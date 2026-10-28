// deno-lint-ignore-file no-explicit-any
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ─── 1. Inicializar Supabase com service_role (acesso total) ───
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // ─── 2. Validar JWT do usuário ───
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return jsonResponse({ error: 'Missing authorization header' }, 401);
    }

    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return jsonResponse({ error: 'Invalid or expired token' }, 401);
    }

    console.log(`[2FA] Generating code for user ${user.id}`);

    // ─── 3. Rate-limit: não permitir reenvio em menos de 60s ───
    const { data: recentOtp } = await supabase
      .from('user_email_otp')
      .select('created_at')
      .eq('user_id', user.id)
      .eq('used', false)
      .gte('created_at', new Date(Date.now() - 60 * 1000).toISOString())
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (recentOtp) {
      return jsonResponse({ error: 'Aguarde 60 segundos antes de solicitar um novo código.' }, 429);
    }

    // ─── 4. Buscar informações do usuário ───
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('full_name, email')
      .eq('id', user.id)
      .single();

    if (userError || !userData) {
      console.error('[2FA] User not found:', userError);
      return jsonResponse({ error: 'User not found' }, 404);
    }

    const userEmail = userData.email || user.email;
    const userName = userData.full_name || 'Usuário';

    if (!userEmail) {
      return jsonResponse({ error: 'User has no email configured' }, 400);
    }

    // ─── 5. Gerar código de 6 dígitos ───
    // CSPRNG: Math.random() não é imprevisível o bastante para um segundo fator.
    const code = generateOtp();

    // ─── 6. Hash SHA-256 do código ───
    const encoder = new TextEncoder();
    const hashBuffer = await crypto.subtle.digest('SHA-256', encoder.encode(code));
    const codeHash = Array.from(new Uint8Array(hashBuffer))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');

    // ─── 7. Invalidar OTPs anteriores ───
    await supabase
      .from('user_email_otp')
      .update({ used: true })
      .eq('user_id', user.id)
      .eq('used', false);

    // ─── 8. Inserir novo OTP ───
    const { error: insertError } = await supabase.from('user_email_otp').insert({
      user_id: user.id,
      code_hash: codeHash,
      expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    });

    if (insertError) {
      console.error('[2FA] Error inserting OTP:', insertError);
      return jsonResponse({ error: 'Failed to generate verification code' }, 500);
    }

    // ─── 9. Enviar e-mail com o código ───
    await sendEmail(userEmail, userName, code);

    console.log(`[2FA] Code sent to ${userEmail.substring(0, 3)}***`);

    // Mascarar e-mail para exibição no app
    const maskedEmail = maskEmail(userEmail);

    return jsonResponse({
      success: true,
      message: 'Verification code sent',
      masked_email: maskedEmail,
    });
  } catch (error: any) {
    console.error('[2FA] Unexpected error:', error);
    return jsonResponse({ error: error.message || 'Internal server error' }, 500);
  }
});

// ─────────────────────────────────────────────────────────────
// Envio de E-mail — servidor configurado nos Secrets (SMTP_* ou, por
// compatibilidade, GMAIL_USER/GMAIL_APP_PASSWORD). Ver `_shared/mailer.ts`.
// Opcional: SENDER_NAME (default = APP_NAME de _shared/brand.ts).
// ─────────────────────────────────────────────────────────────
import { APP_NAME, APP_TAGLINE, EMAIL_LOGO_URL } from '../_shared/brand.ts';
import { escapeHtml } from '../_shared/html.ts';
import { platformSmtp, sendMail, SMTP_NOT_CONFIGURED } from '../_shared/mailer.ts';

async function sendEmail(to: string, userName: string, code: string) {
  const smtp = platformSmtp();
  if (!smtp) throw new Error(SMTP_NOT_CONFIGURED);

  try {
    await sendMail(smtp, {
      to,
      subject: `${code} — Código de Verificação ${APP_NAME}`,
      html: generateEmailHtml(userName, code),
    });
  } catch (err) {
    console.error('[2FA] Email send error:', err);
    throw new Error(`Failed to send email: ${err instanceof Error ? err.message : String(err)}`);
  }
}

