// deno-lint-ignore-file no-explicit-any
// ============================================================
// rh-gerar-questoes — geração de questões técnicas por IA (RH-12)
// Chamada pela Central (RH autenticado) via supabase.functions.invoke.
//
// Fluxo: valida o JWT do usuário → confirma rh_banco_talentos:manage (RBAC)
// → lê o provedor ativo + chave BYOK da org (Vault, service_role) →
// gera N questões de múltipla escolha (reuso do dispatch multi-provedor
// do rh-extract-cv) → valida com Zod → persiste em `questao` (origem='ia')
// COMO O USUÁRIO (RLS + trg_force_org carimbam a org) → loga custo em
// ia_usage_log. Teto de 15 questões (controle de custo — plano Fase 3).
// ============================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import Anthropic from 'npm:@anthropic-ai/sdk';
import OpenAI from 'npm:openai@4.67.3';
import { GoogleGenerativeAI } from 'npm:@google/generative-ai@0.21.0';
import { z } from 'npm:zod@3.23.8';

import { corsHeadersFor } from '../_shared/cors.ts';

const PROVIDERS: Record<string, { model: string; priceIn: number; priceOut: number }> = {
  anthropic: { model: 'claude-haiku-4-5', priceIn: 1.0, priceOut: 5.0 },
  openai: { model: 'gpt-4o-mini', priceIn: 0.15, priceOut: 0.60 },
  gemini: { model: 'gemini-2.0-flash', priceIn: 0.10, priceOut: 0.40 },
  groq: { model: 'llama-3.3-70b-versatile', priceIn: 0.20, priceOut: 0.60 },
};
const GROQ_BASE_URL = 'https://api.groq.com/openai/v1';
const MAX_OUTPUT_TOKENS = 4096;
const MAX_QUESTOES = 15; // teto de custo (Fase 3)

const QuestoesSchema = z.object({
  questoes: z.array(z.object({
    enunciado: z.string().min(5).max(1000),
    opcoes: z.array(z.string().min(1).max(300)).min(2).max(6),
    correta_idx: z.number().int().min(0),
  })).min(1),
});

const jsonSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['questoes'],
  properties: {
    questoes: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['enunciado', 'opcoes', 'correta_idx'],
        properties: {
          enunciado: { type: 'string', description: 'Enunciado claro e objetivo da questão' },
          opcoes: {
            type: 'array',
            items: { type: 'string' },
            description: '4 alternativas plausíveis; apenas uma correta',
          },
          correta_idx: { type: 'integer', description: 'Índice (0-based) da alternativa correta em opcoes' },
        },
      },
    },
  },
};

const SYSTEM_PROMPT =
  'Você é um especialista em recrutamento técnico que elabora provas objetivas ' +
  'em português do Brasil. Gere questões de múltipla escolha claras, sem ambiguidade, ' +
  'com exatamente uma alternativa correta e distratores plausíveis. Não repita questões. ' +
  'Não numere as alternativas dentro do texto — devolva apenas o conteúdo de cada opção.';

const JSON_SHAPE_HINT =
  '\n\nRetorne SOMENTE um JSON válido: {"questoes": [{"enunciado": string, ' +
  '"opcoes": [string, ...] (4 alternativas), "correta_idx": inteiro 0-based}]}. ' +
  'Sem texto antes ou depois do JSON.';

function userPrompt(cargo: string, nivel: string, qtd: number): string {
  const nivelTxt = nivel ? ` de nível ${nivel}` : '';
  return `Gere ${qtd} questões de múltipla escolha (4 alternativas cada) para avaliar ` +
    `tecnicamente um candidato ao cargo de "${cargo}"${nivelTxt}. ` +
    `As questões devem cobrir conhecimentos práticos e teóricos relevantes ao cargo.`;
}

