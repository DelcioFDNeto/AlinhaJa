// deno-lint-ignore-file no-explicit-any
// ============================================================
// rh-extract-cv — extração estruturada de currículo via IA (RH-3)
// Disparada pelo trigger trg_rh_extract_cv (insert em
// candidato_curriculo, via pg_net com x-webhook-secret).
//
// Fluxo: baixa o arquivo do bucket rh-curriculos → extrai texto
// (PDF: unpdf / DOCX: fflate) → remove PII (S068) → Claude Haiku
// com structured outputs → valida com Zod (S061) → persiste
// formações/experiências/habilidades + resumo/score → registra
// custo em ia_usage_log (S067/S069).
//
// Fallback (S064/S065): falha marca candidato.extracao='falhou',
// com 1 retry automático após 30s. O candidato nunca é bloqueado.
//
// BYOK: a chave da Anthropic é POR ORGANIZAÇÃO, lida do Vault via
// RPC get_org_ai_key (service role). Não há chave global no env —
// empresa sem chave configurada → extracao='falhou' com erro
// 'missing_api_key' (RH preenche manualmente; nada trava — S064).
//
// Secrets: WEBHOOK_SECRET (mesma do Vault 'webhook_secret').
// ============================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import Anthropic from 'npm:@anthropic-ai/sdk';
import OpenAI from 'npm:openai@4.67.3';
import { GoogleGenerativeAI } from 'npm:@google/generative-ai@0.21.0';
import { z } from 'npm:zod@3.23.8';
import { extractText, getDocumentProxy } from 'npm:unpdf@0.12.1';
import { unzipSync, strFromU8 } from 'npm:fflate@0.8.2';

// ── Provedores de IA suportados (BYOK multi-tenant) ──────────
// Cada org escolhe o provedor ativo (organizations.settings.ai_provider);
// a chave correspondente vem do Vault via get_org_ai_key. Modelos e
// preços (USD por MTok) usam sempre o tier mais barato de cada um.
const PROVIDERS: Record<string, { model: string; priceIn: number; priceOut: number }> = {
  anthropic: { model: 'claude-haiku-4-5', priceIn: 1.0, priceOut: 5.0 },
  openai: { model: 'gpt-4o-mini', priceIn: 0.15, priceOut: 0.60 },
  gemini: { model: 'gemini-2.0-flash', priceIn: 0.10, priceOut: 0.40 },
  // Usando extração de texto livre (sem response_format strict/json_object) pois a
  // engine de formatação do Groq (400 Failed to generate JSON) é instável para payloads
  // complexos. Llama-3.3-70b-versatile é superior em qualidade, então nós apenas 
  // limpamos o markdown do retorno e deixamos o Zod validar.
  groq: { model: 'llama-3.3-70b-versatile', priceIn: 0.20, priceOut: 0.60 },
};

const GROQ_BASE_URL = 'https://api.groq.com/openai/v1';

// Descrição do formato para provedores sem json_schema nativo (Gemini/Groq).
// A saída ainda é validada por Zod (S061), então o hint é só orientação.
const JSON_SHAPE_HINT =
  '\n\nRetorne SOMENTE um JSON válido com exatamente estas chaves: ' +
  'formacoes (array de objetos {instituicao, curso, grau, ano_inicio, ano_fim}), ' +
  'experiencias (array de objetos {empresa, cargo, descricao, data_inicio, data_fim}), ' +
  'habilidades (array de strings), idiomas (array de strings), ' +
  'certificacoes (array de strings), resumo_executivo (string), ' +
  'score_completude (inteiro de 0 a 100). Datas no formato YYYY-MM-DD. ' +
  'Campos desconhecidos como null.';

