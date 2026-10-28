import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { GoogleAuth } from "npm:google-auth-library@9.6.3";
import { contentPreview, isStaleTokenError } from "../_shared/fcm.ts";

console.log("Edge Function 'send-chat-notification' v3 — Smart Rules up and running!");

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-webhook-secret',
};

serve(async (req: Request) => {
  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── Guard: apenas POST (Webhook do Supabase) ──
    if (req.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405, headers: corsHeaders });
    }

    // -- Guard: valida secret compartilhado do webhook (fail-closed, anti-spoofing) --
    // Configure com: npx supabase secrets set WEBHOOK_SECRET=<valor forte>
    // e envie o header 'x-webhook-secret' nos triggers do banco (ver migration).
    //
    // Fail-closed: sem WEBHOOK_SECRET a funcao recusa. Aceitar sem validacao
    // permitiria a qualquer um com a anon key disparar push arbitrario em nome
    // da empresa para qualquer usuario.
    //
    // WEBHOOK_SECRET_PREVIOUS e opcional e existe apenas para a janela de
    // rotacao: mantenha nele o valor antigo ate o Vault e as secrets das
    // functions estarem sincronizados, depois remova.
    const webhookSecret = Deno.env.get('WEBHOOK_SECRET') ?? '';
    const previousSecret = Deno.env.get('WEBHOOK_SECRET_PREVIOUS') ?? '';
    if (!webhookSecret) {
      console.error('[AUTH] WEBHOOK_SECRET nao configurado - recusando a chamada.');
      return new Response('Server misconfigured', { status: 503, headers: corsHeaders });
    }
    const receivedSecret = req.headers.get('x-webhook-secret') ?? '';
    if (
      receivedSecret !== webhookSecret &&
      !(previousSecret && receivedSecret === previousSecret)
    ) {
      console.warn('[AUTH] Requisicao rejeitada: x-webhook-secret ausente ou invalido.');
      return new Response('Unauthorized', { status: 401, headers: corsHeaders });
    }

    const payload = await req.json();
    const message = payload.record;

    if (!message) {
      console.warn('[SKIP] Payload sem campo "record".');
      return new Response('No record found in payload', { status: 400, headers: corsHeaders });
    }

    const isChannelMessage = Boolean(message.channel_id) && !message.chat_id;
    const conversationId = isChannelMessage ? message.channel_id : message.chat_id;
    const messageTable = isChannelMessage ? 'channel_messages' : 'messages';
    const membersTable = isChannelMessage ? 'channel_members' : 'chat_members';
    const memberConversationColumn = isChannelMessage ? 'channel_id' : 'chat_id';

    console.log(`[1/6] Mensagem recebida: id=${message.id}, ${isChannelMessage ? 'channel_id' : 'chat_id'}=${conversationId}, sender_id=${message.sender_id}, type=${message.content_type}, thread_id=${message.thread_id ?? 'null'}`);

    // Ignorar mensagens soft-deleted
    if (message.deleted_at != null) {
      console.log('[SKIP] Mensagem deletada, ignorando.');
      return new Response('Ignored deleted message', { status: 200, headers: corsHeaders });
    }

    // ── Inicializar Supabase Admin ──
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // ── 1. Buscar dados do remetente ──
    const { data: sender, error: senderErr } = await supabase
      .from('users')
      .select('full_name, avatar_url')
      .eq('id', message.sender_id)
      .single();

    if (senderErr) {
      console.error('[ERRO] Falha ao buscar sender:', senderErr.message);
    }

    const senderName = sender?.full_name ?? 'Novo usuário';
    console.log(`[2/6] Remetente: "${senderName}"`);

    // ── 2. Buscar dados do chat/canal ──
    let chatTitle = senderName;
    const { data: chat, error: chatErr } = isChannelMessage
      ? await supabase
        .from('channels')
        .select('name, type')
        .eq('id', conversationId)
        .single()
      : await supabase
        .from('chats')
        .select('name, type')
        .eq('id', conversationId)
        .single();

    if (chatErr) {
      console.error('[ERRO] Falha ao buscar chat:', chatErr.message);
    }

    const chatType = isChannelMessage ? 'channel' : (chat?.type ?? 'direct');

    if (chat && (chatType === 'group' || chatType === 'channel')) {
      chatTitle = `${chat.name ?? 'Chat'} • ${senderName}`;
    }

    // ── 3. Resolver preview de conteúdo ──
    const bodyPreview = contentPreview(message.content_type, message.content);
    const senderAvatar = typeof sender?.avatar_url === 'string' ? sender.avatar_url : '';

    // ── Formatar notificação estilo WhatsApp ──
    // DM: título = nome do remetente, body = conteúdo
    // Grupo/Canal: título = nome do grupo, body = "NomeRemetente: conteúdo"
    let notifTitle: string;
    let notifBody: string;

    if (chat && (chatType === 'group' || chatType === 'channel')) {
      notifTitle = chat.name ?? 'Chat';
      notifBody = `${senderName}: ${bodyPreview}`;
    } else {
      notifTitle = senderName;
      notifBody = bodyPreview;
    }

    console.log(`[3/6] Tipo="${chatType}", Título="${notifTitle}", Body="${notifBody}"`);

    // ── 4. SMART RULES: Determinar destinatários ──
    let recipientIds: string[] = [];

    // ─── REGRA A: Thread → notificar apenas participantes da Thread ──
    if (message.thread_id) {
      console.log(`[SMART] Mensagem em Thread (thread_id=${message.thread_id}). Buscando participantes da thread...`);

      const { data: threadParticipants, error: tpErr } = await supabase
        .from(messageTable)
        .select('sender_id')
        .eq('thread_id', message.thread_id)
        .neq('sender_id', message.sender_id);

      if (tpErr) {
        console.error('[ERRO] Falha ao buscar participantes da thread:', tpErr.message);
      }

      // Também incluir o autor da mensagem pai (thread original)
      const { data: parentMsg } = await supabase
        .from(messageTable)
        .select('sender_id')
        .eq('id', message.thread_id)
        .single();

      const participantSet = new Set<string>();
      if (threadParticipants) {
        threadParticipants.forEach((p: { sender_id: string }) => participantSet.add(p.sender_id));
      }
      if (parentMsg && parentMsg.sender_id !== message.sender_id) {
        participantSet.add(parentMsg.sender_id);
      }

      recipientIds = Array.from(participantSet);
      console.log(`[SMART] Thread: ${recipientIds.length} participantes encontrados.`);

    // ─── REGRA B: Canal / DM / Grupo → push normal para todos os membros ──
    } else {
      console.log(`[SMART] ${chatType === 'direct' ? 'DM' : chatType === 'channel' ? 'Canal' : 'Grupo'} → notificação normal.`);

      const { data: members, error: memErr } = await supabase
        .from(membersTable)
        .select('user_id')
        .eq(memberConversationColumn, conversationId)
        .neq('user_id', message.sender_id);

      if (memErr) {
        console.error('[ERRO] Falha ao buscar membros:', memErr.message);
        return new Response('Error fetching members', { status: 500, headers: corsHeaders });
      }

      recipientIds = members?.map((m: { user_id: string }) => m.user_id) ?? [];
    }

    // ── 4.1 Quem foi mencionado nesta mensagem ──
    // Usado tanto para o nível `mentions` quanto para prefixar a notificação.
    const rawMentions = message.metadata?.mentions;
    const mentionedIds = new Set<string>(
      Array.isArray(rawMentions) ? rawMentions.filter((v: unknown) => typeof v === 'string') : [],
    );
    const mentionsEveryone = message.metadata?.mentions_everyone === true;

    if (mentionsEveryone) {
      console.log('[MENTION] Mensagem marca @canal/@aqui — alcança quem está em "somente menções".');
    } else if (mentionedIds.size > 0) {
      console.log(`[MENTION] ${mentionedIds.size} usuário(s) mencionado(s) diretamente.`);
    }

    // ── 4.2 SILENCIAR / NÍVEL DE NOTIFICAÇÃO ──
    if (recipientIds.length > 0) {
      if (isChannelMessage) {
        // Canal: `all` recebe tudo, `mentions` só quando citado (direto ou por
        // @canal/@aqui), `none` nunca. Coluna nova em 20260813110000 — se ela
        // ainda não existe no banco, o catch mantém todo mundo (fail-open é o
        // comportamento anterior e não perde mensagem).
        const { data: levelRows, error: levelErr } = await supabase
          .from('channel_members')
          .select('user_id, notification_level')
          .eq('channel_id', conversationId)
          .in('user_id', recipientIds);

        if (levelErr) {
          console.error('[WARN] Falha ao consultar nível de notificação (mantendo destinatários):', levelErr.message);
        } else if (levelRows) {
          // Montado em laço, e não via `new Map(rows.map(...))`: o `.map`
          // infere `string[][]` e não a tupla que o construtor exige.
          const levelByUser = new Map<string, string>();
          for (const row of levelRows as Array<{ user_id: string; notification_level?: string }>) {
            levelByUser.set(row.user_id, row.notification_level ?? 'all');
          }

          const before = recipientIds.length;
          recipientIds = recipientIds.filter((id) => {
            const level = levelByUser.get(id) ?? 'all';
            if (level === 'none') return false;
            if (level === 'mentions') return mentionsEveryone || mentionedIds.has(id);
            return true;
          });
          console.log(`[LEVEL] ${before - recipientIds.length} destinatário(s) filtrados por preferência do canal.`);
        }
      } else {
        // DM/grupo seguem no booleano `muted` de chat_members.
        const { data: mutedRows, error: mutedErr } = await supabase
          .from('chat_members')
          .select('user_id')
          .eq('chat_id', conversationId)
          .eq('muted', true)
          .in('user_id', recipientIds);

        if (mutedErr) {
          console.error('[WARN] Falha ao consultar chats silenciados (mantendo destinatários):', mutedErr.message);
        } else if (mutedRows && mutedRows.length > 0) {
          const mutedSet = new Set(mutedRows.map((r: { user_id: string }) => r.user_id));
          recipientIds = recipientIds.filter((id) => !mutedSet.has(id));
          console.log(`[MUTE] ${mutedSet.size} destinatário(s) com a conversa silenciada foram removidos.`);
        }
      }
    }

    if (recipientIds.length === 0) {
      console.log('[SKIP] Nenhum destinatário após aplicar regras smart.');
      return new Response('No recipients after smart rules', { status: 200, headers: corsHeaders });
    }

    console.log(`[4/6] ${recipientIds.length} destinatário(s) após regras smart.`);

    // ── 5. Buscar tokens FCM ativos dos destinatários ──
    // `user_id` vem junto para personalizar a notificação de quem foi citado.
    const { data: tokensMap, error: tokErr } = await supabase
      .from('user_fcm_tokens')
      .select('token, platform, user_id')
      .in('user_id', recipientIds);

    if (tokErr) {
      console.error('[ERRO] Falha ao buscar tokens FCM:', tokErr.message);
      return new Response('Error fetching tokens', { status: 500, headers: corsHeaders });
    }

    if (!tokensMap || tokensMap.length === 0) {
      console.log('[SKIP] Nenhum token FCM ativo para os destinatários.');
      return new Response('No active tokens for recipients', { status: 200, headers: corsHeaders });
    }

    console.log(`[5/6] Tokens FCM encontrados: ${tokensMap.length}`);

    // ── 6. Autenticação Firebase (OAuth2 via Service Account) ──
    const projectId = Deno.env.get('FIREBASE_PROJECT_ID');
    const firebaseConfigStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');

    if (!projectId || !firebaseConfigStr) {
      console.error('[ERRO FATAL] Variáveis de ambiente FIREBASE_PROJECT_ID e/ou FIREBASE_SERVICE_ACCOUNT não definidas.');
      return new Response('Firebase admin configs missing from env variables', { status: 500, headers: corsHeaders });
    }

    let credentials;
    try {
      credentials = JSON.parse(firebaseConfigStr);
    } catch (parseErr) {
      console.error('[ERRO FATAL] FIREBASE_SERVICE_ACCOUNT não é um JSON válido:', parseErr);
      return new Response('Invalid FIREBASE_SERVICE_ACCOUNT JSON', { status: 500, headers: corsHeaders });
    }

    const auth = new GoogleAuth({
      credentials,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    });

    const accessToken = await auth.getAccessToken();

    if (!accessToken) {
      console.error('[ERRO FATAL] GoogleAuth retornou accessToken nulo/vazio.');
      return new Response('Failed to get Firebase access token', { status: 500, headers: corsHeaders });
    }

    console.log('[6/6] AccessToken Firebase obtido com sucesso. Disparando pushes...');

    // ── 7. Disparar FCM v1 para cada token ──
    const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const results = await Promise.allSettled(
      tokensMap.map(async (tokenData: { token: string, platform?: string, user_id?: string }) => {
        const fcmToken = tokenData.token;
        const platform = tokenData.platform || 'android';
        const isAndroid = platform === 'android';

        // Menção se destaca na bandeja: é o sinal que faz o nível "somente
        // menções" valer a pena para quem silenciou o canal.
        const wasMentioned = tokenData.user_id
          ? mentionedIds.has(tokenData.user_id)
          : false;
        const personalBody = wasMentioned
          ? `@ ${notifBody}`
          : (mentionsEveryone ? `📣 ${notifBody}` : notifBody);

        const messageData = {
          title: String(notifTitle || 'Nova mensagem'),
          body: String(personalBody || ''),
          chat_id: String(conversationId || ''),
          message_id: String(message.id || ''),
          sender_id: String(message.sender_id || ''),
          sender_name: String(senderName || ''),
          chat_type: String(chatType || 'direct'),
          chat_name: String(chat?.name ?? senderName ?? ''),
          // Campos do layout estilo WhatsApp: o app monta a conversa com a
          // foto e o nome de quem enviou, e responde na tabela certa.
          preview: String(bodyPreview),
          sender_avatar: senderAvatar,
          conversation_table: messageTable,
          is_mention: wasMentioned ? 'true' : 'false',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        };

        const messagePayload: any = {
          token: fcmToken,
          data: messageData,
        };

        if (isAndroid) {
          // Data-only: o app desenha a conversa (MessagingStyle) e aplica as
          // preferências do usuário antes de exibir.
          messagePayload.android = {
            priority: 'HIGH',
          };
        } else if (platform === 'web') {
          // Data-only também na web: o service worker exibe com agrupamento
          // por conversa e foto do remetente. Com bloco `notification`, o SDK
          // do Firebase exibia uma notificação e o SW outra (duplicada).
          messagePayload.webpush = {
            headers: { Urgency: 'high', TTL: '86400' },
          };
        } else {
          messagePayload.notification = {
            title: String(notifTitle || 'Nova mensagem'),
            body: String(personalBody || ''),
          };
          messagePayload.apns = {
            headers: {
              "apns-priority": "10"
            },
            payload: {
              aps: {
                "content-available": 1
              }
            }
          };
        }

        const fcmPayload = {
          message: messagePayload,
        };

        const resp = await fetch(fcmEndpoint, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(fcmPayload),
        });

        const respBody = await resp.text();

        if (!resp.ok) {
          console.error(`[FCM FAIL] Token=${fcmToken.substring(0, 20)}... Status=${resp.status} Body=${respBody}`);

          // Só remove token que o FCM declarou inexistente. INVALID_ARGUMENT
          // também é devolvido para erro de PAYLOAD — tratá-lo como token
          // inválido apagava tokens bons a cada envio malformado.
          if (isStaleTokenError(resp.status, respBody)) {
            console.log(`[CLEANUP] Removendo token inválido: ${fcmToken.substring(0, 20)}...`);
            await supabase
              .from('user_fcm_tokens')
              .delete()
              .eq('token', fcmToken);
          }
          throw new Error(`FCM ${resp.status}: ${respBody}`);
        }

        return { token: fcmToken.substring(0, 20), status: 'ok' };
      })
    );

    const succeeded = results.filter((r: PromiseSettledResult<unknown>) => r.status === 'fulfilled').length;
    const failed = results.filter((r: PromiseSettledResult<unknown>) => r.status === 'rejected').length;
    console.log(`[DONE] Push notifications: ${succeeded} OK, ${failed} falhas de ${tokensMap.length} total.`);

    return new Response(JSON.stringify({
      success: true,
      sent: succeeded,
      failed: failed,
      total: tokensMap.length,
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('[ERRO FATAL] Exceção não tratada:', error);
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