Deno.serve(async (req: Request) => {
  // CORS restrito à allowlist: roda com o JWT do usuário RH e consome
  // crédito de IA da organização.
  const corsHeaders = corsHeadersFor(req);
  // Os cabeçalhos de CORS dependem da origem desta requisição: o helper de
  // resposta é criado aqui. Enquanto `json` era de módulo e lia
  // `corsHeaders` daqui, toda resposta lançava ReferenceError e a geração
  // de questões falhava com erro de CORS no navegador.
  const json = jsonWith(corsHeaders);

  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const authHeader = req.headers.get('Authorization') ?? '';

  // Cliente no contexto do usuário (RLS + auth.uid()) e cliente admin
  // (Vault). A geração escreve como o usuário; a chave só o service_role lê.
  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
  });
  const admin = createClient(url, serviceRole);

  const started = Date.now();
  let orgId: string | null = null;
  let modeloUsado: string | null = null;

  try {
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: 'Não autenticado.' }, 401);

    // Autorização: quem gere o Banco de Talentos (RBAC) gera questões — a
    // mesma permissão exigida para gravá-las em `questao`. Consome IA.
    const { data: podeGerir } = await userClient.rpc('fn_rh_pode', {
      p_module: 'rh_banco_talentos',
      p_action: 'manage',
    });
    if (podeGerir !== true) {
      return json({ error: 'Sem permissão para gerar questões no Banco de Talentos.' }, 403);
    }

    const { data: urow } = await admin
      .from('users').select('organization_id').eq('id', user.id).single();
    orgId = urow?.organization_id ?? null;
    if (!orgId) return json({ error: 'Organização não encontrada.' }, 400);

    const body = await req.json();
    const cargoNome = String(body?.cargo_nome ?? '').trim();
    const nivel = String(body?.nivel ?? '').trim();
    const cargoId = body?.cargo_id ? String(body.cargo_id) : null;
    const areaId = body?.area_id ? String(body.area_id) : null;
    const qtd = Math.min(MAX_QUESTOES, Math.max(1, Number(body?.quantidade ?? 5) || 5));
    if (cargoNome.length < 2) {
      return json({ error: 'Informe o cargo para gerar as questões.' }, 400);
    }

    // Provedor ativo + chave BYOK (Vault, service_role).
    const { data: org } = await admin
      .from('organizations').select('settings').eq('id', orgId).single();
    const provider = (org?.settings?.ai_provider as string) ?? 'anthropic';
    const cfg = PROVIDERS[provider] ?? PROVIDERS.anthropic;
    modeloUsado = cfg.model;

    const { data: apiKey, error: keyErr } = await admin
      .rpc('get_org_ai_key', { p_org_id: orgId, p_provider: provider });
    if (keyErr) throw new Error(`falha ao ler chave de IA: ${keyErr.message}`);
    if (!apiKey) {
      return json({
        error: `Nenhuma chave de IA (${provider}) configurada. ` +
          'Configure em Admin → Chave de IA para gerar questões.',
      }, 400);
    }

    const { jsonText, usageIn, usageOut } =
      await gerar(provider, apiKey, cargoNome, nivel, qtd);

    const parsed = QuestoesSchema.parse(JSON.parse(jsonText));
    // Sanidade: correta_idx dentro do intervalo; corta ao teto.
    const validas = parsed.questoes
      .filter((q) => q.correta_idx < q.opcoes.length)
      .slice(0, qtd);
    if (validas.length === 0) throw new Error('IA não retornou questões válidas.');

    const rows = validas.map((q) => ({
      cargo_id: cargoId,
      area_id: areaId,
      nivel: nivel || null,
      enunciado: q.enunciado.trim(),
      opcoes: q.opcoes,
      correta_idx: q.correta_idx,
      origem: 'ia',
      created_by: user.id,
    }));
    // Insere como o usuário: trg_force_org carimba org; RLS exige rh_banco_talentos:manage.
    const { error: insErr } = await userClient.from('questao').insert(rows);
    if (insErr) throw new Error(`falha ao salvar questões: ${insErr.message}`);

    await admin.from('ia_usage_log').insert({
      organization_id: orgId,
      funcao: 'rh-gerar-questoes',
      modelo: cfg.model,
      tokens_input: usageIn,
      tokens_output: usageOut,
      custo_estimado: (usageIn * cfg.priceIn + usageOut * cfg.priceOut) / 1e6,
      sucesso: true,
      duracao_ms: Date.now() - started,
    });

    return json({ success: true, geradas: rows.length });
  } catch (error: any) {
    console.error('[rh-gerar-questoes] error:', error);
    await admin.from('ia_usage_log').insert({
      organization_id: orgId,
      funcao: 'rh-gerar-questoes',
      modelo: modeloUsado,
      sucesso: false,
      erro: String(error?.message ?? error).slice(0, 500),
      duracao_ms: Date.now() - started,
    });
    return json({ error: 'Não foi possível gerar as questões. Tente novamente.' }, 500);
  }
});

