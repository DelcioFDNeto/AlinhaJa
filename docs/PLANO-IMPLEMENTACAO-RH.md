# Plano de Implementação — Módulo RH (AlinhaJá)

> Baseado em `AlinhaJa_Modulo_RH_Escopo_v1.docx` (Escopo Linear v1.0, jun/2026).
> Objetivo maior: evoluir o AlinhaJá para plataforma SaaS multi-tenant com múltiplos
> módulos (estilo CRM cloud), mantendo o app Android instalável + PWA existente.
> Plano criado em 08/07/2026.

## 1. Ambientes (novo fluxo de desenvolvimento)

| Item | DEV | PROD |
|---|---|---|
| Branch GitHub | `Alinhaja-dev` | `AlinhaJa` |
| Hosting Firebase | `alinhajadev` → https://alinhajadev.web.app (target `app-dev`) | `alinha-ja-app` (target `app`) |
| Supabase | **AlinhaJá Dev** — ref `ffsspqscpdxlmxuaiytj` (sa-east-1) | **AlinhaJá** — ref `gpeemngsxvqjflasdody` (us-west-2) |
| E-mail p/ candidato | sandbox/e-mail de teste (S021) | Gmail SMTP (denomailer) — **não Resend** como diz o escopo |

Regras:
- Todo o Módulo RH nasce na `Alinhaja-dev` apontando para o banco DEV. Promoção a PROD só após os 12 bloqueios (seção 8).
- Primeiro passo prático: **provisionar o banco DEV** aplicando as migrations existentes do repo (`supabase link --project-ref ffsspqscpdxlmxuaiytj` + `supabase db push`) + seed mínimo (org DuBairro, filiais, deptos, ~5 usuários de teste). Atenção à [armadilha de encoding](../supabase/scripts/03_verificar_funcionarios_dubairro.sql): executar seeds sempre em UTF-8.
- Criar `dart_defines.dev.json` (URL/anon key do banco DEV) — build dev usa `--dart-define-from-file=dart_defines.dev.json`; o `dart_defines.json` continua sendo o de produção. Nenhum dos dois vai para o git.
- Banner visual "AMBIENTE DEV" no app quando apontando ao banco dev (S022) — decidir por dart-define `ENVIRONMENT=dev`.

## 2. Fase 0 — Fundação Multi-Tenant (pré-requisito de tudo)

O schema atual **não tem tenancy**: não existem `organizations` nem `organization_id`. O escopo exige `organization_id NOT NULL` em todas as tabelas RH (S001) e o objetivo SaaS exige isso em toda a plataforma. Estratégia incremental:

1. **Migration `create_organizations`**: tabela `organizations` (`id uuid`, `name`, `slug unique` — usado em `/carreiras/:slug`, `logo_url`, `active`, `settings jsonb`, timestamps). Seed: organização `dubairro` (INOVAR SERVIÇOS LTDA).
2. **`organization_id` nas tabelas de estrutura**: `branches`, `departments`, `job_positions`, `public.users` ganham `organization_id NOT NULL DEFAULT <org dubairro>` (backfill + remover default depois). RLS dessas tabelas passa a filtrar por org do usuário (`fn_current_org()` lendo claim/linha do usuário).
3. **Helper functions**: `fn_current_org()`, `fn_has_role(text)`, `fn_is_rh()` — SECURITY DEFINER, estáveis, usadas por todas as policies RH.
4. **RBAC estendido** (S016/S017): novos papéis `rh_admin`, `rh_operador`, `gestor_filial`, `gestor_setor` somados aos existentes. Matriz de permissões documentada em `docs/RBAC-RH.md`.
5. **Não retrofitar ainda** as tabelas de chat/workflow/helpdesk com `organization_id` — fica para a fase "SaaS aberto" (seção 9). O módulo RH nasce multi-tenant; o legado é migrado depois com a org DuBairro como default.

## 3. Ordem de implementação dos módulos

A ordem respeita dependências (dados → portal → IA → funcionário → onboarding → documentos):

