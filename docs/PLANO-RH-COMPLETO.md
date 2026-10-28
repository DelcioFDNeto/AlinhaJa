# Plano de Implementação — RH Completo ("AlinhaJá Talentos")

> Evolução do Módulo RH para uma suíte completa de **Recrutamento + Gestão de Pessoas**, superando o escopo inicial (S001–S103). Inspirado no comparativo com o projeto **talentflow-suite** (`../talentflow-suite`), adaptado à nossa arquitetura Supabase multi-tenant, tokens de status white-label e registro de módulos.

**Status:** implementado (Fases 1–9) · **Branch de trabalho:** `Alinhaja-dev` · **Deploy de validação:** `alinhajadev.web.app` antes de produção.

> **Situação em 22/07/2026** — as nove fases saíram do papel (commits `342fecd` → `42c59dc`, mais `rh23`/`rh24`). O que ficou de fora está listado na seção **16. Pendências conhecidas**, no fim do documento. As descrições de cada fase abaixo são o plano original, mantidas como registro da decisão de projeto.

---

## 1. Onde estamos (baseline já entregue)

O módulo RH já cobre, hoje, um ATS funcional + ficha de funcionário:

| Área | Já implementado |
|------|-----------------|
| **Banco de Talentos** | Lista filtrável + funil Kanban com drag-and-drop, score de completude, histórico, comentários, soft-delete, LGPD (anonimização + retenção) |
| **Portal público** | `/carreiras/:slug` (candidatura sem login, via Edge Function `rh-candidatura`) e `/candidato/:token` (área do candidato: status + mensagens + upload) |
| **IA de currículo** | Extração multi-provedor (Gemini/Groq/…) com retry manual, `ia_usage_log` |
| **Ficha do Funcionário** | `funcionario` + `funcionario_dados_sensiveis` (cifrados, acesso auditado em `rh_access_log`), view `funcionario_resumo`, conversão candidato→funcionário |
| **Onboarding / Documentos / Alertas** | Templates de onboarding, documentos por funcionário, alertas de RH |
| **Infra** | Multi-tenant pool+RLS, `organizations.slug`/`logo_url`, registro único de módulos em `lib/core/modules`, tokens de status por papel |

**Pontos de apoio que o plano reaproveita:**
- `funcionario.user_id` (FK → `users`) **já existe** no schema (migration `20260709100000`) — falta só a UI/RPC para vincular.
- `organizations.slug` **já** alimenta `/carreiras/:slug` — falta só expor/divulgar o link.
- `qr_flutter` e `url_launcher` já estão no `pubspec` (QR + compartilhar prontos, sem nova dependência).

---

## 2. Comparativo com talentflow-suite (o que vale adotar)

O talentflow-suite é um ATS React/Node com foco em **avaliação técnica automatizada**. Recursos que nós ainda **não** temos e agregam valor real:

| talentflow-suite | Temos? | Vale adotar? |
|------------------|:------:|--------------|
| Catálogo **Áreas → Cargos** (dinâmico) | ❌ (temos texto livre) | ✅ Alto — estrutura filtros, vagas e testes |
| **Teste técnico** por cargo (múltipla escolha, auto-correção 0–100) | ❌ | ✅ Alto — grande diferencial de triagem |
| **Geração de questões por IA** (por cargo/nível) | ❌ (temos IA só p/ CV) | ✅ Médio — reaproveita nossa stack multi-provedor |
| **Dashboard** (funil, top talentos, distribuição, conversão) | ⚠️ parcial (pills de contagem) | ✅ Alto |
| **Timeline** de transições de status | ✅ (`candidato_historico`) | — já temos |
| **Login do candidato** / "minhas candidaturas" | ⚠️ (temos área por token, sem senha) | ✅ Médio |
| **Pipeline customizável** (etapas nomeáveis, responsável, ações em massa) | ❌ (etapas fixas) | ✅ Médio |
| **Observação interna** por candidato | ✅ (comentários no histórico) | — já temos |
| **Vagas** (job openings) publicáveis | ❌ | ✅ Alto — hoje o portal é genérico |
| Log de e-mails / notificações de status | ⚠️ (mensagens; sem e-mail automático) | ✅ Médio |

**Decisão de arquitetura:** não portamos código React. Reimplementamos os *conceitos* em Flutter + Supabase, respeitando multi-tenant (RLS por `organization_id`), tokens de status e Edge Functions (nada de acesso anônimo direto a tabelas).

---

## 3. Visão do produto

