// ============================================================
// mailer.ts — envio de e-mail transacional, independente de provedor
//
// Antes, cada function abria o próprio SMTPClient com `smtp.gmail.com`
// fixo: trocar de provedor (Office 365 do cliente, SES, SMTP interno de
// uma instalação on-premise) exigia editar quatro functions. Agora o
// servidor é configuração.
//
// Servidor global da plataforma (Secrets do projeto):
//
//   SMTP_HOST        ex.: smtp.office365.com
//   SMTP_PORT        465 = TLS direto; qualquer outra = STARTTLS (padrão 465)
//   SMTP_USER        usuário de autenticação
//   SMTP_PASSWORD    senha (ou senha de app)
//   SMTP_FROM_EMAIL  remetente, quando difere do usuário (opcional)
//   SENDER_NAME      nome exibido no remetente (opcional, padrão APP_NAME)
//
// Compatibilidade: sem SMTP_HOST, vale a configuração anterior
// GMAIL_USER + GMAIL_APP_PASSWORD (smtp.gmail.com:465). Deployments
// existentes continuam funcionando sem mudar nenhum Secret.
//
// O SMTP próprio de cada empresa (RH, `rh_get_smtp_server`) continua tendo
// prioridade onde existe — ver `orgSmtp`.
// ============================================================
import { SMTPClient } from 'https://deno.land/x/denomailer@1.6.0/mod.ts';
import { APP_NAME } from './brand.ts';
import { stripHeaderBreaks } from './html.ts';

export interface SmtpConfig {
  host: string;
  port: number;
  username: string;
  password: string;
  fromEmail: string;
  fromName: string;
}

export interface MailMessage {
  to: string;
  subject: string;
  html: string;
  /// Versão texto puro (recomendada: melhora a entrega).
  text?: string;
  replyTo?: string;
  headers?: Record<string, string>;
}

function env(name: string): string {
  return (Deno.env.get(name) ?? '').trim();
}

/// Servidor global da plataforma, ou `null` se nenhum estiver configurado.
/// [fromName] substitui o nome padrão do remetente (SENDER_NAME/APP_NAME).
export function platformSmtp(fromName?: string): SmtpConfig | null {
  const name = fromName || env('SENDER_NAME') || APP_NAME;

  const host = env('SMTP_HOST');
  if (host) {
    const username = env('SMTP_USER');
    const password = env('SMTP_PASSWORD');
    if (!username || !password) return null;
    return {
      host,
      port: Number(env('SMTP_PORT')) || 465,
      username,
      password,
      fromEmail: env('SMTP_FROM_EMAIL') || username,
      fromName: name,
    };
  }

  const gmailUser = env('GMAIL_USER');
  const gmailPassword = env('GMAIL_APP_PASSWORD');
  if (!gmailUser || !gmailPassword) return null;
  return {
    host: 'smtp.gmail.com',
    port: 465,
    username: gmailUser,
    password: gmailPassword,
    fromEmail: gmailUser,
    fromName: name,
  };
}

/// Mensagem de erro padrão quando não há servidor configurado.
export const SMTP_NOT_CONFIGURED =
  'SMTP não configurado: defina SMTP_HOST, SMTP_USER e SMTP_PASSWORD ' +
  '(ou GMAIL_USER e GMAIL_APP_PASSWORD) nos Secrets do projeto.';

/// Converte a linha devolvida por `rh_get_smtp_server` (SMTP próprio da
/// empresa). `null` quando a empresa não configurou servidor.
// deno-lint-ignore no-explicit-any
export function orgSmtp(row: any): SmtpConfig | null {
  if (!row?.host || !row?.username || !row?.password_decrypted) return null;
  return {
    host: String(row.host),
    port: Number(row.port) || 465,
    username: String(row.username),
    password: String(row.password_decrypted),
    fromEmail: String(row.from_email || row.username),
    fromName: String(row.from_name || env('SENDER_NAME') || APP_NAME),
  };
}

/// SMTP da empresa quando ela cadastrou um servidor; senão, o global.
///
/// Empresa com servidor cadastrado mas credencial incompleta recebe `null`
/// em vez do global: o teste de conexão do RH precisa acusar a configuração
/// dela, não mascará-la enviando pelo servidor da plataforma.
// deno-lint-ignore no-explicit-any
export function resolveSmtp(orgRow: any, fallbackFromName?: string): SmtpConfig | null {
  if (orgRow?.host) return orgSmtp(orgRow);
  return platformSmtp(fallbackFromName);
}

/// `true` quando a porta usa TLS direto; as demais negociam STARTTLS.
export function isImplicitTls(cfg: SmtpConfig): boolean {
  return cfg.port === 465;
}

/// Envia uma mensagem e fecha a conexão, mesmo em caso de erro.
export async function sendMail(cfg: SmtpConfig, msg: MailMessage): Promise<void> {
  const client = new SMTPClient({
    connection: {
      hostname: cfg.host,
      port: cfg.port,
      tls: isImplicitTls(cfg),
      auth: { username: cfg.username, password: cfg.password },
    },
  });
  try {
    // Campos opcionais só entram quando têm valor: é o formato que as
    // functions já enviavam antes deste módulo.
    await client.send({
      from: `${stripHeaderBreaks(cfg.fromName)} <${cfg.fromEmail}>`,
      to: msg.to,
      subject: stripHeaderBreaks(msg.subject),
      html: msg.html,
      ...(msg.text ? { content: msg.text } : {}),
      ...(msg.replyTo ? { replyTo: msg.replyTo } : {}),
      ...(msg.headers ? { headers: msg.headers } : {}),
    });
  } finally {
    try { await client.close(); } catch (_) { /* conexão já encerrada */ }
  }
}