// Prompt deliberadamente duro contra alucinação. O modo de falha observado
// em produção não foi erro de leitura, foi *preenchimento de template*: com
// um currículo enxuto, o modelo completava a ficha com dados plausíveis mas
// inexistentes (empresas "[Empresa1]", faculdade trocada, idiomas e
// certificações que ninguém declarou). As regras abaixo dizem explicitamente
// que uma extração curta é o resultado certo — e a checagem de ancoragem
// (enforceGrounding) descarta o que sobrar, porque prompt sozinho não basta.
const SYSTEM_PROMPT = [
  'Você é um extrator LITERAL de dados de currículos em português.',
  '',
  'REGRAS INEGOCIÁVEIS:',
  '1. Copie apenas o que está escrito no texto. Nunca deduza, complete,',
  '   estime nem "melhore" nada. Se a informação não está escrita, o campo',
  '   é null e o array fica vazio.',
  '2. É PROIBIDO inventar empresas, instituições, cargos, cursos, datas,',
  '   idiomas ou certificações. Currículo curto gera extração curta — isso',
  '   é o resultado CORRETO, não uma falha sua.',
  '3. NUNCA use rótulos genéricos como "[Empresa1]", "Empresa X", "N/A",',
  '   "-" ou "Não informado". Nesses casos, use null.',
  '4. O texto foi anonimizado antes de chegar até você: [NOME], [EMAIL],',
  '   [TELEFONE] e [CPF] marcam dados pessoais removidos. Eles NÃO são',
  '   conteúdo — ignore-os e jamais os copie para a saída.',
  '5. Datas: use somente anos e meses que aparecem literalmente no texto.',
  '   Sem data escrita, use null — não estime pela ordem dos empregos.',
  '6. habilidades/idiomas/certificações: extraia os termos como aparecem.',
  '   Não acrescente o idioma nativo presumido, habilidades "esperadas"',
  '   para a área, nem transforme um curso em "certificado".',
  '7. resumo_executivo: 2 a 4 frases em TERCEIRA pessoa, descrevendo apenas',
  '   o que o texto comprova. Nunca em primeira pessoa e nunca copiando o',
  '   objetivo profissional do candidato como se fosse sua análise.',
  '8. score_completude (0-100): mede o quanto o currículo está completo',
  '   (contato, formação, experiências datadas, habilidades claras).',
  '   Currículo enxuto recebe score baixo — não compense inventando dados.',
].join('\n');

const userPrompt = (scrubbed: string) =>
  'Extraia os dados estruturados deste currículo. Só existe o que está ' +
  'entre as marcas abaixo; qualquer coisa fora disso é invenção.\n\n' +
  `<<<CURRICULO\n${scrubbed}\nCURRICULO>>>`;

const MAX_OUTPUT_TOKENS = 4096; // S066
const MAX_CV_CHARS = 24000;

const strOrNull = z.preprocess((v) => {
  if (v === null || v === undefined) return null;
  const s = String(v).trim();
  return s.length > 0 ? s : null;
}, z.string().nullable());

const numOrNull = z.preprocess((v) => {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return Math.round(v);
  if (typeof v === 'string') {
    const n = parseInt(v.trim(), 10);
    return isNaN(n) ? null : n;
  }
  return null;
}, z.number().int().nullable());

// ── Schema da extração (S060/S061) ───────────────────────────
const ExtractionSchema = z.object({
  formacoes: z.array(z.object({
    instituicao: strOrNull,
    curso: strOrNull,
    grau: strOrNull,
    ano_inicio: numOrNull,
    ano_fim: numOrNull,
  })),
  experiencias: z.array(z.object({
    empresa: strOrNull,
    cargo: strOrNull,
    descricao: strOrNull,
    data_inicio: strOrNull, // YYYY-MM-DD, YYYY-MM ou YYYY
    data_fim: strOrNull,
  })),
  habilidades: z.array(z.string()),
  idiomas: z.array(z.string()),
  certificacoes: z.array(z.string()),
  resumo_executivo: z.string(),
  score_completude: z.preprocess(
    (v) => (typeof v === 'string' ? parseInt(v, 10) || 50 : v),
    z.number().int().min(0).max(100),
  ),
});

