import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { GoogleAuth } from "npm:google-auth-library@9.6.3";

console.log("Edge Function 'send-module-notification' up and running!");

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-webhook-secret',
};

/**
 * Broadcast de notificação por módulo (departamento).
 *
 * Envia para o tópico FCM `mod_<module>`, no qual o app inscreve os usuários
 * que têm acesso ao módulo (ver PushNotificationService.syncModuleTopicSubscriptions).
 *
 * Corpo esperado (POST):
 *   { "module": "rh_alertas", "title": "...", "body": "...", "data": { ... } }
 *
 * A mensagem é enviada como *data-only* (sem bloco `notification`) para que o
 * handler de background do app a renderize no canal do módulo, respeitando o
 * toggle por módulo e o horário silencioso do usuário.
 */
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
    const moduleId: string | undefined = payload.module;
    const title: string = payload.title ?? '';
    const body: string = payload.body ?? '';
    const extraData: Record<string, string> = payload.data ?? {};

    if (!moduleId) {
      return new Response(JSON.stringify({ error: 'module is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Google Auth para FCM v1
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

    const fcmPayload = {
      message: {
        topic: `mod_${moduleId}`,
        data: {
          ...extraData,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
          type: 'module',
          module: moduleId,
          title,
          body,
        },
        android: {
          priority: 'high',
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

    const respText = await resp.text();
    if (!resp.ok) {
      console.error('[ERRO] FCM respondeu:', resp.status, respText);
      return new Response(JSON.stringify({ error: 'FCM send failed', detail: respText }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ success: true, topic: `mod_${moduleId}` }), {
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