> **De** "banco de candidatos + ficha de funcionário" **para** "central de recrutamento e gestão de pessoas white-label".

Três pilares:
1. **Atrair** — vagas publicáveis, página de carreiras rica, link/QR de divulgação.
2. **Selecionar** — pipeline configurável, triagem por IA, avaliação técnica, scorecards.
3. **Gerir** — conversão em funcionário, vínculo com usuário do app, onboarding, documentos, desempenho.

---

## 4. FASE 1 — Pedidos imediatos (quick wins de alto impacto)

### F1.1 — Banco de Talentos vira **Central de Recrutamento**

Transformar a tela `talent_bank_screen.dart` de "lista + funil" em um **hub** com sub-navegação e, principalmente, um painel de **divulgação do link de inscrição**.

**Entregáveis (UI):**
- Reestruturar `TalentBankScreen` com `TabBar` / segmented control:
  1. **Pipeline** (a lista + funil atuais)
  2. **Divulgação** (novo) — ver abaixo
  3. **Vagas** (placeholder → Fase 2)
  4. **Ajustes** (retenção LGPD, etapas — cresce nas fases seguintes)
- **Painel de Divulgação** (`lib/features/hr/ui/widgets/careers_link_panel.dart`):
  - URL pública montada a partir do host + `organizations.slug`: `https://<host>/carreiras/<slug>`.
    Host resolvido por `Uri.base.origin` no Web e por constante de ambiente (`AppEnv`) no mobile.
  - Botões: **Copiar link** (`Clipboard`), **Compartilhar** (WhatsApp/e-mail via `url_launcher`: `wa.me?text=` e `mailto:`), **Abrir página**.
  - **QR code** (`qr_flutter`) com opção de baixar/expandir — ideal para material impresso.
  - **Estado da página**: toggle "Página de carreiras ativa/inativa" (novo campo `organizations.carreiras_ativo`, default `true`).
  - Métricas de divulgação: nº de inscrições nos últimos 30 dias, taxa de conversão do portal (inscritos → em processo).
- Mover a criação de candidato manual e a busca para dentro da aba **Pipeline** (comportamento atual preservado).

**Backend:**
- Migration aditiva: `organizations.carreiras_ativo BOOLEAN NOT NULL DEFAULT true`, `organizations.carreiras_headline TEXT`, `organizations.carreiras_sobre TEXT` (para o RH editar a mini-landing sem código).
- Edge Function `rh-candidatura` (action `org`): retornar também `carreiras_ativo`, `carreiras_headline`, `carreiras_sobre`; e **bloquear** `apply` quando `carreiras_ativo = false` (mensagem amigável).
- View/consulta para as métricas de divulgação (reuso de `candidato` com filtro por `fonte='portal'` e `created_at`).

**Esforço:** ~M (1 painel + tabs + 1 migration curta + ajuste na Edge Function).

### F1.2 — Vincular **Funcionário ↔ Usuário** do app

Permitir, na ficha do funcionário, associar o registro a um usuário existente da organização (e desvincular).

**Entregáveis (UI):**
- Em `employee_detail_screen.dart`: seção "Acesso ao app" com:
  - Estado atual: "Vinculado a **Fulano** (email)" com avatar, ou "Sem usuário vinculado".
  - Ação **Vincular usuário** → bottom sheet com busca de usuários da org (nome/email), lista filtrável, exclui usuários já vinculados a outro funcionário.
  - Ação **Desvincular** (com confirmação).
- Badge "tem app" na lista de funcionários (`employees_screen.dart`) quando `userId != null`.

**Backend:**
- RPC `rh_vincular_usuario(p_funcionario_id, p_user_id)` e `rh_desvincular_usuario(p_funcionario_id)`:
  - valida papel RH (admin), mesma `organization_id`, e **unicidade 1:1** (um user ↔ um funcionário) — impedir vínculo duplicado.
  - grava auditoria em `rh_access_log`.
- Índice único parcial: `CREATE UNIQUE INDEX ... ON funcionario(user_id) WHERE user_id IS NOT NULL AND deleted_at IS NULL`.
- View de suporte `org_users_vinculaveis` (usuários da org + flag `ja_vinculado`) para alimentar a busca.

**Por que importa:** fecha o ciclo candidato → funcionário → **usuário do app** (chat, documentos, onboarding self-service já dependem de `funcionario.user_id`).

**Esforço:** ~S–M (2 RPCs + 1 índice + 1 sheet de busca).

---