### Etapa 1 — Módulo 0 + RH-1 Banco de Talentos (S001–S041)
- Migrations: `candidato`, `candidato_curriculo`, `candidato_formacao`, `candidato_experiencia`, `candidato_habilidade`, `candidato_historico` — todas com `organization_id NOT NULL`, RLS, auditoria (`created_by` etc.), soft delete, índices (S026), `unique(organization_id, email)` (S035), CHECK de consentimento LGPD (S036).
- Máquina de estados de status via trigger (S039/S040) + view de contagens (S041).
- Bucket `rh-curriculos` (privado, 5MB, PDF/DOCX por MIME) e `rh-documentos` (10MB) — separados dos buckets atuais (S013/S014).
- Flutter: `lib/features/hr/` (novo feature module) — `talent_bank_screen` (lista+filtros+busca com debounce 300ms e paginação 50), `candidate_detail_screen`, upload manual. Entrada pelo menu principal visível só para papéis RH (S018/S019 — guard no go_router, mesmo padrão do `require_aal2`).

### Etapa 2 — RH-2 Portal do Candidato (S042–S054)
- Rota **pública** `/carreiras/:orgSlug` no próprio app Flutter web (go_router com grupo de rotas sem auth guard — splash/login não podem interceptar). Validação do slug via RPC anônima que expõe apenas nome/setores visíveis (S043/S044).
- Submissão via Edge Function `rh-candidatura` (não insert direto do anon): valida campos, MIME real do arquivo, rate limit 10/IP/h (tabela `rh_rate_limit` ou KV), registra IP/user-agent, grava consentimento LGPD com versão do termo, gera token de acompanhamento (UUID + expiração 90 dias) e dispara e-mail.
- Edge Function `rh-email-candidato`: confirmação + link da área do candidato. **Gmail SMTP** (mesmo padrão do `send-2fa-code`), secrets `GMAIL_USER`/`GMAIL_APP_PASSWORD`; em DEV, redirecionar para e-mail de teste (S021).
- Área do candidato (`/candidato/:token`): status, mensagens do RH, upload adicional — tudo servido por Edge Function/RPCs que validam o token (nunca expor IDs internos, S053).

### Etapa 3 — RH-3 IA de Currículo (S055–S069)
- Edge Function `rh-extract-cv` disparada por webhook/trigger no insert de `candidato_curriculo` (mesmo padrão pg_net já usado nas notificações do workflow).
- Parse PDF (`pdf-parse`/unpdf) e DOCX (`mammoth`) em Deno; texto → Claude API `claude-haiku-4-5-20251001`, saída JSON validada com Zod (S060/S061), máx 4096 tokens output.
- **LGPD (S068)**: remover nome/telefone/e-mail do texto antes de enviar à API (regex de PII básico) — enviar só o corpo do currículo.
- Persistência atômica + status `extraido`; falha → `extracao_pendente` + notificação ao RH + 1 retry após 30s (S064/S065).
- Tabela `ia_usage_log` (S067/S069) — base do billing futuro do SaaS.
- Secret `ANTHROPIC_API_KEY` só na Edge Function (B010).

### Etapa 4 — RH-4 Ficha do Funcionário (S070–S081)
- Tabelas `funcionario` (públicos), `funcionario_dados_sensiveis` (restrita), `vinculo` (1:N, com `filial_id/departamento_id/cargo_id` referenciando o organograma existente — S070–S072, RH-4.9).
- **Criptografia**: usar `pgsodium`/Vault do Supabase para `cpf_encrypted`, `dados_bancarios_encrypted`, `salario_encrypted` + `cpf_hash` para o unique por org (S073/S077). Decrypt só via RPC SECURITY DEFINER que exige papel RH **e registra em `rh_access_log`** (S008/B009).
- RLS em duas camadas (S074) + view `funcionario_resumo` (S075).
- Validação de CPF (dígitos verificadores) no backend (S076).
- Conversão candidato→funcionário em RPC transacional: copia dados, cria vínculo, guarda `candidato_id`, inicia onboarding (S078/S079 — é o teste B011).
- Relação com `public.users` existente: funcionário RH ≠ conta de acesso; campo opcional `user_id` liga a ficha à conta AlinhaJá quando existir (os 178 do DuBairro viram fichas via script de carga a partir da planilha).

### Etapa 5 — RH-5 Onboarding (S082–S092)
- Tabelas de template/execução/item + `periodo_experiencia` (45+45, alerta D-7).
- Trigger de progresso (S088) e bloqueio de conclusão com obrigatórios pendentes (S091).
- Cron diário (`pg_cron`, já disponível no Supabase) para alertas de experiência e itens atrasados, notificando via sistema de notificações existente do AlinhaJá (S089/S090).
- Comunicado de admissão reusa "Estou Ciente" (RH-5.9).