const jsonSchema = {
  type: 'object',
  additionalProperties: false,
  required: [
    'formacoes', 'experiencias', 'habilidades', 'idiomas',
    'certificacoes', 'resumo_executivo', 'score_completude',
  ],
  properties: {
    formacoes: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['instituicao', 'curso', 'grau', 'ano_inicio', 'ano_fim'],
        properties: {
          instituicao: { type: ['string', 'null'] },
          curso: { type: ['string', 'null'] },
          grau: { type: ['string', 'null'] },
          ano_inicio: { type: ['integer', 'null'] },
          ano_fim: { type: ['integer', 'null'] },
        },
      },
    },
    experiencias: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['empresa', 'cargo', 'descricao', 'data_inicio', 'data_fim'],
        properties: {
          empresa: { type: ['string', 'null'] },
          cargo: { type: ['string', 'null'] },
          descricao: { type: ['string', 'null'] },
          data_inicio: { type: ['string', 'null'], description: 'YYYY-MM-DD; use dia 01 se desconhecido' },
          data_fim: { type: ['string', 'null'], description: 'YYYY-MM-DD; null se emprego atual' },
        },
      },
    },
    habilidades: { type: 'array', items: { type: 'string' } },
    idiomas: { type: 'array', items: { type: 'string' } },
    certificacoes: { type: 'array', items: { type: 'string' } },
    resumo_executivo: {
      type: 'string',
      description: 'Um parágrafo em português sintetizando o perfil profissional, sem citar o nome do candidato',
    },
    score_completude: {
      type: 'integer',
      description: 'Qualidade/completude do currículo de 0 a 100',
    },
  },
};

