// Textos dos avisos de conta. Separado do handler para ser testável sem rede.
import { escapeHtml } from '../_shared/html.ts';

export type AccountEventKind =
  | 'channel_join_rejected'
  | 'channel_admin_transferred'
  | 'signup_rejected';

export interface AccountEvent {
  kind: AccountEventKind;
  user_id?: string;
  email?: string;
  full_name?: string;
  channel_id?: string;
  channel_name?: string;
  actor_name?: string;
}

export interface PushNotice {
  title: string;
  body: string;
  /// Rota do app aberta ao tocar.
  route: string;
}

const KINDS: AccountEventKind[] = [
  'channel_join_rejected',
  'channel_admin_transferred',
  'signup_rejected',
];

/// Valida o corpo recebido. Evento sem destinatário não tem o que enviar.
export function parseAccountEvent(raw: unknown): AccountEvent | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const e = raw as Record<string, unknown>;
  if (!KINDS.includes(e.kind as AccountEventKind)) return null;
  const str = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim() : undefined);
  const event: AccountEvent = {
    kind: e.kind as AccountEventKind,
    user_id: str(e.user_id),
    email: str(e.email),
    full_name: str(e.full_name),
    channel_id: str(e.channel_id),
    channel_name: str(e.channel_name),
    actor_name: str(e.actor_name),
  };
  if (event.kind === 'signup_rejected') return event.email ? event : null;
  return event.user_id ? event : null;
}

export function pushNotice(event: AccountEvent): PushNotice | null {
  const channel = event.channel_name ?? 'o canal';
  switch (event.kind) {
    case 'channel_join_rejected':
      return {
        title: 'Solicitação não aprovada',
        body: `Seu pedido para entrar em "${channel}" não foi aprovado. Fale com quem administra o canal se precisar de acesso.`,
        route: '/channels/discover',
      };
    case 'channel_admin_transferred':
      return {
        title: `Você agora administra "${channel}"`,
        body: event.actor_name
          ? `${event.actor_name} saiu do canal e passou a administração para você.`
          : 'O administrador anterior saiu do canal e passou a administração para você.',
        route: event.channel_id ? `/channel/${event.channel_id}` : '/chats',
      };
    default:
      return null;
  }
}

export function signupRejectedEmail(
  event: AccountEvent,
  appName: string,
  tagline: string,
): { subject: string; text: string; html: string } {
  const firstName = (event.full_name ?? '').split(/\s+/)[0] || '';
  const greeting = firstName ? `Olá, ${firstName}!` : 'Olá!';
  const text = `${greeting}

Seu cadastro no ${appName} não foi aprovado pela equipe responsável.

Se você acredita que isso foi um engano ou precisa de acesso para trabalhar, procure o TI ou o seu gestor. Um novo cadastro pode ser feito depois do alinhamento.

--
${tagline}`;

  const html = `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
<body style="margin:0;padding:0;background-color:#0a0a0f;font-family:'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0a0a0f;padding:40px 20px;">
    <tr><td align="center">
      <table width="480" cellpadding="0" cellspacing="0" style="background-color:#12121a;border-radius:20px;overflow:hidden;border:1px solid rgba(255,255,255,0.06);">
        <tr><td style="background:linear-gradient(135deg,#D32F2F 0%,#8B0000 100%);padding:32px 40px;text-align:center;">
          <h1 style="margin:0;color:#ffffff;font-size:22px;font-weight:700;">Cadastro não aprovado</h1>
        </td></tr>
        <tr><td style="padding:36px 40px 40px;">
          <p style="margin:0 0 12px;color:#e0e0e0;font-size:16px;line-height:1.6;">${escapeHtml(greeting)}</p>
          <p style="margin:0 0 16px;color:#b8b8c8;font-size:14px;line-height:1.7;">
            Seu cadastro no <strong style="color:#ffffff;">${escapeHtml(appName)}</strong> não foi aprovado pela equipe responsável.
          </p>
          <p style="margin:0;color:#8888a0;font-size:13px;line-height:1.7;">
            Se você acredita que isso foi um engano ou precisa de acesso para trabalhar, procure o TI ou o seu gestor. Um novo cadastro pode ser feito depois do alinhamento.
          </p>
        </td></tr>
        <tr><td style="padding:18px 40px;background:rgba(0,0,0,0.3);text-align:center;border-top:1px solid rgba(255,255,255,0.04);">
          <p style="margin:0;color:#444460;font-size:11px;">© ${new Date().getFullYear()} ${escapeHtml(tagline)}</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;

  return { subject: `Cadastro não aprovado — ${appName}`, text, html };
}