## 5. FASE 2 — Vagas (Job Openings)

Hoje o portal é genérico ("Trabalhe conosco"). Introduzir **vagas** publicáveis dá foco e melhora os dados.

- **Tabelas:** `vaga` (org, titulo, area_id, cargo_id, nivel, tipo_contrato, localidade, remoto, faixa_salarial, descricao, requisitos, status[rascunho|aberta|pausada|fechada], vagas_qtd, publicada_em, expira_em). `candidato.vaga_id` (opcional; candidatura espontânea permanece com `vaga_id NULL`).
- **Portal:** `/carreiras/:slug` lista vagas abertas; `/carreiras/:slug/vaga/:id` abre o form já vinculado à vaga (o form da Fase de landing vira o "candidatar-se a esta vaga").
- **Central:** aba **Vagas** com CRUD, contadores de candidatos por vaga, botão "compartilhar vaga" (link/QR por vaga).
- **RLS:** leitura pública só de vagas `aberta` (via Edge Function); escrita só RH.

**Esforço:** ~L.

---

## 6. FASE 3 — Avaliação Técnica + IA generativa de questões

O maior diferencial do talentflow. Triagem automática por prova objetiva.

- **Tabelas:** `questao` (org, cargo_id/area_id, nivel, enunciado, opcoes[], correta_idx, origem[manual|ia]), `avaliacao` (candidato_id, vaga_id?, nota, iniciada_em, finalizada_em), `avaliacao_resposta` (avaliacao_id, questao_id, resposta_idx, correta).
- **Fluxo candidato:** após enviar candidatura → opcionalmente redirecionar para prova (N questões, timer configurável), correção **no servidor** (Edge Function — nunca enviar `correta_idx` ao cliente), nota 0–100 grava em `avaliacao` e alimenta o score.
- **IA:** Edge Function `rh-gerar-questoes` reaproveitando a stack multi-provedor (Gemini/Groq) já usada em `rh-extract-cv`: entrada `{cargo, nivel, quantidade}`, saída JSON validada (Zod-like) antes de persistir. Prompt inspirado no talentflow (Módulo 6). Custo controlado (modelo econômico, teto de 15 questões).
- **Central:** aba **Avaliações** (banco de questões por cargo, gerar com IA, ver resultados por candidato — quais acertou/errou).

**Riscos:** segurança das respostas (correção server-side obrigatória), custo de IA (logar em `ia_usage_log`, teto por org).

**Esforço:** ~XL (é praticamente um submódulo).

---

## 7. FASE 4 — Catálogo Áreas / Cargos / Competências

Estrutura que destrava filtros consistentes, vagas e testes (hoje `area_interesse`/`cargo_pretendido` são texto livre).

- **Tabelas:** `rh_area` (org, nome), `rh_cargo` (org, area_id, nome, nivel_sugerido), `rh_competencia` (org, nome), `cargo_competencia` (N:N). Já existem `job_positions`/`departments`/`branches` — mapear/reusar em vez de duplicar.
- **Migração suave:** manter campos texto atuais; adicionar `*_id` opcionais; job de normalização best-effort.
- **UI:** aba **Ajustes → Catálogo** (CRUD simples, multi-tenant).

**Esforço:** ~M.

---

## 8. FASE 5 — Pipeline avançado

- **Etapas customizáveis por org:** tabela `pipeline_etapa` (org, nome, ordem, role_cor, terminal?). O funil deixa de ser fixo em `CandidateStatus` e passa a ler as etapas da org (com seed = etapas atuais para não quebrar). Manter o trigger de validação de transição, agora dirigido por dados.
- **Responsável:** `candidato.responsavel_id` (FK users) + filtro "meus candidatos".
- **Ações em massa:** seleção múltipla na lista → mover etapa / descartar / atribuir responsável em lote.
- **SLA / tempo em etapa:** derivar do `candidato_historico`; alertar candidatos "parados" há > N dias.

**Esforço:** ~L (o trigger de status data-driven exige cuidado).

---

## 9. FASE 6 — Dashboard & Analytics de RH

- Nova tela/aba **Visão Geral**: funil (por etapa), taxa de conversão, tempo médio no pipeline, top talentos (por score/nota), distribuição por área/nível/fonte, contratações no período.
- **Headcount / gestão:** distribuição por status, admissões vs. desligamentos, turnover, aniversários/tempo de casa.
- **Dependência:** adicionar lib de gráficos (`fl_chart`) — **única nova dependência** relevante do plano.
- Views agregadas no banco (reuso do padrão `*_contagem_status`), respeitando RLS.
- **Export** CSV (e PDF opcional) dos relatórios.