// ── Dispatch por provedor (mesmo padrão do rh-extract-cv) ────
type GenResult = { jsonText: string; usageIn: number; usageOut: number };

async function gerar(
  provider: string, apiKey: string, cargo: string, nivel: string, qtd: number,
): Promise<GenResult> {
  switch (provider) {
    case 'openai': return await genOpenAI(apiKey, cargo, nivel, qtd);
    case 'gemini': return await genGemini(apiKey, cargo, nivel, qtd);
    case 'groq': return await genGroq(apiKey, cargo, nivel, qtd);
    default: return await genAnthropic(apiKey, cargo, nivel, qtd);
  }
}

async function genAnthropic(
  apiKey: string, cargo: string, nivel: string, qtd: number): Promise<GenResult> {
  const anthropic = new Anthropic({ apiKey });
  const resp = await anthropic.messages.create({
    model: PROVIDERS.anthropic.model,
    max_tokens: MAX_OUTPUT_TOKENS,
    system: SYSTEM_PROMPT,
    messages: [{ role: 'user', content: userPrompt(cargo, nivel, qtd) }],
    output_config: { format: { type: 'json_schema', schema: jsonSchema } },
  } as any);
  if (resp.stop_reason === 'refusal') throw new Error('modelo recusou a solicitação');
  const block = (resp.content as any[]).find((b) => b.type === 'text');
  if (!block) throw new Error('resposta sem conteúdo de texto');
  return { jsonText: block.text, usageIn: resp.usage.input_tokens, usageOut: resp.usage.output_tokens };
}

async function genOpenAI(
  apiKey: string, cargo: string, nivel: string, qtd: number): Promise<GenResult> {
  const openai = new OpenAI({ apiKey });
  const resp = await openai.chat.completions.create({
    model: PROVIDERS.openai.model,
    max_tokens: MAX_OUTPUT_TOKENS,
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: userPrompt(cargo, nivel, qtd) },
    ],
    response_format: {
      type: 'json_schema',
      json_schema: { name: 'questoes', strict: true, schema: jsonSchema },
    },
  });
  const text = resp.choices[0]?.message?.content;
  if (!text) throw new Error('resposta sem conteúdo de texto');
  return {
    jsonText: text,
    usageIn: resp.usage?.prompt_tokens ?? 0,
    usageOut: resp.usage?.completion_tokens ?? 0,
  };
}

async function genGemini(
  apiKey: string, cargo: string, nivel: string, qtd: number): Promise<GenResult> {
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: PROVIDERS.gemini.model,
    systemInstruction: SYSTEM_PROMPT,
    generationConfig: {
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      responseMimeType: 'application/json',
    },
  });
  const result = await model.generateContent(userPrompt(cargo, nivel, qtd) + JSON_SHAPE_HINT);
  const text = result.response.text();
  if (!text) throw new Error('resposta sem conteúdo de texto');
  const usage = result.response.usageMetadata;
  return {
    jsonText: text,
    usageIn: usage?.promptTokenCount ?? 0,
    usageOut: usage?.candidatesTokenCount ?? 0,
  };
}

async function genGroq(
  apiKey: string, cargo: string, nivel: string, qtd: number): Promise<GenResult> {
  const groq = new OpenAI({ apiKey, baseURL: GROQ_BASE_URL });
  const resp = await groq.chat.completions.create({
    model: PROVIDERS.groq.model,
    max_tokens: MAX_OUTPUT_TOKENS,
    messages: [
      { role: 'system', content: SYSTEM_PROMPT + JSON_SHAPE_HINT },
      { role: 'user', content: userPrompt(cargo, nivel, qtd) },
    ],
  });
  let text = resp.choices[0]?.message?.content;
  if (!text) throw new Error('resposta sem conteúdo de texto');
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start !== -1 && end !== -1 && end >= start) {
    text = text.substring(start, end + 1);
  } else {
    text = text.replace(/```json/gi, '').replace(/```/g, '').trim();
  }
  return {
    jsonText: text,
    usageIn: resp.usage?.prompt_tokens ?? 0,
    usageOut: resp.usage?.completion_tokens ?? 0,
  };
}

function jsonWith(cors: Record<string, string>) {
  return (data: Record<string, any>, status = 200) =>
    new Response(JSON.stringify(data), {
      status,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
}
