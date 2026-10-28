-- ============================================================
-- Módulo RH-3 — Reprocessamento Manual de Currículo
-- Adiciona um RPC para reenfileirar a extração via Edge Function.
-- ============================================================

CREATE OR REPLACE FUNCTION public.retry_cv_extraction(p_curriculo_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_base text := public.get_edge_base_url();
  v_curriculo record;
BEGIN
  -- Segurança: garantir que só RH da mesma org possa rodar
  IF NOT public.fn_is_rh_admin() THEN
    RAISE EXCEPTION 'Acesso negado: apenas administradores de RH podem reprocessar currículos.';
  END IF;

  SELECT * INTO v_curriculo FROM public.candidato_curriculo WHERE id = p_curriculo_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Currículo não encontrado';
  END IF;

  -- Resetar status no candidato para dar feedback visual imediato
  UPDATE public.candidato 
  SET extracao = 'processando' 
  WHERE id = v_curriculo.candidato_id AND organization_id = public.fn_current_org();

  IF v_base = '' THEN
    RAISE WARNING 'edge_base_url não configurada no Vault';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_base || '/functions/v1/rh-extract-cv',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.get_webhook_secret()
    ),
    body := jsonb_build_object(
      'type', 'MANUAL_RETRY',
      'table', 'candidato_curriculo',
      'record', row_to_json(v_curriculo),
      'attempt', 1
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.retry_cv_extraction(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.retry_cv_extraction(UUID) TO authenticated;
