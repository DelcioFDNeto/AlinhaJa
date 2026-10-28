import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { GoogleAuth } from "npm:google-auth-library@9.6.3";
import { isStaleTokenError } from "../_shared/fcm.ts";

console.log("Edge Function 'send-workflow-notification' up and running!");

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-webhook-secret',
};

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    if (req.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405, headers: corsHeaders });
    }

    // -- Guard: valida secret compartilhado (fail-closed, anti-spoofing) --
    // Sem WEBHOOK_SECRET a funcao recusa (auditoria 2026-09-16): o modo antigo
    // "aceitando sem validacao" deixava qualquer chamador com a anon key
    // disparar push com titulo e corpo arbitrarios.
    // WEBHOOK_SECRET_PREVIOUS: opcional, so para a janela de rotacao.
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
    const cardNew = payload.record;
    const cardOld = payload.old_record;

    if (!cardNew) {
      return new Response('No record found in payload', { status: 400, headers: corsHeaders });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    let recipientId: string | null = null;
    let notifTitle = '';
    let notifBody = '';
    const isUrgent = cardNew.priority === 'urgent' || cardNew.priority === 'urgente';

    // Regra 1: Card acabou de ser atribuído a alguém (UPDATE)
    if (payload.type === 'UPDATE' && cardNew.assigned_to && cardNew.assigned_to !== cardOld?.assigned_to) {
      recipientId = cardNew.assigned_to;
      notifTitle = 'Card Atribuído a Você';
      notifBody = cardNew.title;
    }
    // Regra 2: Card URGENTE criado (INSERT)
    else if (payload.type === 'INSERT' && isUrgent && cardNew.assigned_to) {
      recipientId = cardNew.assigned_to;
      notifTitle = '⚠️ Atenção: Card Urgente!';
      notifBody = cardNew.title;
    } else {
      console.log('[SKIP] Nenhuma regra aplicável para notificação push.');
      return new Response('No rules matched', { status: 200, headers: corsHeaders });
    }

    if (!recipientId) {
      return new Response('No recipient', { status: 200, headers: corsHeaders });
    }

    // Buscar FCM Tokens
    const { data: tokensMap, error: tokErr } = await supabase
      .from('user_fcm_tokens')
      .select('token')
      .eq('user_id', recipientId);

    if (tokErr || !tokensMap || tokensMap.length === 0) {
      console.log('[SKIP] Sem tokens FCM para o usuário:', recipientId);
      return new Response('No FCM tokens', { status: 200, headers: corsHeaders });
    }

    const targetTokens = tokensMap.map((t: { token: string }) => t.token);

    // Google Auth para FCM
    const projectId = Deno.env.get('FIREBASE_PROJECT_ID');
    const firebaseConfigStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');

    if (!projectId || !firebaseConfigStr) {
      console.error('[ERRO] Firebase Admin configs missing.');
      return new Response('Firebase config missing', { status: 500, headers: corsHeaders });
    }

    const credentials = JSON.parse(firebaseConfigStr);
    const auth = new GoogleAuth({
      credentials,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    });

    const accessToken = await auth.getAccessToken();

    const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
    let succeeded = 0;

    for (const fcmToken of targetTokens) {
      const fcmPayload = {
        message: {
          token: fcmToken,
          notification: {
            title: notifTitle,
            body: notifBody,
          },
          data: {
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
            type: 'workflow_card',
            card_id: String(cardNew.id),
            channel_id: String(cardNew.channel_id),
            chat_type: 'workflow',
            title: notifTitle,
            body: String(notifBody ?? ''),
          },
          android: {
            priority: 'HIGH',
            notification: {
              // Canal com som criado pelo app. Em versão antiga do app, sem
              // esse canal, o Android usa o canal padrão do manifest.
              channel_id: 'alinhaja_workflow_alerts',
              icon: 'ic_notification',
              color: '#D21A18',
              tag: `workflow_${cardNew.id}`,
            },
          },
          webpush: {
            headers: { Urgency: 'high', TTL: '86400' },
            notification: {
              icon: '/icons/Icon-192.png',
              badge: '/icons/Icon-maskable-192.png',
              tag: `workflow_${cardNew.id}`,
            },
          },
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

      if (resp.ok) {
        succeeded++;
      } else {
        const body = await resp.text();
        console.error(`[FCM FAIL] Status=${resp.status} Body=${body}`);
        if (isStaleTokenError(resp.status, body)) {
          await supabase.from('user_fcm_tokens').delete().eq('token', fcmToken);
        }
      }
    }

    return new Response(JSON.stringify({ success: true, sent: succeeded }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('[ERRO] Exceção:', error);
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