### Etapa 6 — RH-6 Documentos (S093–S103)
- Tabela `documento` + enum de categorias; Cron diário de vencimento (S095) — pode ser o mesmo job da etapa 5 (`rh-cron-vencimentos`, a 3ª Edge Function do escopo, ou 100% `pg_cron` em SQL).
- Fluxo funcionário-envia/RH-aprova (S097/S098), RLS por `funcionario_id` (S099), download por signed URL 15min (S102), soft delete (S103).
- Integração onboarding→repositório (S092).
- Tela "Meus Documentos" no app do funcionário (RH-6.6).

## 4. Divergências conscientes em relação ao escopo

| Escopo diz | Fazemos | Motivo |
|---|---|---|
| E-mail via Resend | Gmail SMTP (denomailer) | AlinhaJá não tem domínio próprio; padrão já adotado no `send-2fa-code` |
| DEV/PROD "a criar" | Já existem (seção 1) | Feito em 08/07 |
| Cronograma 01–14/07, go-live 15/07 | Ver seção 7 | O plano só começou em 08/07 |
| 3 Edge Functions | 3–4 (`rh-candidatura` separada do e-mail por segurança/rate-limit) | Validação server-side do portal público |

## 5. Estrutura no repositório

```
lib/features/hr/
  models/ services/ providers/ ui/        # padrão dos features existentes
supabase/migrations/2026MMDDHHMMSS_rh_*.sql
supabase/functions/rh-candidatura/ rh-email-candidato/ rh-extract-cv/ rh-cron-vencimentos/
docs/RBAC-RH.md                            # matriz de permissões (S017)
```

Convenções: valores internos/enums do banco em snake_case estáveis (mesma lição dos templates de workflow — label muda, `value` nunca). Textos com acento: conferir UTF-8 após qualquer geração/patch.

## 6. Segurança — pontos de atenção específicos deste app

- As policies restritivas `require_aal2`/`require_email_2fa` existem nas tabelas atuais. **Decidir**: tabelas RH (dados sensíveis!) devem receber as mesmas policies restritivas — sim para tudo exceto as rotas públicas do candidato (que passam por Edge Function com service role, não são afetadas).
- O portal público é a primeira superfície sem login do app — revisar que nenhuma policy `anon` seja criada nas tabelas; todo acesso anônimo passa por Edge Function/RPC com token.
- Módulo RH é **exclusivo do AlinhaJá** — não portar para o Fluxy (exceção explícita à regra de paridade, como os templates genéricos).

## 7. Cronograma realista (a partir de 08/07)

| Semana | Entrega |
|---|---|
| 08–11/07 | Fase 0 (multi-tenant) + Etapa 1 (Banco de Talentos) no DEV |
| 12–15/07 | Etapas 2 e 3 (Portal + IA) no DEV |
| 16–18/07 | Etapa 4 (Ficha) + carga dos 178 funcionários DuBairro |
| 19–21/07 | Etapas 5 e 6 (Onboarding + Documentos) |
| 22–23/07 | Checklist de bloqueios B001–B012, testes de RLS por perfil (S003), backup/restore (S025) |
| 24/07 | Go-live PROD (migrations + functions + deploy web/APK) |

MVP go-live 15/07 do escopo original é inviável com qualidade nos 12 bloqueios; proposta acima desliza ~9 dias. Se 15/07 for imutável, cortar Etapas 5–6 do go-live (entram na semana seguinte).

## 8. Bloqueios de go-live (checklist B001–B012)

RLS testado por perfil · criptografia verificada · termo LGPD funcional · fallback de IA · CPF/e-mail duplicado · DEV/PROD separados ✅ · backup+restore testado · rate limiting · log de acesso a sensíveis · chaves só no backend · teste candidato→funcionário→onboarding · vencimento de documentos testado.

## 9. Rumo ao SaaS (pós-Fase 1, direção)

1. Retrofit de `organization_id` nas tabelas legadas (chat, workflow, helpdesk, GPS) com RLS por org.
2. Onboarding self-service de empresas (signup de org + admin) e billing por módulo/uso (a `ia_usage_log` já nasce pronta).
3. Módulos plugáveis: flag `organizations.settings.modules` habilitando RH/Workflow/Helpdesk por tenant.
4. Fases 2–4 do RH conforme escopo (vagas, férias, escalas, ponto, dashboards, eSocial).
