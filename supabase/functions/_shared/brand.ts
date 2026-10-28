// ============================================================
// brand-guard:allow-file
// brand.ts — identidade da marca para as Edge Functions
//
// Fluxy (Shineray by Sabel) e AlinhaJá (DuBairro) são o MESMO código com
// deployments distintos. Enquanto o nome do app e o da empresa ficavam
// hardcoded nas functions, todo sync entre os forks era uma chance de
// vazamento — foi exatamente assim que "Shineray by Sabel" acabou no
// prompt do bot do AlinhaJá, afirmando a colaborador do DuBairro que ele
// trabalha na Shineray.
//
// A fonte de verdade passa a ser o Secret do projeto Supabase. Cada marca
// tem o seu projeto, então o valor nunca cruza a fronteira:
//
//   # projeto do AlinhaJá
//   npx supabase secrets set APP_NAME="AlinhaJá" \
//                            COMPANY_NAME="DuBairro" \
//                            LANDING_URL="https://alinha-ja-landing.web.app"
//
//   # projeto do Fluxy
//   npx supabase secrets set APP_NAME="Fluxy" \
//                            COMPANY_NAME="Shineray by Sabel" \
//                            LANDING_URL="https://fluxy-landing.web.app"
//
// Os defaults abaixo são a marca DESTE repositório e existem só para o
// caso de o Secret não estar configurado. `scripts/check_brand.sh` falha
// se eles forem trocados pela marca do outro fork.
// ============================================================

/// Nome do aplicativo, como aparece para o usuário final.
export const APP_NAME = Deno.env.get('APP_NAME')?.trim() || 'AlinhaJá';

/// Razão/nome comercial do tenant natal deste deployment.
///
/// NÃO use para identificar a empresa de um usuário: o projeto é
/// multiempresa e o nome correto é `organizations.name` do tenant da
/// requisição. O prompt do assistente deixou de ler esta constante por isso
/// — com ela, o colaborador de qualquer cliente ouvia que trabalhava aqui.
export const COMPANY_NAME =
  Deno.env.get('COMPANY_NAME')?.trim() || 'DuBairro';

/// Host da landing, usado para montar URLs de imagem nos e-mails.
export const LANDING_URL =
  Deno.env.get('LANDING_URL')?.trim() || 'https://alinha-ja-landing.web.app';

/// Endereço público do aplicativo web, usado nos links enviados por e-mail
/// (área do candidato, verificação de conta). Em instalação própria do
/// cliente, aponta para o domínio dele.
export const APP_BASE_URL =
  (Deno.env.get('APP_BASE_URL')?.trim() || 'https://alinha-ja-app.web.app')
    .replace(/\/+$/, '');

/// Assinatura padrão de rodapé de e-mail.
export const APP_TAGLINE = `${APP_NAME} — Comunicação Empresarial Inteligente`;

/// Logo usado no cabeçalho dos e-mails transacionais.
export const EMAIL_LOGO_URL = `${LANDING_URL}/logo_header.webp`;
