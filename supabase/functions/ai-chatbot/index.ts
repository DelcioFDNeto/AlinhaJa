// deno-lint-ignore-file no-explicit-any
// ============================================================
// ai-chatbot — Assistente IA interno (Groq / Llama)
//
// Disparada pelo trigger trg_ai_chatbot (AFTER INSERT em messages e channel_messages,
// via pg_net com x-webhook-secret) sempre que alguém escreve num
// chat/canal onde o bot "Assistente IA" é membro.
//
// Regras de resposta:
//   • DM (chat.type = 'direct'): responde sempre.
//   • Grupo / Canal: só responde se a mensagem MENCIONAR o bot (@assistente /
//     @ia ou metadata.mentions) OU for uma RESPOSTA a uma mensagem
//     do bot. Evita spam/custo em grupos movimentados.
//
// Contexto: lê as últimas mensagens do chat para "lembrar" do papo.
// Chave da Groq é GLOBAL (Supabase Secret GROQ_API_KEY) — sem BYOK.
// A resposta é inserida em messages/channel_messages como o bot → Realtime + push
// atualizam o app automaticamente.
//
// Especialização: chats.metadata.ai_specialization escolhe a persona
// (geral | rh | ti | administrativo | comercial | pos_venda).
// ============================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import OpenAI from 'npm:openai@4.67.3';
import { APP_BUSINESS_CONTEXT } from './app_context.ts';
import { APP_NAME } from '../_shared/brand.ts';
const BOT_ID = '00000000-0000-4000-a000-000000000001';
const GROQ_BASE_URL = 'https://api.groq.com/openai/v1';
const MODEL = 'llama-3.3-70b-versatile';
const MAX_OUTPUT_TOKENS = 1024;
const HISTORY_LIMIT = 16;
// Preço do tier usado (Groq llama-3.3-70b), USD por MTok — para ia_usage_log.
const PRICE_IN = 0.59;
const PRICE_OUT = 0.79;

/// Prompt-base do assistente para a empresa dona da conversa.
///
/// O nome da empresa vem de `organizations.name` da mensagem que disparou o
/// trigger — nunca de constante ou Secret do deployment. Este projeto é
/// multiempresa: com um nome global no prompt, o colaborador de qualquer
/// cliente ouviria que trabalha no tenant natal (o mesmo defeito que já tinha
/// vazado a marca entre os forks).
function basePrompt(companyName: string | null): string {
  const empresa = companyName ? `da empresa ${companyName}` : 'da empresa';
  return `Você é o "Assistente IA" do ${APP_NAME}, o app corporativo interno ` +
    `${empresa}. Responda em português do Brasil, de forma clara, ` +
    'cordial e objetiva. Ajude os colaboradores com dúvidas sobre processos ' +
    'internos, RH e TI. Você está dentro de uma conversa de chat corporativo: ' +
    'seja conciso (respostas de chat, não relatórios longos). Se não souber ou ' +
    'não tiver acesso a um dado específico (banco de horas, chamados, documentos), ' +
    'diga isso honestamente e oriente o próximo passo. Nunca invente informações ' +
    'internas nem exponha dados sensíveis.\n\n' + APP_BUSINESS_CONTEXT;
}

/// Complemento de cada persona, somado ao prompt-base da empresa.
const SPECIALIZATIONS: Record<string, string> = {
  geral: '',
  rh: '\nSua especialidade é RH: onboarding, documentos, políticas, benefícios e dúvidas trabalhistas gerais.',
  ti: '\nSua especialidade é TI/Helpdesk: dúvidas técnicas, uso dos sistemas e triagem de chamados.',
  administrativo: '\nSua especialidade é administração e processos administrativos internos.',
  comercial: '\nSua especialidade é a área comercial e de vendas.',
  pos_venda: '\nSua especialidade é pós-venda e atendimento ao cliente.',
};

