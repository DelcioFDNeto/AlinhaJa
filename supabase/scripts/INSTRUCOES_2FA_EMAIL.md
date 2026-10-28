# Ativação do 2FA por e-mail (opt-in) — banco DuBairro/AlinhaJá

> Para o agente executor via MCP (Supabase MCP server). O código Flutter já
> está commitado; falta o lado banco/infra descrito aqui.

## Status da execução (07/07/2026)

- ✅ **Migration aplicada** via MCP no `gpeemngsxvqjflasdody`: coluna
  `email_2fa_enabled`, policy `require_email_2fa` e RPCs de segurança no ar.
- ✅ **Edge function `send-2fa-code`**: estava `ACTIVE`, mas era a versão
  Resend herdada do Fluxy. Em 07/07/2026 o código foi reescrito para **SMTP
  do Gmail** (AlinhaJá não tem domínio próprio para usar Resend) e rebrandado
  (logo/cores/assunto AlinhaJá). ⏳ **PENDENTE: redeployar** a function com o
  código novo deste repo.
- ⏳ **PENDENTE — secrets da function** (Dashboard → Edge Functions →
  Secrets, ou `supabase secrets set`): `GMAIL_USER` (conta Gmail remetente) e
  `GMAIL_APP_PASSWORD` (senha de app do Google — requer verificação em 2
  etapas na conta; não é a senha normal). Opcional: `SENDER_NAME` (default
  "AlinhaJá"). **Até redeploy + secrets, não ativar o toggle de 2FA por
  e-mail em produção** (o código de verificação não seria enviado).
- ✅ **Build + deploy**: `flutter build web --release
  --dart-define-from-file=dart_defines.json` + Firebase Hosting; versão no ar
  em alinha-ja-app.web.app.
- ⏳ Teste manual (Passo 3 abaixo) pendente até os secrets serem definidos.

## Projeto alvo (NÃO CONFUNDIR)

| Empresa | App | Projeto Supabase (ref) |
|---|---|---|
| DuBairro (supermercado) | AlinhaJá | `gpeemngsxvqjflasdody` ← **alvo** |
| Shineray (concessionária) | Fluxy | `hzvmqsgpopgfkvdxyain` (já aplicado lá; não tocar) |

Confirme via `get_project`/`list_projects` que o MCP está conectado ao
`gpeemngsxvqjflasdody` **antes** de qualquer comando.

## Passo 1 — Aplicar a migration

Arquivo: [`../migrations/20260707150000_email_2fa_opt_in_enforcement.sql`](../migrations/20260707150000_email_2fa_opt_in_enforcement.sql)

- Use `apply_migration` (é mudança de schema versionada), nome
  `email_2fa_opt_in_enforcement`.
- Segura em produção: cria `users.email_2fa_enabled` com default `false` e a
  policy restritiva `require_email_2fa` só afeta quem ativar a flag; ninguém
  é bloqueado no estado inicial.
- Conferência pós-aplicação:
  ```sql
  SELECT column_name FROM information_schema.columns
   WHERE table_name = 'users' AND column_name = 'email_2fa_enabled';
  SELECT polname FROM pg_policy WHERE polname = 'require_email_2fa';
  SELECT proname FROM pg_proc WHERE proname = 'register_2fa_session';
  ```

## Passo 2 — Edge function `send-2fa-code` (versão SMTP/Gmail)

1. **Redeployar** a function com o código atual de
   `supabase/functions/send-2fa-code/index.ts` deste repo (via MCP
   `deploy_edge_function` ou `supabase functions deploy send-2fa-code
   --project-ref gpeemngsxvqjflasdody`). A versão hoje ACTIVE no projeto é a
   antiga (Resend + branding Fluxy) e não funciona sem domínio.
2. Configurar os secrets: `GMAIL_USER` e `GMAIL_APP_PASSWORD` (senha de app
   do Google). Diferente do Fluxy, que usa Resend — **não** copiar secrets
   de lá.
3. Sem redeploy + secrets, quem ativar o toggle de 2FA por e-mail não
   recebe o código em dispositivo novo.

## Passo 3 — Teste manual (humano)

1. Navegador anônimo: login normal deve entrar direto (flag nasce `false`).
2. Configurações → Segurança e 2FA → ativar "Exigir código por e-mail".
3. Logar em outro navegador → deve cair em `/verify-email-2fa` e receber o
   código por e-mail.
4. Sem validar o código, a API REST não deve retornar mensagens (RLS
   `require_email_2fa`).
5. Fluxo TOTP (app autenticador) existente deve continuar intacto.

## Regra permanente de paridade

Qualquer mudança futura em auth/2FA num dos repos deve ser espelhada no
outro (Fluxy ⇄ AlinhaJá), preservando: package name, issuer TOTP
(`Fluxy`/`AlinhaJá`), fingerprint key (`alinhaja_device_fingerprint`) e o
gate `require_aal2` que só existe no AlinhaJá.