// ─────────────────────────────────────────────────────────────
// Template HTML do e-mail
// ─────────────────────────────────────────────────────────────
function generateEmailHtml(userName: string, code: string): string {
  const digits = code.split('');
  const digitBoxes = digits
    .map(
      (d) =>
        `<td style="width:48px;height:56px;background:#1a1a24;border:2px solid rgba(211,47,47,0.4);border-radius:10px;text-align:center;vertical-align:middle;font-size:28px;font-weight:800;color:#ffffff;font-family:'Courier New',monospace;letter-spacing:0;">${d}</td>`
    )
    .join('<td style="width:8px;"></td>');

  return `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
<body style="margin:0;padding:0;background-color:#0a0a0f;font-family:'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0a0a0f;padding:40px 20px;">
    <tr><td align="center">
      <table width="480" cellpadding="0" cellspacing="0" style="background-color:#12121a;border-radius:20px;overflow:hidden;border:1px solid rgba(255,255,255,0.06);box-shadow:0 20px 60px rgba(0,0,0,0.5);">
        <!-- Header com gradiente -->
        <tr><td style="background:linear-gradient(135deg,#D32F2F 0%,#8B0000 100%);padding:36px 40px;text-align:center;">
          <table width="100%" cellpadding="0" cellspacing="0"><tr>
            <td style="text-align:center;">
              <img src="${EMAIL_LOGO_URL}" alt="${APP_NAME} Logo" width="160" style="display:block;margin:0 auto 16px;object-fit:contain;background:rgba(255,255,255,0.1);padding:10px;border-radius:12px;">
              <h1 style="margin:8px 0 0;color:#ffffff;font-size:22px;font-weight:700;letter-spacing:-0.3px;">Verificação de Segurança</h1>
              <p style="margin:6px 0 0;color:rgba(255,255,255,0.75);font-size:13px;">Autenticação em dois fatores</p>
            </td>
          </tr></table>
        </td></tr>
        <!-- Corpo -->
        <tr><td style="padding:36px 40px 40px;">
          <p style="margin:0 0 8px;color:#e0e0e0;font-size:16px;line-height:1.6;">Olá, <strong style="color:#ffffff;">${escapeHtml(userName)}</strong>!</p>
          <p style="margin:0 0 28px;color:#8888a0;font-size:14px;line-height:1.7;">Detectamos um acesso de um dispositivo que ainda não foi verificado. Use o código abaixo para confirmar sua identidade:</p>
          <!-- Código em caixas separadas -->
          <table cellpadding="0" cellspacing="0" style="margin:0 auto;">
            <tr>${digitBoxes}</tr>
          </table>
          <p style="margin:20px 0 0;color:#8888a0;font-size:13px;text-align:center;">⏱ Este código expira em <strong style="color:#D32F2F;">10 minutos</strong></p>
          <hr style="border:none;border-top:1px solid rgba(255,255,255,0.06);margin:28px 0;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:rgba(211,47,47,0.06);border-radius:12px;border:1px solid rgba(211,47,47,0.12);padding:16px;">
            <tr><td style="padding:14px 16px;">
              <p style="margin:0;color:#8888a0;font-size:12px;line-height:1.6;">
                ✅ Após a verificação, este dispositivo será <strong style="color:#e0e0e0;">confiável por 30 dias</strong>.<br>
                🚫 Se você não solicitou este código, ignore este e-mail — sua conta permanece segura.
              </p>
            </td></tr>
          </table>
        </td></tr>
        <!-- Rodapé -->
        <tr><td style="padding:18px 40px;background:rgba(0,0,0,0.3);text-align:center;border-top:1px solid rgba(255,255,255,0.04);">
          <p style="margin:0;color:#444460;font-size:11px;">© ${new Date().getFullYear()} ${APP_TAGLINE}</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────
/// Código de 6 dígitos uniforme em [100000, 999999], sem viés de módulo:
/// valores acima do maior múltiplo de 900000 que cabe em 32 bits são
/// descartados e sorteados de novo.
function generateOtp(): string {
  const range = 900000;
  const limit = Math.floor(0x100000000 / range) * range;
  const buf = new Uint32Array(1);
  do {
    crypto.getRandomValues(buf);
  } while (buf[0] >= limit);
  return String(100000 + (buf[0] % range));
}

function maskEmail(email: string): string {
  const [local, domain] = email.split('@');
  if (!local || !domain) return '***@***';
  const visible = local.substring(0, Math.min(3, local.length));
  return `${visible}${'*'.repeat(Math.max(0, local.length - 3))}@${domain}`;
}

function jsonResponse(data: Record<string, any>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