Deno.serve(async (req: Request) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Autenticação do webhook (fail-closed). Esta função lê chaves de IA
  // do Vault e processa currículos com PII — sem secret, recusamos.
  const expected = (Deno.env.get('WEBHOOK_SECRET') ?? '').trim();
  const received = (req.headers.get('x-webhook-secret') ?? '').trim();
  console.log(`[rh-extract-cv] auth debug: exp=${expected.slice(0, 8)}... (len ${expected.length}), rec=${received.slice(0, 8)}... (len ${received.length})`);
  if (!expected) {
    console.error('[rh-extract-cv] WEBHOOK_SECRET não configurada — recusando');
    return json({ error: 'server misconfigured' }, 503);
  }
  if (received !== expected) {
    console.error(`[rh-extract-cv] auth mismatch! expected len=${expected.length}, received len=${received.length}`);
    return json({ error: 'unauthorized' }, 401);
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid payload' }, 400);
  }
  const record = body?.record;
  const attempt = Number(body?.attempt ?? 1);
  if (!record?.id || !record?.candidato_id) {
    return json({ error: 'missing record' }, 400);
  }

  const started = Date.now();
  let orgId: string | null = null;
  let modeloUsado: string | null = null;

  try {
    // ── Candidato + marca 'processando' ──────────────────────
    const { data: candidato, error: candErr } = await supabase
      .from('candidato')
      .select('id, organization_id, nome, email, telefone')
      .eq('id', record.candidato_id)
      .single();
    if (candErr || !candidato) throw new Error(`candidato não encontrado: ${candErr?.message}`);
    orgId = candidato.organization_id;

    await supabase.from('candidato')
      .update({ extracao: 'processando' })
      .eq('id', candidato.id);

    // ── Download + parse ─────────────────────────────────────
    const { data: blob, error: dlErr } = await supabase.storage
      .from('rh-curriculos')
      .download(record.arquivo_url);
    if (dlErr || !blob) throw new Error(`download falhou: ${dlErr?.message}`);
    const bytes = new Uint8Array(await blob.arrayBuffer());

    let texto = record.tipo_arquivo === 'docx'
      ? extractDocxText(bytes)
      : await extractPdfText(bytes);
    texto = texto.replace(/\s+/g, ' ').trim();
    if (texto.length < 50) {
      throw new Error('texto extraído insuficiente (arquivo pode ser imagem/escaneado)');
    }

    // ── Minimização de dados (S068): remover PII antes da API ─
    const scrubbed = scrubPii(texto, candidato).slice(0, MAX_CV_CHARS);

    // ── BYOK multi-provedor: provedor ativo + chave (Vault) ──
    const { data: org } = await supabase
      .from('organizations')
      .select('settings')
      .eq('id', orgId)
      .single();
    const provider = (org?.settings?.ai_provider as string) ?? 'anthropic';
    const cfg = PROVIDERS[provider] ?? PROVIDERS.anthropic;
    modeloUsado = cfg.model;

    const { data: apiKey, error: keyErr } = await supabase
      .rpc('get_org_ai_key', { p_org_id: orgId, p_provider: provider });
    if (keyErr) throw new Error(`falha ao ler chave de IA: ${keyErr.message}`);
    if (!apiKey) {
      const e: any = new Error(
        `missing_api_key: organização não possui chave de API (${provider}) configurada`);
      e.noRetry = true; // repetir em 30s não resolve ausência de chave
      throw e;
    }

    // ── Extração via provedor ativo (structured outputs) ─────
    const { jsonText, usageIn, usageOut } =
      await runExtraction(provider, apiKey, scrubbed);

    // Validação Zod — protege contra respostas malformadas (S061)
    const parsed = ExtractionSchema.parse(JSON.parse(jsonText));

    // Ancoragem (S061b) — só sobrevive o que existe no currículo. Vale
    // para todos os provedores: nenhum deles é confiável o bastante para
    // gravarmos direto na ficha do candidato.
    const { extracted, descartados } = enforceGrounding(parsed, texto);
    if (descartados.length) {
      console.warn(
        `[rh-extract-cv] ${descartados.length} item(ns) sem ancoragem ` +
        `descartado(s): ${descartados.slice(0, 10).join(' | ')}`,
      );
    }

    // ── Persistência (limpa extrações anteriores de origem IA) ─
    await supabase.from('candidato_formacao').delete().eq('candidato_id', candidato.id);
    await supabase.from('candidato_experiencia').delete().eq('candidato_id', candidato.id);
    await supabase.from('candidato_habilidade')
      .delete().eq('candidato_id', candidato.id).eq('origem', 'ia');

    if (extracted.formacoes.length) {
      await supabase.from('candidato_formacao').insert(
        extracted.formacoes.map((f) => ({ candidato_id: candidato.id, ...f })));
    }
    if (extracted.experiencias.length) {
      await supabase.from('candidato_experiencia').insert(
        extracted.experiencias.map((e) => ({
          candidato_id: candidato.id,
          empresa: e.empresa, cargo: e.cargo, descricao: e.descricao,
          data_inicio: normDate(e.data_inicio), data_fim: normDate(e.data_fim),
        })));
    }
    const tags = dedupe([
      ...extracted.habilidades,
      ...extracted.idiomas,
      ...extracted.certificacoes,
    ]).slice(0, 40);
    if (tags.length) {
      await supabase.from('candidato_habilidade').upsert(
        tags.map((nome) => ({ candidato_id: candidato.id, nome, origem: 'ia' })),
        { onConflict: 'candidato_id,nome', ignoreDuplicates: true });
    }

    await supabase.from('candidato').update({
      resumo_executivo: extracted.resumo_executivo,
      score_completude: extracted.score_completude,
      extracao: 'extraido',
    }).eq('id', candidato.id);

    await supabase.from('candidato_curriculo')
      .update({ texto_extraido: texto.slice(0, 50000) })
      .eq('id', record.id);

    await supabase.from('candidato_historico').insert({
      candidato_id: candidato.id,
      acao: 'extracao_ia',
      detalhes: {
        score: extracted.score_completude,
        tags: tags.length,
        // Auditoria: o que a IA produziu mas não estava no currículo. Se
        // este número cresce, o provedor ativo está alucinando.
        descartados: descartados.length,
        ...(descartados.length
          ? { descartados_exemplos: descartados.slice(0, 10) }
          : {}),
      },
    });

    // ── Log de uso/custo (S067/S069) ─────────────────────────
    const cfgUsed = PROVIDERS[provider] ?? PROVIDERS.anthropic;
    await supabase.from('ia_usage_log').insert({
      organization_id: orgId,
      candidato_id: candidato.id,
      funcao: 'rh-extract-cv',
      modelo: cfgUsed.model,
      tokens_input: usageIn,
      tokens_output: usageOut,
      custo_estimado:
        (usageIn * cfgUsed.priceIn + usageOut * cfgUsed.priceOut) / 1e6,
      sucesso: true,
      duracao_ms: Date.now() - started,
    });

    return json({ success: true, score: extracted.score_completude });
  } catch (error: any) {
    console.error(`[rh-extract-cv] attempt ${attempt} error:`, error);

    await supabase.from('candidato')
      .update({ extracao: 'falhou' })
      .eq('id', record.candidato_id);
    const isMissingKey = String(error?.message ?? '').startsWith('missing_api_key');
    await supabase.from('ia_usage_log').insert({
      organization_id: orgId,
      candidato_id: record.candidato_id,
      funcao: 'rh-extract-cv',
      // modelo null quando a empresa não configurou chave — permite ao
      // dashboard separar "falha técnica" de "não configurado"
      modelo: isMissingKey ? null : modeloUsado,
      sucesso: false,
      erro: String(error?.message ?? error).slice(0, 500),
      duracao_ms: Date.now() - started,
    });

    // Retry único após 30s (S065) — exceto quando não há chave
    if (attempt < 2 && !error?.noRetry) {
      const retry = (async () => {
        await new Promise((r) => setTimeout(r, 30_000));
        await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/rh-extract-cv`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-webhook-secret': expected,
            'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
          },
          body: JSON.stringify({ record, attempt: attempt + 1 }),
        }).catch((e) => console.error('[rh-extract-cv] retry dispatch failed:', e));
      })();
      // @ts-ignore EdgeRuntime existe no ambiente Supabase
      if (typeof EdgeRuntime !== 'undefined') EdgeRuntime.waitUntil(retry);
    }

    return json({ error: 'extraction failed', attempt }, 500);
  }
});

// ── Dispatch por provedor ─────────────────────────────────────
// Cada função retorna o JSON bruto (validado depois com Zod) + tokens.
type ExtractionResult = { jsonText: string; usageIn: number; usageOut: number };

async function runExtraction(
  provider: string,
  apiKey: string,
  scrubbed: string,
): Promise<ExtractionResult> {
  switch (provider) {
    case 'openai':
      return await extractOpenAI(apiKey, scrubbed);
    case 'gemini':
      return await extractGemini(apiKey, scrubbed);
    case 'groq':
      return await extractGroq(apiKey, scrubbed);
    default:
      return await extractAnthropic(apiKey, scrubbed);
  }
}

async function extractGroq(apiKey: string, scrubbed: string): Promise<ExtractionResult> {
  const groq = new OpenAI({ apiKey, baseURL: GROQ_BASE_URL });
  const resp = await groq.chat.completions.create({
    model: PROVIDERS.groq.model,
    max_tokens: MAX_OUTPUT_TOKENS,
    temperature: 0, // extração é cópia, não redação — sem criatividade
    messages: [
      {
        role: 'system',
        content: SYSTEM_PROMPT + JSON_SHAPE_HINT + 
          '\n\nRetorne EXATAMENTE e APENAS o JSON. Não adicione nenhum texto antes ou depois.',
      },
      { role: 'user', content: userPrompt(scrubbed) },
    ],
  });
  const choice = resp.choices[0];
  let text = choice?.message?.content;
  if (!text) throw new Error('resposta sem conteúdo de texto');
  
  // Extração robusta: encontra o primeiro '{' e o último '}' para ignorar qualquer
  // texto extra (preâmbulos, markdown, explicações) que o modelo possa ter gerado.
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start !== -1 && end !== -1 && end >= start) {
    text = text.substring(start, end + 1);
  } else {
    // Fallback: limpa markdown básico caso não ache chaves (improvável para esse prompt)
    text = text.replace(/```json/gi, '').replace(/```/g, '').trim();
  }

  return {
    jsonText: text,
    usageIn: resp.usage?.prompt_tokens ?? 0,
    usageOut: resp.usage?.completion_tokens ?? 0,
  };
}

async function extractAnthropic(apiKey: string, scrubbed: string): Promise<ExtractionResult> {
  const anthropic = new Anthropic({ apiKey });
  const response = await anthropic.messages.create({
    model: PROVIDERS.anthropic.model,
    max_tokens: MAX_OUTPUT_TOKENS,
    temperature: 0,
    system: SYSTEM_PROMPT,
    messages: [{ role: 'user', content: userPrompt(scrubbed) }],
    output_config: { format: { type: 'json_schema', schema: jsonSchema } },
  } as any);

  if (response.stop_reason === 'refusal') {
    throw new Error('modelo recusou a solicitação');
  }
  const textBlock = (response.content as any[]).find((b) => b.type === 'text');
  if (!textBlock) throw new Error('resposta sem conteúdo de texto');
  return {
    jsonText: textBlock.text,
    usageIn: response.usage.input_tokens,
    usageOut: response.usage.output_tokens,
  };
}

async function extractOpenAI(apiKey: string, scrubbed: string): Promise<ExtractionResult> {
  const openai = new OpenAI({ apiKey });
  const resp = await openai.chat.completions.create({
    model: PROVIDERS.openai.model,
    max_tokens: MAX_OUTPUT_TOKENS,
    temperature: 0,
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: userPrompt(scrubbed) },
    ],
    response_format: {
      type: 'json_schema',
      json_schema: { name: 'curriculo', strict: true, schema: jsonSchema },
    },
  });
  const choice = resp.choices[0];
  if (choice?.finish_reason === 'content_filter') {
    throw new Error('modelo recusou a solicitação');
  }
  const text = choice?.message?.content;
  if (!text) throw new Error('resposta sem conteúdo de texto');
  return {
    jsonText: text,
    usageIn: resp.usage?.prompt_tokens ?? 0,
    usageOut: resp.usage?.completion_tokens ?? 0,
  };
}

async function extractGemini(apiKey: string, scrubbed: string): Promise<ExtractionResult> {
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: PROVIDERS.gemini.model,
    systemInstruction: SYSTEM_PROMPT,
    generationConfig: {
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      responseMimeType: 'application/json',
      temperature: 0,
    },
  });
  // O Gemini não aceita o mesmo json_schema; guiamos pelo prompt e
  // validamos com Zod depois (mesma proteção S061).
  const result = await model.generateContent(userPrompt(scrubbed) + JSON_SHAPE_HINT);
  const text = result.response.text();
  if (!text) throw new Error('resposta sem conteúdo de texto');
  const usage = result.response.usageMetadata;
  return {
    jsonText: text,
    usageIn: usage?.promptTokenCount ?? 0,
    usageOut: usage?.candidatesTokenCount ?? 0,
  };
}

// ── Parsers ───────────────────────────────────────────────────
async function extractPdfText(bytes: Uint8Array): Promise<string> {
  const pdf = await getDocumentProxy(bytes);
  const { text } = await extractText(pdf, { mergePages: true });
  return typeof text === 'string' ? text : (text as string[]).join('\n');
}

function extractDocxText(bytes: Uint8Array): string {
  const files = unzipSync(bytes);
  const doc = files['word/document.xml'];
  if (!doc) throw new Error('DOCX sem word/document.xml');
  let xml = strFromU8(doc);
  xml = xml.replace(/<w:tab[^>]*\/>/g, '\t').replace(/<\/w:p>/g, '\n');
  return xml.replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#(\d+);/g, (_, d) => String.fromCharCode(+d));
}

// ── Ancoragem no texto original (S061b — anti-alucinação) ─────
// Segunda linha de defesa: o prompt pede para não inventar, isto CONFERE.
// Cada valor que a IA devolveu precisa aparecer no currículo; o que não
// aparece é descartado antes de virar ficha do candidato. Preferimos uma
// ficha incompleta (que o RH completa à mão) a uma ficha errada — uma
// faculdade trocada ou uma experiência inventada contamina a triagem e o
// candidato é julgado por dados que não são dele.

type Extraction = z.infer<typeof ExtractionSchema>;

/// Rótulos genéricos que o modelo usa quando não sabe a resposta.
const PLACEHOLDER_RE =
  /\[|\]|\b(n\.?\/?a|nao informado|não informado|desconhecid[oa]|empresa\s*[0-9x]|instituicao\s*[0-9x]|instituição\s*[0-9x]|x{3,})\b/i;

/// Quantas letras iniciais formam o radical usado na comparação. Absorve
/// flexão ("trabalhar"/"trabalho") sem aproximar palavras diferentes.
const STEM_LEN = 5;

/// Remove acentos sem usar faixa de combining marks literal no fonte —
/// esses caracteres não sobrevivem a toda cadeia de edição em Windows.
function stripAccents(s: string): string {
  let out = '';
  for (const ch of s.normalize('NFD')) {
    const c = ch.codePointAt(0)!;
    if (c >= 0x300 && c <= 0x36f) continue; // marca de combinação
    out += ch;
  }
  return out;
}

function normalizeText(s: string): string {
  return stripAccents(s)
    .toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function stemsOf(normalized: string): Set<string> {
  const out = new Set<string>();
  for (const t of normalized.split(' ')) {
    if (t.length >= 3) out.add(t.slice(0, STEM_LEN));
  }
  return out;
}

/// Aparece no currículo exatamente como sequência de palavras.
function isLiteral(value: string | null | undefined, hay: string): boolean {
  if (!value || PLACEHOLDER_RE.test(value)) return false;
  const norm = normalizeText(value);
  return norm.length > 0 && hay.includes(` ${norm} `);
}

/// Aparece literalmente OU todas as suas palavras significativas aparecem
/// (tolerante a flexão). Usado em habilidades, onde "Trabalho em equipe"
/// legitimamente resume "aptidão para trabalhar em equipe".
function isGrounded(
  value: string | null | undefined, hay: string, stems: Set<string>,
): boolean {
  if (!value || PLACEHOLDER_RE.test(value)) return false;
  if (isLiteral(value, hay)) return true;
  const toks = normalizeText(value).split(' ').filter((t) => t.length >= 4);
  // Só termos curtos (siglas como "SQL", "UFPA") e nenhum casamento
  // literal: não há como confirmar, então cai fora.
  if (toks.length === 0) return false;
  return toks.every((t) => stems.has(t.slice(0, STEM_LEN)));
}

/// Ano só vale se estiver escrito no currículo — impede o modelo de
/// "datar" empregos pela ordem em que os listou.
function anoAncorado(ano: number | null, hay: string): number | null {
  return ano != null && hay.includes(String(ano)) ? ano : null;
}

function dataAncorada(d: string | null, hay: string): string | null {
  const norm = normDate(d);
  if (!norm) return null;
  return hay.includes(norm.slice(0, 4)) ? norm : null;
}

function enforceGrounding(
  ex: Extraction, texto: string,
): { extracted: Extraction; descartados: string[] } {
  const hay = ` ${normalizeText(texto)} `;
  const stems = stemsOf(hay);
  const descartados: string[] = [];
  const ok = (v: string | null | undefined) => isGrounded(v, hay, stems);

  // Formação: âncora é a instituição ou o curso (há currículos que citam
  // só um dos dois). Os demais campos são zerados individualmente.
  const formacoes = ex.formacoes.filter((f) => {
    if (ok(f.instituicao) || ok(f.curso)) return true;
    descartados.push(`formacao: ${f.curso ?? f.instituicao ?? '?'}`);
    return false;
  }).map((f) => ({
    instituicao: ok(f.instituicao) ? f.instituicao : null,
    curso: ok(f.curso) ? f.curso : null,
    grau: ok(f.grau) ? f.grau : null,
    ano_inicio: anoAncorado(f.ano_inicio, hay),
    ano_fim: anoAncorado(f.ano_fim, hay),
  }));

  // Experiência: exige a EMPRESA ancorada, ou um cargo que apareça
  // literalmente (currículos que descrevem o cargo sem citar o empregador).
  // Radical não serve aqui: "Programador" casaria com "Programação" da
  // seção de habilidades e ressuscitaria justamente o emprego inventado.
  const experiencias = ex.experiencias.filter((e) => {
    if (ok(e.empresa) || isLiteral(e.cargo, hay)) return true;
    descartados.push(`experiencia: ${e.cargo ?? '?'} @ ${e.empresa ?? '?'}`);
    return false;
  }).map((e) => ({
    empresa: ok(e.empresa) ? e.empresa : null,
    cargo: ok(e.cargo) ? e.cargo : null,
    // A descrição é paráfrase das atividades — exigir ancoragem literal
    // derrubaria descrições legítimas. Barramos só o rótulo genérico.
    descricao: e.descricao && !PLACEHOLDER_RE.test(e.descricao)
      ? e.descricao
      : null,
    data_inicio: dataAncorada(e.data_inicio, hay),
    data_fim: dataAncorada(e.data_fim, hay),
  }));

  const filtraLista = (lista: string[], rotulo: string) =>
    lista.filter((v) => {
      if (ok(v)) return true;
      descartados.push(`${rotulo}: ${v}`);
      return false;
    });

  const habilidades = filtraLista(ex.habilidades, 'habilidade');
  const idiomas = filtraLista(ex.idiomas, 'idioma');
  const certificacoes = filtraLista(ex.certificacoes, 'certificacao');

  return {
    extracted: {
      formacoes,
      experiencias,
      habilidades,
      idiomas,
      certificacoes,
      // Marca de redação que vazou para o resumo vira texto sem sentido na
      // ficha ("atuou na [NOME] como...") — sai fora.
      resumo_executivo: ex.resumo_executivo
        .replace(/\[(NOME|EMAIL|TELEFONE|CPF)\]/g, '')
        .replace(/\s{2,}/g, ' ')
        .trim(),
      // O score vinha da extração cheia; depois do corte ele mediria um
      // currículo que não existe. O teto abaixo o traz de volta ao que
      // sobrou — sempre para baixo, nunca inflando a nota do modelo.
      score_completude: Math.min(
        ex.score_completude,
        tetoDeScore({ formacoes, experiencias, habilidades, idiomas, certificacoes }),
      ),
    },
    descartados,
  };
}

/// Teto determinístico do score, a partir só do que ficou comprovado.
function tetoDeScore(d: {
  formacoes: unknown[];
  experiencias: { data_inicio: string | null }[];
  habilidades: unknown[];
  idiomas: unknown[];
  certificacoes: unknown[];
}): number {
  let s = 20; // currículo legível já vale a base
  if (d.formacoes.length) s += 20;
  // Experiência sem data não comprova tempo de casa — vale menos.
  s += Math.min(30, d.experiencias.filter((e) => e.data_inicio).length * 15);
  s += Math.min(10, d.experiencias.length * 5);
  if (d.habilidades.length >= 3) s += 15;
  if (d.idiomas.length) s += 5;
  if (d.certificacoes.length) s += 5;
  return Math.min(100, s);
}

// ── Minimização de dados (S068) ───────────────────────────────
function scrubPii(
  texto: string,
  c: { nome: string; email: string; telefone: string | null },
): string {
  let out = texto;
  // E-mails e telefones (quaisquer, não só os do cadastro)
  out = out.replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, '[EMAIL]');
  out = out.replace(/(\+?55\s?)?\(?\d{2}\)?\s?9?\d{4}[-\s]?\d{4}/g, '[TELEFONE]');
  // CPF
  out = out.replace(/\d{3}\.?\d{3}\.?\d{3}-?\d{2}/g, '[CPF]');
  // Nome do candidato (tokens com 3+ letras). \b evita apagar o token
  // quando ele aparece como substring de outra palavra (ex.: nome "Ana"
  // não deve zerar "Banana"/"Analista").
  for (const parte of c.nome.split(/\s+/).filter((p) => p.length >= 3)) {
    out = out.replace(new RegExp(`\\b${escapeRegex(parte)}\\b`, 'gi'), '[NOME]');
  }
  return out;
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function normDate(d: string | null): string | null {
  if (!d) return null;
  if (/^\d{4}$/.test(d)) return `${d}-01-01`;
  if (/^\d{4}-\d{2}$/.test(d)) return `${d}-01`;
  if (/^\d{4}-\d{2}-\d{2}$/.test(d)) return d;
  return null;
}

function dedupe(arr: string[]): string[] {
  const seen = new Set<string>();
  return arr.filter((s) => {
    const k = s.trim().toLowerCase();
    if (!k || seen.has(k)) return false;
    seen.add(k);
    return true;
  }).map((s) => s.trim());
}

function json(data: Record<string, any>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
