import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { GoogleAuth } from "npm:google-auth-library@9.6.3";
import { isStaleTokenError } from "../_shared/fcm.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-webhook-secret',
};

console.log("Edge Function 'send-call-notification' — CallKit Push system booting...");

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    if (req.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405, headers: corsHeaders });
    }

    // -- Guard: valida secret compartilhado do webhook (fail-closed, anti-spoofing) --
    // Configure com: npx supabase secrets set WEBHOOK_SECRET=<valor forte>
    // e envie o header 'x-webhook-secret' nos triggers do banco (ver migration).
    //
    // Fail-closed: sem WEBHOOK_SECRET a funcao recusa. Aceitar sem validacao
    // permitiria forjar notificacoes de chamada (CallKit) para qualquer usuario.
    //
    // WEBHOOK_SECRET_PREVIOUS e opcional e existe apenas para a janela de
    // rotacao: mantenha nele o valor antigo ate o Vault e as secrets das
    // functions estarem sincronizados, depois remova.
    const webhookSecret = Deno.env.get('WEBHOOK_SECRET') ?? '';
    const previousSecret = Deno.env.get('WEBHOOK_SECRET_PREVIOUS') ?? '';
    let isAuthorized = false;
    // Preenchido só no caminho por JWT (o app dispara o toque direto). O
    // trigger do banco usa o secret e não passa por aqui.
    let jwtUserId: string | null = null;

    const receivedSecret = req.headers.get('x-webhook-secret') ?? '';
    if (
      (webhookSecret && receivedSecret === webhookSecret) ||
      (previousSecret && receivedSecret === previousSecret)
    ) {
      isAuthorized = true;
    } else {
      const authHeader = req.headers.get('Authorization');
      if (authHeader) {
        const token = authHeader.replace(/^Bearer\s+/i, '');
        const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
        const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
        const userClient = createClient(supabaseUrl, supabaseAnonKey, {
          global: { headers: { Authorization: `Bearer ${token}` } },
        });
        const { data: { user }, error: userErr } = await userClient.auth.getUser();
        if (user && !userErr) {
          isAuthorized = true;
          jwtUserId = user.id;
        }
      }
    }

    if (!isAuthorized) {
      console.warn('[AUTH] Requisicao rejeitada: nem x-webhook-secret nem JWT de usuario valido.');
      return new Response('Unauthorized', { status: 401, headers: corsHeaders });
    }

    const payload = await req.json();
    const callRecord = payload.record;

    if (!callRecord) {
      console.warn('[SKIP] Payload sem campo "record".');
      return new Response('No record found in payload', { status: 400, headers: corsHeaders });
    }

    // A tabela "calls" envia type='audio'. A tabela "meetings" não tem type.
    // Prioriza o campo is_video explícito enviado pelo client, fallback para heurística.
    const isVideo = callRecord.is_video === true || callRecord.is_video === 'true'
      || callRecord.room_id !== undefined || payload.table === 'meetings';
    const callerId = callRecord.caller_id || callRecord.host_id;
    const chatId = callRecord.chat_id;
    const channelId = callRecord.channel_id;
    const callId = callRecord.id;
    const isChannel = !!channelId;

    console.log(`📞 [1/5] Recebendo chamada: ID=${callId}, type=${isVideo ? 'video' : 'audio'}, caller=${callerId}, ${isChannel ? `channel=${channelId}` : `chat=${chatId}`}`);

    // Ignorar updates que não sejam de status='ringing' ou 'in_progress' inicial
    // Na verdade, só nos importamos com o INSERT, então o Payload terá type="INSERT"
    if (payload.type !== 'INSERT') {
      return new Response('Only INSERT events are handled for ringing', { status: 200, headers: corsHeaders });
    }

    // ── Inicializar Supabase Admin ──
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // ── Guard do caminho por JWT (auditoria 2026-09-16) ──
    // O `record` vem do cliente. Sem esta checagem, qualquer usuário logado
    // faria tocar a tela de chamada de todos os membros de qualquer conversa,
    // com o nome de outra pessoa como quem liga.
    if (jwtUserId) {
      if (!callerId || callerId !== jwtUserId) {
        console.warn(`[AUTH] caller_id=${callerId} diverge do usuario autenticado ${jwtUserId}.`);
        return new Response('Forbidden', { status: 403, headers: corsHeaders });
      }
      const guardTable = isChannel ? 'channel_members' : 'chat_members';
      const guardColumn = isChannel ? 'channel_id' : 'chat_id';
      const guardContext = isChannel ? channelId : chatId;
      const { data: selfMember } = guardContext
        ? await supabase
          .from(guardTable)
          .select('user_id')
          .eq(guardColumn, guardContext)
          .eq('user_id', jwtUserId)
          .maybeSingle()
        : { data: null };
      if (!selfMember) {
        console.warn(`[AUTH] ${jwtUserId} nao e membro de ${guardTable}=${guardContext}.`);
        return new Response('Forbidden', { status: 403, headers: corsHeaders });
      }
    }

    // ── 1. Buscar dados do Remetente (Quem LIGOU) ──
    const { data: sender } = await supabase
      .from('users')
      .select('full_name, avatar_url')
      .eq('id', callerId)
      .single();

    const callerName = sender?.full_name ?? 'Alguém';
    const callerAvatar = sender?.avatar_url ?? '';

    console.log(`👤 [2/5] Remetente: "${callerName}"`);

    // ── 2. Buscar Destinatários (Membros da conversa MENOS o autor) ──
    // Suporta tanto chats (chat_members) quanto canais (channel_members)
    const memberTable = isChannel ? 'channel_members' : 'chat_members';
    const memberColumn = isChannel ? 'channel_id' : 'chat_id';
    const contextId = isChannel ? channelId : chatId;

    const { data: members, error: memErr } = await supabase
      .from(memberTable)
      .select('user_id')
      .eq(memberColumn, contextId)
      .neq('user_id', callerId);

    if (memErr || !members || members.length === 0) {
      console.error(`[ERRO] Falha ao buscar membros em ${memberTable}: ${memErr?.message}`);
      return new Response('Error fetching members', { status: 500, headers: corsHeaders });
    }

    const recipientIds = members.map((m: { user_id: string }) => m.user_id);
    console.log(`👨‍👩‍👧‍👦 [3/5] Disparando para ${recipientIds.length} membros.`);

    // ── 3. Buscar tokens FCM APENAS E EXCLUSIVAMENTE DOS DESTINATÁRIOS ──
    const { data: tokensMap, error: tokErr } = await supabase
      .from('user_fcm_tokens')
      .select('token')
      .in('user_id', recipientIds);

    if (tokErr || !tokensMap || tokensMap.length === 0) {
      console.log('🔇 [SKIP] Nenhum token FCM de destinatário online encontrado.');
      return new Response('No tokens to ping', { status: 200, headers: corsHeaders });
    }

    const targetTokens: string[] = tokensMap.map((t: { token: string }) => t.token);

    // ── 4. Autenticação Google Firebase OAUTH ──
    const projectId = Deno.env.get('FIREBASE_PROJECT_ID');
    const firebaseConfigStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');

    if (!projectId || !firebaseConfigStr) {
      console.error('[ERRO FATAL] Credenciais Firebase não definidas no Secrets');
      return new Response('Firebase configs missing', { status: 500, headers: corsHeaders });
    }

    const auth = new GoogleAuth({
      credentials: JSON.parse(firebaseConfigStr),
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    });

    const accessToken = await auth.getAccessToken();
    const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    console.log('🔗 [4/5] Conectado ao FCM! Disparando CALL PUSH...');

    // ── 5. Disparar FCM Data-Only Push para o CallKit! ──
    // IMPORTANTE: NÃO INCLUIR BLOCO "notification"!! O Flutter deve ler em background e acionar API Nativa
    const results = await Promise.allSettled(
      targetTokens.map(async (fcmToken) => {
        // Chamada em canal não tem chat_id: o app entra em `call_<id>` com o
        // id do canal. Mandar String(chatId) virava "null" e o atendimento
        // falhava.
        const contextId = String((isChannel ? channelId : chatId) ?? '');
        const fcmPayload = {
          message: {
            token: fcmToken,
            data: {
              // Keywords essenciais que o Flutter (push_notification_service.dart) procura
              type: 'call',
              call_id: String(callId),
              chat_id: contextId,
              channel_id: isChannel ? contextId : '',
              chat_type: isChannel ? 'channel' : 'direct',
              caller_id: String(callerId),
              caller_name: String(callerName),
              caller_avatar: String(callerAvatar),
              is_video: isVideo ? 'true' : 'false',
              // Usados pelo service worker da web para exibir a chamada.
              title: isVideo ? '📹 Chamada de vídeo' : '📞 Chamada de voz',
              body: `${callerName} está ligando…`,
              click_action: 'FLUTTER_NOTIFICATION_CLICK' // Mantém o app engine vivo no Android
            },
            android: {
              priority: 'HIGH', // Acorda o device force (HIGH em maiúsculo na API FCM v1)
              // Chamada entregue depois de 1 min já foi perdida: não toca.
              ttl: '60s',
              direct_boot_ok: true
            },
            webpush: {
              headers: { Urgency: 'high', TTL: '60' },
            },
            apns: {
              headers: {
                "apns-priority": "10",
                "apns-push-type": "voip" // Fundamental pro iOS 
              }
            }
          },
        };

        const resp = await fetch(fcmEndpoint, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(fcmPayload),
        });

        if (!resp.ok) {
          const body = await resp.text();
          if (isStaleTokenError(resp.status, body)) {
            await supabase.from('user_fcm_tokens').delete().eq('token', fcmToken);
          }
          throw new Error(body);
        }
        return fcmToken;
      })
    );

    const succeeded = results.filter(r => r.status === 'fulfilled').length;
    console.log(`✅ [5/5] Chamada Despachada com sucesso: ${succeeded}/${targetTokens.length}`);

    return new Response(JSON.stringify({ success: true, sent: succeeded }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('[ERRO CRÍTICO]', error);
    const err = error as Error;
    return new Response(JSON.stringify({ error: err.message || 'Unknown error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
