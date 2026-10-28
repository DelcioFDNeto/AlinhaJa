// ============================================================
// CORS compartilhado (achado de segurança 1.11)
//
// Todas as functions respondiam `Access-Control-Allow-Origin: *`.
// Para as que são chamadas pelo navegador com o JWT do usuário
// (get-agora-token, rh-gerar-questoes), isso permite que qualquer site
// aberto na mesma sessão dispare requisições à nossa API e leia a
// resposta.
//
// Aqui a origem é confrontada com uma allowlist. Origem desconhecida
// não recebe cabeçalho de CORS e o navegador bloqueia a leitura.
//
// Configure em produção:
//   npx supabase secrets set ALLOWED_ORIGINS="https://alinha-ja-app.web.app,https://alinhajadev.web.app"
// ============================================================

/// Origens liberadas quando ALLOWED_ORIGINS não está configurada.
/// Cobre os hosts atuais do app e o desenvolvimento local do Flutter Web.
/// Multi-tenant: alem dos hosts do app (prod e homologacao) entra o
/// `alinha-ja-admin`, host do Console de Plataforma — ele chama as mesmas
/// functions e ficaria bloqueado por CORS se ficasse de fora.
const DEFAULT_ORIGINS = [
  'https://alinha-ja-app.web.app',
  'https://alinha-ja-app.firebaseapp.com',
  'https://alinhajadev.web.app',
  'https://alinhajadev.firebaseapp.com',
  'https://alinha-ja-admin.web.app',
  'https://alinha-ja-landing.web.app',
];

function allowlist(): string[] {
  const configured = Deno.env.get('ALLOWED_ORIGINS');
  if (configured && configured.trim() !== '') {
    return configured.split(',').map((o) => o.trim()).filter(Boolean);
  }
  return DEFAULT_ORIGINS;
}

function isLocalhost(origin: string): boolean {
  // O Flutter Web em debug sobe numa porta aleatória de localhost.
  return /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
}

/// Cabeçalhos de CORS para a origem da requisição.
///
/// `publicEndpoint` afrouxa para `*` — use apenas onde o recurso é
/// deliberadamente público e não depende de credencial do usuário
/// (ex.: portal de carreiras, que pode ser embutido em outro site).
export function corsHeadersFor(
  req: Request,
  opts: { publicEndpoint?: boolean } = {},
): Record<string, string> {
  const base: Record<string, string> = {
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type, x-webhook-secret',
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
    'Vary': 'Origin',
  };

  if (opts.publicEndpoint) {
    return { ...base, 'Access-Control-Allow-Origin': '*' };
  }

  const origin = req.headers.get('Origin') ?? '';
  if (origin && (allowlist().includes(origin) || isLocalhost(origin))) {
    return { ...base, 'Access-Control-Allow-Origin': origin };
  }

  // Origem desconhecida (ou chamada servidor-a-servidor, que não manda
  // Origin): sem cabeçalho de permissão. Não bloqueia o webhook — o
  // navegador é quem aplica CORS, e trigger de banco não é navegador.
  return base;
}
