// Testes da resolução do servidor de e-mail. Rodar com:
//   deno test --allow-env supabase/functions/_shared/mailer_test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { orgSmtp, platformSmtp, resolveSmtp } from './mailer.ts';

const VARS = [
  'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM_EMAIL',
  'GMAIL_USER', 'GMAIL_APP_PASSWORD', 'SENDER_NAME',
];

function withEnv(values: Record<string, string>, fn: () => void) {
  const saved = new Map(VARS.map((k) => [k, Deno.env.get(k)]));
  try {
    for (const k of VARS) Deno.env.delete(k);
    for (const [k, v] of Object.entries(values)) Deno.env.set(k, v);
    fn();
  } finally {
    for (const [k, v] of saved) {
      if (v === undefined) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  }
}

Deno.test('sem configuração nenhuma, não há servidor', () => {
  withEnv({}, () => assertEquals(platformSmtp(), null));
});

Deno.test('GMAIL_* continua funcionando como antes', () => {
  withEnv({ GMAIL_USER: 'a@gmail.com', GMAIL_APP_PASSWORD: 'x', SENDER_NAME: 'RH' }, () => {
    assertEquals(platformSmtp(), {
      host: 'smtp.gmail.com', port: 465, username: 'a@gmail.com', password: 'x',
      fromEmail: 'a@gmail.com', fromName: 'RH',
    });
  });
});

Deno.test('SMTP_* tem prioridade sobre GMAIL_*', () => {
  withEnv({
    SMTP_HOST: 'smtp.office365.com', SMTP_PORT: '587', SMTP_USER: 'u@empresa.com',
    SMTP_PASSWORD: 'p', SMTP_FROM_EMAIL: 'nao-responda@empresa.com',
    GMAIL_USER: 'a@gmail.com', GMAIL_APP_PASSWORD: 'x',
  }, () => {
    const cfg = platformSmtp('Empresa');
    assertEquals(cfg?.host, 'smtp.office365.com');
    assertEquals(cfg?.port, 587);
    assertEquals(cfg?.fromEmail, 'nao-responda@empresa.com');
    assertEquals(cfg?.fromName, 'Empresa');
  });
});

Deno.test('SMTP_HOST sem credencial não cai silenciosamente no Gmail', () => {
  withEnv({ SMTP_HOST: 'smtp.empresa.com', GMAIL_USER: 'a@gmail.com', GMAIL_APP_PASSWORD: 'x' },
    () => assertEquals(platformSmtp(), null));
});

Deno.test('SMTP da empresa tem prioridade; incompleto não usa o global', () => {
  withEnv({ GMAIL_USER: 'a@gmail.com', GMAIL_APP_PASSWORD: 'x' }, () => {
    const row = {
      host: 'smtp.empresa.com', port: 587, username: 'rh@empresa.com',
      password_decrypted: 's', from_email: 'rh@empresa.com', from_name: 'RH Empresa',
    };
    assertEquals(resolveSmtp(row)?.host, 'smtp.empresa.com');
    assertEquals(resolveSmtp({ ...row, password_decrypted: null }), null);
    assertEquals(resolveSmtp(null)?.host, 'smtp.gmail.com');
    assertEquals(resolveSmtp({ host: null })?.host, 'smtp.gmail.com');
  });
});

Deno.test('orgSmtp completa remetente com o usuário', () => {
  withEnv({}, () => {
    const cfg = orgSmtp({ host: 'h', port: '465', username: 'u@e.com', password_decrypted: 'p' });
    assertEquals(cfg?.fromEmail, 'u@e.com');
    assertEquals(cfg?.port, 465);
  });
});
