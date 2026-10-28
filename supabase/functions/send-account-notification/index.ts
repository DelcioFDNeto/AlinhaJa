// ============================================================
// send-account-notification — avisos sobre a conta do usuário
//
// Chamada só pelo banco (`fn_notify_account_event`, via net.http_post com
// x-webhook-secret):
//   * channel_join_rejected     → push para quem teve o pedido recusado
//   * channel_admin_transferred → push para quem herdou a administração
//   * signup_rejected           → e-mail para o cadastro recusado (a conta
//                                 pendente nunca teve login nem token de push)
// ============================================================
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { GoogleAuth } from 'npm:google-auth-library@9.6.3';
import { APP_NAME, APP_TAGLINE } from '../_shared/brand.ts';
import { isStaleTokenError } from '../_shared/fcm.ts';
import { platformSmtp, sendMail, SMTP_NOT_CONFIGURED } from '../_shared/mailer.ts';
import { parseAccountEvent, pushNotice, signupRejectedEmail } from './messages.ts';

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'Method Not Allowed' }, 405);

  // Fail-closed, como as demais functions chamadas por trigger.
  const webhookSecret = Deno.env.get('WEBHOOK_SECRET') ?? '';
  const previousSecret = Deno.env.get('WEBHOOK_SECRET_PREVIOUS') ?? '';
  if (!webhookSecret) {
    console.error('[AUTH] WEBHOOK_SECRET nao configurado - recusando a chamada.');
    return json({ error: 'Server misconfigured' }, 503);
  }
  const received = req.headers.get('x-webhook-secret') ?? '';
  if (received !== webhookSecret && !(previousSecret && received === previousSecret)) {
    return json({ error: 'Unauthorized' }, 401);
  }

  try {
    const event = parseAccountEvent(await req.json());
    if (!event) return json({ error: 'Invalid event' }, 400);

    if (event.kind === 'signup_rejected') {
      await sendSignupRejectedEmail(event.email!, event);
      console.log(`[account] signup_rejected enviado para ${event.email!.substring(0, 3)}***`);
      return json({ success: true, channel: 'email' });
    }

    const notice = pushNotice(event)!;
    const sent = await sendPush(event.user_id!, notice, event.channel_id);
    console.log(`[account] ${event.kind}: ${sent} push(es) enviados.`);
    return json({ success: true, channel: 'push', sent });
  } catch (error) {
    console.error('[account] Erro:', error);
    return json({ error: (error as Error).message }, 500);
  }
});

async function sendPush(
  userId: string,
  notice: { title: string; body: string; route: string },
  channelId?: string,
): Promise<number> {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: tokens, error } = await supabase
    .from('user_fcm_tokens')
    .select('token, platform')
    .eq('user_id', userId);
  if (error) throw error;
  if (!tokens || tokens.length === 0) return 0;

  const projectId = Deno.env.get('FIREBASE_PROJECT_ID');
  const serviceAccount = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
  if (!projectId || !serviceAccount) throw new Error('Firebase configs missing');

  const auth = new GoogleAuth({
    credentials: JSON.parse(serviceAccount),
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const accessToken = await auth.getAccessToken();
  const endpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  // Mesmo contrato dos pushes de chat: Android e web recebem data-only e o
  // app/service worker desenha; `type: account` identifica o aviso.
  const data = {
    type: 'account',
    title: notice.title,
    body: notice.body,
    route: notice.route,
    channel_id: channelId ?? '',
    click_action: 'FLUTTER_NOTIFICATION_CLICK',
  };

  let sent = 0;
  for (const { token, platform } of tokens as { token: string; platform?: string }[]) {
    const message: Record<string, unknown> = { token, data };
    if (platform === 'android' || !platform) {
      message.android = { priority: 'HIGH' };
    } else if (platform === 'web') {
      message.webpush = { headers: { Urgency: 'normal', TTL: '604800' } };
    } else {
      message.notification = { title: notice.title, body: notice.body };
    }

    const resp = await fetch(endpoint, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ message }),
    });
    if (resp.ok) {
      sent++;
      continue;
    }
    const body = await resp.text();
    console.error(`[account] FCM ${resp.status}: ${body}`);
    if (isStaleTokenError(resp.status, body)) {
      await supabase.from('user_fcm_tokens').delete().eq('token', token);
    }
  }
  return sent;
}

async function sendSignupRejectedEmail(
  to: string,
  event: Parameters<typeof signupRejectedEmail>[0],
) {
  const smtp = platformSmtp();
  if (!smtp) throw new Error(SMTP_NOT_CONFIGURED);
  // S021 — em DEV nenhum destinatário real recebe e-mail.
  const recipient = Deno.env.get('DEV_EMAIL_OVERRIDE') || to;
  const mail = signupRejectedEmail(event, APP_NAME, APP_TAGLINE);

  await sendMail(smtp, {
    to: recipient,
    subject: mail.subject,
    text: mail.text,
    html: mail.html,
    headers: { 'Auto-Submitted': 'auto-generated' },
  });
}
