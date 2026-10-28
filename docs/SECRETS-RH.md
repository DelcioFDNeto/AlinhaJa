# Provisionamento de Secrets — Módulo RH

Guia de onde encontrar e como inserir cada secret que o Módulo RH usa.
Há **dois lugares distintos** onde secrets vivem:

1. **Supabase Vault** (dentro do banco) — lido por funções SQL `SECURITY DEFINER`
   via `vault.decrypted_secrets`. Nunca aparece no repositório nem no frontend.
2. **Edge Function Secrets** (variáveis de ambiente das Functions) — lidas com
   `Deno.env.get(...)` dentro das Edge Functions.

> **Ambientes separados (S020/B006).** Tudo abaixo deve ser feito **duas vezes**,
> uma em cada projeto Supabase:
>
> - **DEV**: `ffsspqscpdxlmxuaiytj`
> - **PROD**: `gpeemngsxvqjflasdody`
>
> Onde achar: Supabase → seletor de projeto no topo. O `ref` do projeto aparece
> em **Project Settings → General → Reference ID** e na URL do dashboard.

---

## 0. Pré-requisito: habilitar extensões

Dashboard → **Database → Extensions** → habilitar:

- `pg_net` — dispara as Edge Functions a partir de triggers (extração de CV).
- `pg_cron` — agenda os jobs diários de RH (experiência, vencimentos, retenção LGPD).
- `pgcrypto` — criptografia dos dados sensíveis (a migration já faz `CREATE EXTENSION`).

Se o `pg_cron` for habilitado **depois** de rodar as migrations, reexecute os
blocos `cron.schedule` (ver seção 5) — as migrations avisam via `RAISE NOTICE`
quando pulam o agendamento.

---

## 1. Vault: `webhook_secret`

**O que é:** segredo compartilhado enviado no header `x-webhook-secret` quando um
trigger chama uma Edge Function, para a Function rejeitar chamadas forjadas.
Usado por `rh-extract-cv` e pelas notificações de workflow/chat.

**Onde inserir:** Dashboard → **SQL Editor** → rode (troque o valor por um segredo forte):

```sql
select vault.create_secret('COLE_UM_SEGREDO_FORTE_AQUI', 'webhook_secret');
```

O **mesmo valor** precisa ir também nas Edge Functions (seção 4, `WEBHOOK_SECRET`).

Gerar um valor forte (terminal):

```bash
openssl rand -hex 32
```

> Enquanto não existir, o header vai vazio e as Functions operam em modo
> compatibilidade (só logam warning) — nada quebra, mas fica sem proteção.

---

## 2. Vault: `edge_base_url`

**O que é:** URL base do projeto Supabase, usada pelo trigger de extração de CV
(`notify_rh_extract_cv`) para montar `…/functions/v1/rh-extract-cv` via `pg_net`.

**Onde inserir:** SQL Editor, **usando o ref do projeto certo**:

```sql
-- DEV
select vault.create_secret('https://ffsspqscpdxlmxuaiytj.supabase.co', 'edge_base_url');

-- PROD
select vault.create_secret('https://gpeemngsxvqjflasdody.supabase.co', 'edge_base_url');
```

> Sem este secret, o trigger **não dispara** a IA e o candidato fica com
> `extracao = 'pendente'` (fallback S064) — o RH preenche manualmente. Nada trava.

---

## 3. Vault: chaves de IA por organização (BYOK)

**O que é:** cada empresa fornece a própria chave da Anthropic. Fica em
`ai_key_anthropic_<organization_id>`. A `rh-extract-cv` lê via
`get_org_ai_key` (exclusivo da service role).

**Onde inserir — jeito recomendado (pelo app):** o admin da empresa configura em
**Painel Admin → Chave de IA** (RPC `set_org_ai_key`, já implementada). Assim a
chave nunca passa por SQL manual.

**Alternativa manual (SQL Editor):**

```sql
select vault.create_secret('sk-ant-xxxxxxxx', 'ai_key_anthropic_<ORG_ID>');
```

> `rh_data_key_<org_id>` (criptografia dos dados sensíveis) **não precisa** de ação
> manual: `fn_rh_data_key` gera e grava no Vault sob demanda no primeiro uso.

---

## 4. Edge Function Secrets

**Onde inserir:** duas opções.

