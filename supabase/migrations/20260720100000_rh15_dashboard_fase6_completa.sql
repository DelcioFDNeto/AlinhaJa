-- ============================================================
-- RH-15 / Fase 6 (complemento) — Dashboard & Analytics de RH
-- (PLANO-RH-COMPLETO.md, seção 9). Fecha o que faltava da fase:
--   • distribuição de candidatos por ÁREA (catálogo RH-9 + texto livre)
--   • tempo médio no pipeline + contratações no período
--   • tempo de casa e aniversariantes (nascimento e de empresa)
-- Headcount por status (funcionario_contagem_status), funil
-- (candidato_contagem_status) e movimentação mensal
-- (rh_dash_movimentacao_mes) já existem e são reusados; o turnover
-- é derivado no app (desligamentos 12m ÷ headcount ativo).
--
-- Padrão das views: security_invoker → a RLS das tabelas-base
-- filtra por org (candidato/vinculo exigem papel RH; rh_area é
-- lida pela org). Migration 100% aditiva.
-- ============================================================

-- ── 1. Distribuição de candidatos por área ───────────────────
-- Preferência ao catálogo (area_id → rh_area.nome); candidatos
-- antigos sem FK caem no texto livre normalizado.
CREATE OR REPLACE VIEW public.rh_dash_candidato_area
WITH (security_invoker = true) AS
SELECT
  c.organization_id,
  COALESCE(a.nome, NULLIF(trim(c.area_interesse), ''), 'Não informado') AS area,
  count(*) AS total
FROM public.candidato c
LEFT JOIN public.rh_area a ON a.id = c.area_id
WHERE c.deleted_at IS NULL
GROUP BY c.organization_id,
         COALESCE(a.nome, NULLIF(trim(c.area_interesse), ''), 'Não informado');

-- ── 2. Tempo médio no pipeline + contratações no período ─────
-- O tipo da etapa vem de pipeline_etapa (funil customizável RH-14);
-- orgs sem etapas caem no mapa fixo original. `status_changed_at`
-- carimba a última transição (RH-13) — para contratados, é a data
-- da contratação.
CREATE OR REPLACE VIEW public.rh_dash_tempo_pipeline
WITH (security_invoker = true) AS
SELECT
  organization_id,
  round(avg(extract(epoch FROM (status_changed_at - created_at)) / 86400.0)
    FILTER (WHERE tipo = 'contratado'))::int   AS dias_ate_contratacao,
  round(avg(extract(epoch FROM (NOW() - created_at)) / 86400.0)
    FILTER (WHERE tipo NOT IN ('contratado', 'descartado')))::int
                                               AS dias_em_processo,
  count(*) FILTER (WHERE tipo = 'contratado'
    AND status_changed_at >= NOW() - interval '30 days')  AS contratacoes_30d,
  count(*) FILTER (WHERE tipo = 'contratado'
    AND status_changed_at >= NOW() - interval '90 days')  AS contratacoes_90d
FROM (
  SELECT
    c.organization_id, c.created_at, c.status_changed_at,
    COALESCE(e.tipo, CASE c.status
      WHEN 'contratado' THEN 'contratado'
      WHEN 'descartado' THEN 'descartado'
      ELSE 'normal' END) AS tipo
  FROM public.candidato c
  LEFT JOIN public.pipeline_etapa e
    ON e.organization_id = c.organization_id AND e.slug = c.status
  WHERE c.deleted_at IS NULL
) x
GROUP BY organization_id;

-- ── 3. Tempo de casa (média) ─────────────────────────────────
-- Vínculo mais recente de cada funcionário não desligado.
-- vinculo tem RLS só-RH → a view (invoker) só retorna para o RH.
CREATE OR REPLACE VIEW public.rh_dash_tempo_casa
WITH (security_invoker = true) AS
SELECT
  f.organization_id,
  count(*)                                              AS com_vinculo,
  round(avg(CURRENT_DATE - v.data_admissao) / 30.44)::int AS media_meses
FROM public.funcionario f
JOIN LATERAL (
  SELECT vv.data_admissao, vv.data_desligamento
  FROM public.vinculo vv
  WHERE vv.funcionario_id = f.id
  ORDER BY vv.created_at DESC LIMIT 1
) v ON true
WHERE f.deleted_at IS NULL
  AND f.status <> 'desligado'
  AND v.data_desligamento IS NULL
GROUP BY f.organization_id;

-- ── 4. Aniversários de empresa do mês corrente ───────────────
CREATE OR REPLACE VIEW public.rh_dash_aniversariantes_casa
WITH (security_invoker = true) AS
SELECT
  f.organization_id,
  f.id       AS funcionario_id,
  f.nome,
  f.foto_url,
  extract(day FROM v.data_admissao)::smallint AS dia,
  (extract(year FROM CURRENT_DATE)
     - extract(year FROM v.data_admissao))::int AS anos
FROM public.funcionario f
JOIN LATERAL (
  SELECT vv.data_admissao, vv.data_desligamento
  FROM public.vinculo vv
  WHERE vv.funcionario_id = f.id
  ORDER BY vv.created_at DESC LIMIT 1
) v ON true
WHERE f.deleted_at IS NULL
  AND f.status <> 'desligado'
  AND v.data_desligamento IS NULL
  AND extract(month FROM v.data_admissao) = extract(month FROM CURRENT_DATE)
  AND v.data_admissao < date_trunc('month', CURRENT_DATE);

-- ── 5. Aniversariantes (nascimento) do mês ───────────────────
-- data_nascimento mora em funcionario_dados_sensiveis (sem acesso
-- direto — S074), então sai por RPC definer restrita ao RH.
-- Exposição mínima: apenas o DIA do mês, sem ano/idade — por isso
-- não gera linha em rh_access_log (logar cada load do dashboard
-- poluiria a auditoria LGPD sem revelar dado sensível novo).
CREATE OR REPLACE FUNCTION public.rh_dash_aniversariantes(p_mes int DEFAULT NULL)
RETURNS TABLE (funcionario_id uuid, nome text, foto_url text, dia smallint)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_mes int  := COALESCE(p_mes, extract(month FROM CURRENT_DATE)::int);
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;
  IF v_mes NOT BETWEEN 1 AND 12 THEN
    RAISE EXCEPTION 'Mês inválido: %', v_mes;
  END IF;

  RETURN QUERY
  SELECT f.id, f.nome, f.foto_url,
         extract(day FROM ds.data_nascimento)::smallint
  FROM public.funcionario f
  JOIN public.funcionario_dados_sensiveis ds ON ds.funcionario_id = f.id
  WHERE f.organization_id = v_org
    AND f.deleted_at IS NULL
    AND f.status <> 'desligado'
    AND ds.data_nascimento IS NOT NULL
    AND extract(month FROM ds.data_nascimento)::int = v_mes
  ORDER BY 4, 2;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_dash_aniversariantes(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_dash_aniversariantes(int) TO authenticated;