**Esforço:** ~M–L.

---

## 10. FASE 7 — Portal do candidato com login

Evoluir `/candidato/:token` para conta persistente:
- Login por e-mail (magic link/OTP via Supabase Auth em projeto/escopo isolado, ou senha própria do candidato como no talentflow).
- "Minhas candidaturas": histórico de vagas, notas de avaliação, status.
- Reaproveitamento de currículo entre candidaturas.

**Esforço:** ~L (decisão de auth é o ponto sensível — avaliar impacto multi-tenant).

---

## 11. FASE 8 — Gestão de Pessoas (aprofundar o que já existe)

- **Onboarding self-service** (o funcionário vinculado — Fase 1.2 — executa checklists no próprio app).
- **Documentos**: assinatura/aceite, validade e alertas de vencimento (parte já existe).
- **Ausências/Férias**: solicitação e aprovação (workflow), saldo, calendário.
- **Avaliação de desempenho**: ciclos, metas, feedback 360 (novo).

**Esforço:** ~XL (vários submódulos — priorizar Ausências/Férias primeiro).

---

## 12. FASE 9 — Comunicação & automações

- **E-mails automáticos** de status (confirmação, avanço, reprovação) via Edge Function + provedor (Resend/SMTP) com `email_log`.
- **Templates** editáveis por org (white-label).
- **WhatsApp** (link/deep-link já viável; API oficial fica como evolução).
- **Automação de pipeline**: gatilhos "ao mover para etapa X → enviar e-mail/template Y".

**Esforço:** ~L.

---

## 13. Roadmap sugerido (ordem de valor × esforço)

| Onda | Conteúdo | Racional |
|------|----------|----------|
| **1** | **F1.1 Central + link de divulgação**, **F1.2 vínculo funcionário↔usuário** | Pedido explícito, alto valor, baixo risco, sem novas deps |
| **2** | Fase 4 (Catálogo) + Fase 2 (Vagas) | Catálogo destrava Vagas; Vagas dá foco ao portal |
| **3** | Fase 6 (Dashboard) | Visibilidade executiva rápida sobre dados que já existem |
| **4** | Fase 3 (Avaliação técnica + IA) | Maior diferencial; construir sobre Catálogo/Vagas |
| **5** | Fase 5 (Pipeline avançado) + Fase 9 (Automações) | Escala operacional |
| **6** | Fase 7 (Login candidato) + Fase 8 (Gestão de pessoas) | Consolidação da suíte |

---

## 14. Princípios inegociáveis (guardrails do projeto)

- **Multi-tenant sempre:** toda tabela nova nasce com `organization_id`, RLS `RESTRICTIVE` por org, DEFAULT via trigger e índice por org (padrão do retrofit já documentado).
- **Tokens de status:** nada de `Colors.X` para status — usar `AlinhaStatusTokens`/`StatusRole` (white-label).
- **Sem acesso anônimo direto:** tudo que é público passa por Edge Function (`rh-candidatura` e novas).
- **IA:** correção/geração server-side, saída validada, uso logado em `ia_usage_log`, teto por org.
- **Migrations aditivas:** nunca quebrar dados existentes; campos novos opcionais + seed de compatibilidade.
- **Registro de módulos:** cada nova área que vira item de menu/rota entra em `lib/core/modules` (fonte única de sidebar/rotas/FCM) + seed RBAC.
- **Encoding UTF-8** validado (evitar mojibake em telas e seeds).
- **Ícones no Web:** preferir variante base (codepoint `0xe___`).
- **Build:** não buildar localmente; produção exige `--release --dart-define-from-file=dart_defines.json`. Validação em `alinhajadev.web.app` antes de produção.

---

## 15. Métricas de sucesso

- ↑ inscrições via portal (link/QR/vagas) e ↑ conversão portal→contratado.
- ↓ tempo médio no pipeline (SLA por etapa).
- % de funcionários com **usuário do app vinculado** (habilita self-service).
- % de candidatos triados por **avaliação técnica** antes de entrevista.
- Adoção do dashboard por gestores (uso recorrente).

---

## 16. Estado de entrega (auditoria de 22/07/2026)

Auditoria do plano contra o código, seguida do fechamento das lacunas.

