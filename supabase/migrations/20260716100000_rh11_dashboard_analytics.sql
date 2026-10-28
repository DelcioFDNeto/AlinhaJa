-- ============================================================
-- RH-11 / Fase 6 — Dashboard & Analytics de RH
-- (PLANO-RH-COMPLETO.md, Onda 3).
--
-- Views agregadas (mesmo padrão de candidato_contagem_status):
-- security_invoker → a RLS das tabelas-base filtra por org, sem
-- vazamento cross-tenant e sem policy nova. Só leitura; nada de
-- dados sensíveis (salário/PII fica de fora).
--
-- O funil (candidato_contagem_status) e o headcount
-- (funcionario_contagem_status) já existem e são reusados no app.
-- ============================================================

-- ── 1. Distribuição de candidatos por fonte ──────────────────
CREATE OR REPLACE VIEW public.rh_dash_candidato_fonte
WITH (security_invoker = true) AS
SELECT
  organization_id,
  COALESCE(NULLIF(trim(fonte::text), ''), 'outros') AS fonte,
  count(*) AS total
FROM public.candidato
WHERE deleted_at IS NULL
GROUP BY organization_id, COALESCE(NULLIF(trim(fonte::text), ''), 'outros');

-- ── 2. Distribuição de candidatos por nível ──────────────────
CREATE OR REPLACE VIEW public.rh_dash_candidato_nivel
WITH (security_invoker = true) AS
SELECT
  organization_id,
  COALESCE(NULLIF(trim(nivel::text), ''), 'nao_informado') AS nivel,
  count(*) AS total
FROM public.candidato
WHERE deleted_at IS NULL
GROUP BY organization_id, COALESCE(NULLIF(trim(nivel::text), ''), 'nao_informado');

-- ── 3. Movimentação de pessoal por mês (últimos 12 meses) ────
-- Admissões e desligamentos derivados de `vinculo`; base para
-- turnover e para o gráfico de contratações no período.
CREATE OR REPLACE VIEW public.rh_dash_movimentacao_mes
WITH (security_invoker = true) AS
SELECT
  organization_id,
  date_trunc('month', d)::date AS mes,
  count(*) FILTER (WHERE tipo = 'admissao')     AS admissoes,
  count(*) FILTER (WHERE tipo = 'desligamento') AS desligamentos
FROM (
  SELECT organization_id, data_admissao AS d, 'admissao' AS tipo
    FROM public.vinculo WHERE data_admissao IS NOT NULL
  UNION ALL
  SELECT organization_id, data_desligamento AS d, 'desligamento' AS tipo
    FROM public.vinculo WHERE data_desligamento IS NOT NULL
) mov
WHERE d >= (date_trunc('month', CURRENT_DATE) - interval '11 months')
GROUP BY organization_id, date_trunc('month', d);