- **CLI:** `npx supabase secrets set NOME=valor --project-ref <ref>`
- **Dashboard:** projeto → **Edge Functions → Manage secrets** (ou
  **Project Settings → Edge Functions → Secrets**).

### 4.1 `rh-extract-cv`

| Secret           | Valor                        |
| ---------------- | ---------------------------- |
| `WEBHOOK_SECRET` | **o mesmo** valor da seção 1 |

`SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` são injetados automaticamente pela
plataforma — **não** configure manualmente.

### 4.2 `rh-candidatura` (portal do candidato + e-mail de confirmação)

O servidor de e-mail é o mesmo de todas as functions (`_shared/mailer.ts`). Use
**um** dos dois formatos — `SMTP_*` tem prioridade quando `SMTP_HOST` existe:

| Secret               | Valor / observação                                                                                                         |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `SMTP_HOST`          | servidor de qualquer provedor, ex.: `smtp.office365.com`, `email-smtp.sa-east-1.amazonaws.com`, SMTP interno do cliente    |
| `SMTP_PORT`          | `465` = TLS direto (padrão); `587` ou outra = STARTTLS                                                                     |
| `SMTP_USER`          | usuário de autenticação                                                                                                    |
| `SMTP_PASSWORD`      | senha (ou senha de app)                                                                                                    |
| `SMTP_FROM_EMAIL`    | opcional: remetente, quando difere do usuário (ex.: `nao-responda@empresa.com.br`)                                         |
| `GMAIL_USER`         | formato anterior, ainda aceito: e-mail Gmail remetente (`smtp.gmail.com:465`)                                              |
| `GMAIL_APP_PASSWORD` | **App Password** do Gmail (não é a senha normal — gere em myaccount.google.com → Segurança → Senhas de app, com 2FA ativo) |
| `SENDER_NAME`        | opcional, ex.: `AlinhaJá` (padrão)                                                                                         |
| `APP_BASE_URL`       | base do link da área do candidato, ex.: `https://alinhajadev.web.app`                                                      |
| `DEV_EMAIL_OVERRIDE` | **só no projeto DEV** (S021): e-mail de teste que recebe _todos_ os e-mails, evitando disparo para candidatos reais em DEV |

Exemplo (CLI, projeto DEV):

```bash
npx supabase secrets set \
  GMAIL_USER=rh@empresa.com \
  GMAIL_APP_PASSWORD=xxxxxxxxxxxxxxxx \
  APP_BASE_URL=https://alinhajadev.web.app \
  DEV_EMAIL_OVERRIDE=qa@empresa.com \
  --project-ref ffsspqscpdxlmxuaiytj
```

Em **PROD**, repita **sem** `DEV_EMAIL_OVERRIDE` e com `APP_BASE_URL` de produção.

---

## 5. Agendamento dos jobs diários (pg_cron)

As migrations já agendam quando o `pg_cron` está habilitado. Se você habilitou o
`pg_cron` depois, rode no SQL Editor para (re)criar os jobs:

```sql
select cron.schedule('rh-cron-diario',       '0 9 * * *', $$ select public.fn_rh_cron_diario(); $$);            -- experiência D-7 / itens atrasados
select cron.schedule('rh-documentos-diario', '0 8 * * *', $$ select public.rh_atualizar_status_documentos(); $$); -- vencimento de documentos + alertas
select cron.schedule('rh-lgpd-diario',       '0 3 * * *', $$ select public.fn_rh_expirar_candidatos(); $$);      -- retenção/anonimização LGPD
```

Conferir os jobs ativos:

```sql
select jobname, schedule, active from cron.job order by jobname;
```

---

## 6. Checklist rápido por ambiente

Marque para DEV **e** para PROD:

- [ E ] Extensões `pg_net`, `pg_cron`, `pgcrypto` habilitadas
- [ E ] Vault `webhook_secret` criado
- [ E ] Vault `edge_base_url` criado (URL do ref correto)
- [ E ] Edge secret `WEBHOOK_SECRET` = mesmo valor do Vault
- [ E ] Edge secrets do `rh-candidatura` (Gmail, APP_BASE_URL; `DEV_EMAIL_OVERRIDE` só em DEV)
- [ ] Chave de IA da organização configurada (Painel Admin ou Vault)
- [ E ] 3 jobs de cron aparecem em `cron.job`
- [ ] Política de retenção conferida (`rh_set_retencao_candidatos`, padrão 24 meses)
