-- ============================================================
-- RH-7 / F1.1 — Central de Recrutamento: divulgação do portal
-- (PLANO-RH-COMPLETO.md, Onda 1).
--
-- Aditiva: 3 colunas novas em organizations para o RH controlar a
-- página pública /carreiras/:slug sem código (toggle + mini-landing),
-- 1 RPC de escrita (rh_admin) e 1 view de métricas de divulgação.
-- A leitura pública dessas colunas continua passando SOMENTE pela
-- Edge Function rh-candidatura (nenhuma policy anon).
-- ============================================================

-- ── 1. Configuração da página de carreiras ───────────────────
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS carreiras_ativo BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS carreiras_headline TEXT,
  ADD COLUMN IF NOT EXISTS carreiras_sobre TEXT;

COMMENT ON COLUMN public.organizations.carreiras_ativo IS
  'Página pública /carreiras/:slug aceita novas candidaturas?';
COMMENT ON COLUMN public.organizations.carreiras_headline IS
  'Chamada curta exibida no topo da página de carreiras (white-label).';
COMMENT ON COLUMN public.organizations.carreiras_sobre IS
  'Texto "sobre a empresa" da página de carreiras (white-label).';

-- ── 2. RPC: RH admin edita a divulgação da própria org ───────
-- NULL em um parâmetro = mantém o valor atual; string vazia limpa
-- o texto. Assim o toggle liga/desliga sem reenviar os textos.
CREATE OR REPLACE FUNCTION public.rh_set_carreiras_config(
  p_ativo boolean DEFAULT NULL,
  p_headline text DEFAULT NULL,
  p_sobre text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_is_rh_admin() THEN
    RAISE EXCEPTION 'Apenas administradores do RH podem alterar a divulgação';
  END IF;

  UPDATE public.organizations SET
    carreiras_ativo    = COALESCE(p_ativo, carreiras_ativo),
    carreiras_headline = CASE WHEN p_headline IS NULL THEN carreiras_headline
                              ELSE NULLIF(trim(p_headline), '') END,
    carreiras_sobre    = CASE WHEN p_sobre IS NULL THEN carreiras_sobre
                              ELSE NULLIF(trim(p_sobre), '') END,
    updated_at = NOW()
  WHERE id = v_org;

  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_org, auth.uid(), 'editou_carreiras_config',
          jsonb_build_object('ativo', p_ativo,
                             'headline_alterada', p_headline IS NOT NULL,
                             'sobre_alterado', p_sobre IS NOT NULL));
END;
$$;
REVOKE ALL ON FUNCTION public.rh_set_carreiras_config(boolean, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_set_carreiras_config(boolean, text, text) TO authenticated;

-- ── 3. Métricas de divulgação (painel da Central) ────────────
-- Mesmo padrão de candidato_contagem_status: view agregada com
-- security_invoker (a RLS de candidato filtra por org).
CREATE OR REPLACE VIEW public.rh_metricas_divulgacao
WITH (security_invoker = true) AS
SELECT
  organization_id,
  count(*) FILTER (WHERE fonte = 'portal') AS portal_total,
  count(*) FILTER (WHERE fonte = 'portal'
                     AND created_at >= NOW() - interval '30 days') AS portal_30d,
  count(*) FILTER (WHERE fonte = 'portal'
                     AND status NOT IN ('novo', 'descartado')) AS portal_em_processo,
  count(*) FILTER (WHERE fonte = 'portal'
                     AND status = 'contratado') AS portal_contratados
FROM public.candidato
WHERE deleted_at IS NULL
GROUP BY organization_id;