| Fase | Situação | Observação |
|------|----------|------------|
| F1.1 Central + Divulgação | ✅ | 6 abas, `careers_link_panel`, migration `rh7` |
| F1.2 Funcionário↔Usuário | ✅ | `rh8`: índice único parcial + 2 RPCs + view |
| 2 Vagas | ✅ | `rh10`, rota `/carreiras/:slug/vaga/:id`, share por vaga |
| 3 Avaliação + IA | ✅ | `rh12` + `rh23` (timer). Correção sempre server-side |
| 4 Catálogo | ✅ | `rh9` |
| 5 Pipeline avançado | ✅ | `rh13`/`rh14`: etapas por org, SLA, ações em massa |
| 6 Dashboard | ✅ | `rh11`/`rh15`, `fl_chart`, export CSV. **PDF não feito** (era opcional) |
| 7 Login candidato | ✅ | `rh16` + reuso de currículo entre candidaturas |
| 8 Gestão de pessoas | ✅ | `rh17`/`rh21` + `rh24`–`rh27` (ver abaixo) |
| 9 Automações | ✅ | `rh19`/`rh20`, BYO-SMTP, gatilho por etapa. WhatsApp só por deep-link |

### Fechamento da Fase 8

| Entrega | Migration | Telas |
|---------|-----------|-------|
| Aceite eletrônico de documentos | `rh24` | `/meus-documentos` (declarar ciência), `hr_documentos_screen` (exigir + recibo) |
| Onboarding self-service | `rh25` | `/meu-onboarding` |
| Saldo de férias + calendário | `rh26` | `hr_absences_screen` (3 abas), `/meus-afastamentos` |
| Desempenho: ciclos, metas, 360 | `rh27` | `hr_desempenho_screen` → Ciclos → detalhe; `/meu-desempenho` |

**Decisões que valem registro:**

- **Aprovar férias virou RPC.** `rh_decidir_ausencia` substitui o `UPDATE`
  direto: sem saldo no período aquisitivo, o servidor recusa. O app não
  decide mais isso sozinho.
- **Anonimato no 360.** O avaliado **não** tem `SELECT` em
  `rh_avaliacao_360`. Ele lê o próprio resultado por
  `rh_meu_resultado_360`, que devolve só médias — e esconde a média de
  pares enquanto não houver `min_pares_anonimato` respostas (k-anonimato
  configurável por ciclo). Com uma ou duas respostas, revelar a média
  entrega quem escreveu.
- **Progresso de onboarding virou trigger.** Antes era calculado só nas
  RPCs de RH; com o funcionário mexendo nos itens, `trg_onboarding_progresso`
  cobre as duas origens de escrita.

### Responsividade (mobile + web no mesmo binário)

As telas de RH aparecem em dois contextos de largura: tela cheia no mobile
e painel direito (ao lado da sidebar) no desktop. Convenções aplicadas:

- Medidas saem de `LayoutBuilder`/`constraints`, **não** de
  `MediaQuery.size` — no desktop o painel é bem mais estreito que a janela.
  A exceção é `showHrFormSheet`, onde a decisão é sobre a janela mesmo.
- `lib/features/hr/ui/widgets/hr_responsive.dart` concentra os primitivos:
  `HrContentColumn` (limita a largura de leitura), `HrFieldRow` (campos
  lado a lado que empilham), `showHrFormSheet` (bottom sheet no celular,
  diálogo centrado no desktop) e a extensão `HrBreakpoints`.
- Breakpoint único: `kDesktopBreakpoint` (800) de `core/ui/responsive_layout.dart`.
- `TabBar` sempre `isScrollable` — rótulos não se espremem em telas estreitas.
- Ações e etiquetas em `Wrap`, nunca `Row` fixa.
- O calendário de ausências troca de densidade: pontos coloridos no
  compacto, nomes por dia quando há largura.

**Armadilha registrada:** o app **não** inicializa o locale `pt_BR` do
`intl`, então `DateFormat(..., 'pt_BR')` estoura em runtime. Nomes de mês
e dia da semana são constantes no código (mesma decisão de
`hr_ponto_screen.dart`).

**Desvios menores de guardrail** que seguem abertos — `Colors.X` onde
caberia token de status: `automations_screen.dart` (ativo/inativo da regra)
e `candidate_detail_screen.dart` (status `erro` da extração de CV).

---

### Histórico
O plano começou pela **Onda 1** (F1.1 + F1.2) conforme previsto, e as ondas
seguintes seguiram a ordem da seção 13. As migrations `rh23`–`rh27` são o
fechamento das lacunas encontradas na auditoria de 22/07/2026.