/// Remove identificadores diretos antes de enviar o histórico ao provedor
/// de IA (achado LGPD 2.7).
///
/// O `rh-extract-cv` já removia PII antes de mandar currículo ao modelo
/// (S068), mas aqui o histórico de chat interno seguia cru para a Groq,
/// nos EUA — transferência internacional de dado pessoal sem tratamento
/// (Art. 33). A conversa continua legível para o modelo responder; o que
/// sai são os identificadores que não agregam nada à resposta.
function redactPii(text: string): string {
  return text
    // CPF: 000.000.000-00 ou 00000000000
    .replace(/\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/g, '[CPF]')
    // CNPJ: 00.000.000/0000-00
    .replace(/\b\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2}\b/g, '[CNPJ]')
    // Cartão: 13-16 dígitos agrupados
    .replace(/\b(?:\d[ -]?){13,16}\b/g, '[CARTAO]')
    // E-mail
    .replace(/\b[\w.+-]+@[\w-]+\.[\w.-]+\b/g, '[EMAIL]')
    // Telefone BR com DDD
    .replace(/\b(?:\+55\s?)?\(?\d{2}\)?\s?9?\d{4}[- ]?\d{4}\b/g, '[TELEFONE]');
}

Deno.serve(async (req: Request) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // ── Autenticação do webhook (fail-closed) ────────────────
  // Esta função insere/apaga mensagens como o bot. Sem WEBHOOK_SECRET
  // configurada NÃO aceitamos a chamada — uma requisição forjada poderia
  // apagar históricos (/limpar) ou postar em qualquer chat.
  // `.trim()` nos dois lados: `supabase secrets set` costuma gravar o valor com
  // um \n final, e o header chega sem ele — sem o trim a comparação falha e o
  // bot recusa o webhook em silêncio, sem nada no log que aponte a causa.
  const expected = (Deno.env.get('WEBHOOK_SECRET') ?? '').trim();
  const received = (req.headers.get('x-webhook-secret') ?? '').trim();
  if (!expected) {
    console.error('[ai-chatbot] WEBHOOK_SECRET não configurada — recusando');
    return json({ error: 'server misconfigured' }, 503);
  }
  if (received !== expected) {
    // Resposta opaca de propósito: devolver o comprimento do segredo (ou
    // logá-lo) entrega ao atacante o tamanho exato do alvo de força bruta.
    console.error('[ai-chatbot] webhook secret mismatch — recusando');
    return json({ error: 'unauthorized' }, 401);
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid payload' }, 400);
  }

  const clientRecord = body?.record;
  const tableName = body?.table === 'channel_messages' ? 'channel_messages' : 'messages';
  const isChannel = tableName === 'channel_messages';
  const idField = isChannel ? 'channel_id' : 'chat_id';

  if (!clientRecord?.id) return json({ error: 'missing record' }, 400);

  const started = Date.now();

  // Declarados FORA do try: o `catch` no fim posta uma mensagem de
  // contingência na conversa e precisa dos dois. Enquanto eram `const`
  // dentro do try, o `catch` referenciava nomes fora de escopo — o
  // ReferenceError era engolido pelo `catch (_) {}` interno e a
  // contingência nunca chegava a ser postada.
  let record: any = null;
  let conversationId: string | null = null;

  try {
    // ── Releitura autoritativa da mensagem ───────────────────
    // Nunca confiamos no `record` do payload (forjável): buscamos a
    // versão real por id — daí vêm sender_id, conteúdo e conversa.
    const { data: fetched } = await supabase
      .from(tableName)
      .select(`id, ${idField}, organization_id, sender_id, content, content_type, reply_to, metadata, created_at, deleted_at`)
      .eq('id', clientRecord.id)
      .maybeSingle();
    record = fetched;

    if (!record) return json({ skipped: 'message_not_found' });
    if (record.deleted_at) return json({ skipped: 'deleted' });
    // Defesa: nunca responde às próprias mensagens (evita loop).
    if (record.sender_id === BOT_ID) return json({ skipped: 'self' });

    conversationId = record[idField];
    if (!conversationId) return json({ error: 'missing record' }, 400);
    // ── Confirma que o bot é membro do chat ──────────────────
    const membersTable = isChannel ? 'channel_members' : 'chat_members';
    const { data: membership } = await supabase
      .from(membersTable)
      .select(idField)
      .eq(idField, conversationId)
      .eq('user_id', BOT_ID)
      .maybeSingle();
    if (!membership) return json({ skipped: 'not_member' });

    // ── Nome do Usuário que enviou a mensagem ────────────────
    const { data: sender } = await supabase
      .from('users')
      .select('full_name')
      .eq('id', record.sender_id)
      .maybeSingle();
    const senderName = sender?.full_name ? String(sender.full_name).split(' ')[0] : 'Colaborador';

    // ── Tipo do chat + especialização (persona) ──────────────
    const contextTable = isChannel ? 'channels' : 'chats';
    // channels também tem coluna metadata → persona (ai_specialization)
    // agora funciona em canais, não só em DMs/grupos.
    const selectCols = 'type, metadata';
    const { data: chat } = await supabase
      .from(contextTable)
      .select(selectCols)
      .eq('id', conversationId)
      .single();

    const isDirect = !isChannel && chat?.type === 'direct';

    // ── Gate de grupos/canais: só responde se endereçado ─────
    if (!isDirect) {
      const content = String(record.content ?? '').toLowerCase();
      const mentions = record.metadata?.mentions;
      const mentioned =
        (Array.isArray(mentions) && mentions.includes(BOT_ID)) ||
        content.includes('@assistente ia') ||
        content.includes('@assistente');

      let repliedToBot = false;
      if (record.reply_to) {
        const { data: parent } = await supabase
          .from(tableName)
          .select('sender_id')
          .eq('id', record.reply_to)
          .maybeSingle();
        repliedToBot = parent?.sender_id === BOT_ID;
      }

      if (!mentioned && !repliedToBot) {
        return json({ skipped: 'not_addressed' });
      }
    }

    // ── Comando de Limpeza Manual (/limpar ou /reset) ─────────
    const msgText = String(record.content ?? '').trim().toLowerCase();
    
    // Processamento de comandos apenas em DMs
    if (isDirect) {
      if (msgText === '/limpar' || msgText === '/reset') {
        const { error: delErr } = await supabase
          .from(tableName)
          .delete()
          .eq(idField, conversationId)
          .neq('id', record.id);
          
        if (delErr) throw new Error(`Falha ao limpar histórico: ${delErr.message}`);

        const { error: insErr } = await supabase.from(tableName).insert({
          [idField]: conversationId,
          sender_id: BOT_ID,
          organization_id: record.organization_id,
          content: '🧹 O histórico desta conversa foi apagado da minha memória e do banco de dados.',
          content_type: 'text',
        });
        if (insErr) throw new Error(`Falha ao confirmar limpeza: ${insErr.message}`);

        return json({ success: true, action: 'cleared' });
      } else if (msgText === '/ping') {
        const { error: insErr } = await supabase.from(tableName).insert({
          [idField]: conversationId,
          sender_id: BOT_ID,
          organization_id: record.organization_id,
          content: '🏓 Pong! Estou online e pronto para ajudar.',
          content_type: 'text',
        });
        if (insErr) throw new Error(`Falha no ping: ${insErr.message}`);
        return json({ success: true, action: 'ping' });
      } else if (msgText === '/ajuda' || msgText === '/help') {
        const helpText = `Olá! Sou o **Assistente IA do ${APP_NAME}**. Estou aqui para te apoiar com processos internos, RH, TI e informações da empresa.

**O que eu posso fazer:**
- Responder dúvidas sobre políticas, benefícios e fluxos da empresa.
- Explicar como usar o ${APP_NAME} e orientar na abertura de chamados.
- Nos Canais de Workflow, ler o histórico do chat se você me mencionar (@assistente) para te ajudar com o card atual.

**Restrições:**
- Foco exclusivo: Sou um assistente estritamente corporativo.
- Não respondo sobre programação, conhecimentos gerais não aplicados à empresa ou tarefas fora do escopo de trabalho.

**Comandos disponíveis (apenas no Chat Direto comigo):**
- \`/limpar\` ou \`/reset\`: Apaga todo o nosso histórico de conversa para iniciarmos um novo assunto do zero.
- \`/ping\`: Verifica se eu estou online e respondendo.
- \`/resumo\`: Faz um resumo completo do que conversamos até o momento.
- \`/ajuda\` ou \`/help\`: Exibe esta mensagem de ajuda.

Como posso te ajudar hoje?`;

        const { error: insErr } = await supabase.from(tableName).insert({
          [idField]: conversationId,
          sender_id: BOT_ID,
          organization_id: record.organization_id,
          content: helpText,
          content_type: 'text',
        });
        if (insErr) throw new Error(`Falha ao confirmar ajuda: ${insErr.message}`);

        return json({ success: true, action: 'help' });
      }
    }

    // ── Chave global da Groq (Secret da plataforma) ──────────
    const groqKey = Deno.env.get('GROQ_API_KEY') ?? '';
    if (!groqKey) {
      console.warn('[ai-chatbot] GROQ_API_KEY não configurada — postando mensagem de contingência');
      await supabase.from(tableName).insert({
        [idField]: conversationId,
        sender_id: BOT_ID,
        organization_id: record.organization_id,
        content: '⚠️ O Assistente IA está temporariamente indisponível (chave de API Groq não configurada no servidor). Entre em contato com a equipe de T.I.',
        content_type: 'text',
      });
      return json({ skipped: 'no_api_key' });
    }

    // ── Debounce: se já existe mensagem mais nova do usuário,
    //    deixa o disparo mais recente responder (evita respostas
    //    duplicadas e custo em rajadas de mensagens). ───────────
    const { data: newer } = await supabase
      .from(tableName)
      .select('id')
      .eq(idField, conversationId)
      .neq('sender_id', BOT_ID)
      .is('deleted_at', null)
      .gt('created_at', record.created_at)
      .limit(1);
    if (newer && newer.length > 0) return json({ skipped: 'superseded' });

    // ── Histórico recente do chat (contexto) ─────────────────
    const { data: history } = await supabase
      .from(tableName)
      .select('sender_id, content, content_type, created_at')
      .eq(idField, conversationId)
      .is('deleted_at', null)
      .order('created_at', { ascending: false })
      .limit(HISTORY_LIMIT);

    const ordered = (history ?? []).reverse();
    const llmMessages = ordered
      .map((m: any) => ({
        // Tipo literal: inferido como `string`, o SDK da OpenAI recusa a lista.
        role: (m.sender_id === BOT_ID ? 'assistant' : 'user') as 'assistant' | 'user',
        content: (m.content && String(m.content).trim().length > 0)
          ? redactPii(String(m.content))
          : `[${m.content_type ?? 'mídia'}]`,
      }))
      // Remove entradas sem conteúdo. A última mensagem é sempre a que
      // disparou o trigger (do usuário), então a exigência do protocolo
      // OpenAI/Groq de não terminar em `assistant` é satisfeita naturalmente.
      .filter((m: any) => m.content.length > 0);

    if (llmMessages.length === 0) return json({ skipped: 'empty_history' });

    // ── Empresa da conversa (tenant da mensagem) ─────────────
    const { data: org } = await supabase
      .from('organizations')
      .select('name')
      .eq('id', record.organization_id)
      .maybeSingle();
    const companyName = org?.name ? String(org.name).trim() || null : null;
    const base = basePrompt(companyName);

    // ── Persona: especialização + nome do usuário ────────────
    const specialization =
      SPECIALIZATIONS[chat?.metadata?.ai_specialization as string] ?? SPECIALIZATIONS.geral;
    const persona = base + specialization +
      `\nIMPORTANTE: A pessoa falando com você agora se chama ${senderName}. Dirija-se a ela pelo nome sempre que fizer sentido!`;

    // Comando /resumo (só DM): troca a instrução do sistema por um pedido
    // de resumo do histórico. Antes era anunciado no /ajuda mas não existia.
    const systemContent = (isDirect && msgText === '/resumo')
      ? `${base}\nO usuário pediu um RESUMO da conversa. Sintetize em tópicos os principais assuntos, decisões e pendências do histórico abaixo. Não invente nada que não esteja no histórico; se houver pouco conteúdo, diga isso.`
      : persona;

    // ── Groq (compatível com o protocolo OpenAI) ─────────────
    let completion: any;
    try {
      const groq = new OpenAI({ apiKey: groqKey, baseURL: GROQ_BASE_URL });
      completion = await groq.chat.completions.create({
        model: MODEL,
        max_tokens: MAX_OUTPUT_TOKENS,
        messages: [
          { role: 'system', content: systemContent },
          ...llmMessages,
        ],
      });
    } catch (llmErr: any) {
      console.error('[ai-chatbot] LLM error:', llmErr);
      await logUsage(supabase, {
        organization_id: record.organization_id,
        sucesso: false,
        erro: String(llmErr?.message ?? llmErr).slice(0, 500),
        duracao_ms: Date.now() - started,
      });
      // Não deixa o usuário no vácuo: responde com uma contingência.
      await supabase.from(tableName).insert({
        [idField]: conversationId,
        sender_id: BOT_ID,
        organization_id: record.organization_id,
        content: '⚠️ Tive um problema para gerar a resposta agora. Pode tentar de novo em instantes?',
        content_type: 'text',
      });
      return json({ error: 'llm_failed' });
    }

    const reply = completion.choices[0]?.message?.content?.trim();
    const usageIn = completion.usage?.prompt_tokens ?? 0;
    const usageOut = completion.usage?.completion_tokens ?? 0;

    if (!reply) {
      await logUsage(supabase, {
        organization_id: record.organization_id,
        sucesso: false,
        erro: 'empty_reply',
        tokens_input: usageIn,
        tokens_output: usageOut,
        duracao_ms: Date.now() - started,
      });
      return json({ skipped: 'empty_reply' });
    }

    // ── Insere a resposta como o bot → Realtime + push ───────
    const { error: insErr } = await supabase.from(tableName).insert({
      [idField]: conversationId,
      sender_id: BOT_ID,
      organization_id: record.organization_id,
      content: reply,
      content_type: 'text',
    });
    if (insErr) throw new Error(`falha ao inserir resposta: ${insErr.message}`);

    // ── Log de uso/custo (paridade com rh-extract-cv) ────────
    await logUsage(supabase, {
      organization_id: record.organization_id,
      sucesso: true,
      tokens_input: usageIn,
      tokens_output: usageOut,
      custo_estimado: (usageIn * PRICE_IN + usageOut * PRICE_OUT) / 1e6,
      duracao_ms: Date.now() - started,
    });

    return json({ success: true });
  } catch (error: any) {
    console.error('[ai-chatbot] error:', error);
    try {
      if (record && record.organization_id && conversationId) {
        await supabase.from(tableName).insert({
          [idField]: conversationId,
          sender_id: BOT_ID,
          organization_id: record.organization_id,
          content: '⚠️ Não foi possível processar sua resposta no momento. Por favor, tente novamente em instantes.',
          content_type: 'text',
        });
      }
    } catch (_) {}
    return json({ error: 'chatbot failed', detail: String(error?.message ?? error) }, 500);
  }
});

// Registra uso/custo em ia_usage_log. Com o multi-tenant, o chatbot passa a
// ser por-org: organization_id vem da mensagem que disparou o trigger (base
// do billing por empresa). Falha de log nunca derruba a resposta.
async function logUsage(supabase: any, fields: Record<string, any>) {
  try {
    await supabase.from('ia_usage_log').insert({
      funcao: 'ai-chatbot',
      modelo: MODEL,
      ...fields,
    });
  } catch (e) {
    console.error('[ai-chatbot] falha ao logar uso:', e);
  }
}

function json(data: Record<string, any>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
