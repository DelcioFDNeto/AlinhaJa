-- ============================================================
-- Módulo RH-3 — IA de Currículo (escopo S055–S069)
-- Log de uso da IA + trigger que dispara a Edge Function
-- rh-extract-cv no insert de candidato_curriculo (via pg_net,
-- mesmo padrão do notify_workflow_function).
--
-- Provisionamento por ambiente (Vault):
--   SELECT vault.create_secret('https://<ref>.supabase.co', 'edge_base_url');
--   (dev: ffsspqscpdxlmxuaiytj / prod: gpeemngsxvqjflasdody)
-- Enquanto o secret não existir, o trigger não chama nada e o
-- candidato permanece com extracao = 'pendente' (fallback S064).
-- ============================================================

-- ── 1. Log de chamadas à IA (S067/S069 — auditoria e billing) ─
CREATE TABLE IF NOT EXISTS public.ia_usage_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES public.organizations(id),
  candidato_id    UUID REFERENCES public.candidato(id) ON DELETE SET NULL,
  funcao          TEXT NOT NULL,
  modelo          TEXT,
  tokens_input    INTEGER,
  tokens_output   INTEGER,
  -- USD estimado (Haiku 4.5: $1/M input, $5/M output)
  custo_estimado  NUMERIC(10, 6),
  sucesso         BOOLEAN NOT NULL DEFAULT false,
  erro            TEXT,
  duracao_ms      INTEGER,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ia_usage_org
  ON public.ia_usage_log(organization_id, created_at DESC);

-- Somente leitura para administradores do RH; escrita via service role
ALTER TABLE public.ia_usage_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "RH admin lê uso de IA da própria org" ON public.ia_usage_log;
CREATE POLICY "RH admin lê uso de IA da própria org"
  ON public.ia_usage_log FOR SELECT
  USING (public.fn_is_rh_admin() AND organization_id = public.fn_current_org());

-- ── 2. URL base das Edge Functions por ambiente ──────────────
CREATE OR REPLACE FUNCTION public.get_edge_base_url()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_url text;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets
    WHERE name = 'edge_base_url'
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_url := NULL;
  END;
  RETURN COALESCE(v_url, '');
END;
$$;
REVOKE ALL ON FUNCTION public.get_edge_base_url() FROM PUBLIC, anon, authenticated;

-- ── 3. Trigger: insert de currículo → rh-extract-cv (S055) ───
CREATE OR REPLACE FUNCTION public.notify_rh_extract_cv()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE
  v_base text := public.get_edge_base_url();
BEGIN
  IF v_base = '' THEN
    RAISE WARNING 'edge_base_url não configurada no Vault — extração de CV não disparada (candidato_curriculo %)', NEW.id;
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := v_base || '/functions/v1/rh-extract-cv',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.get_webhook_secret()
    ),
    body := jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'record', row_to_json(NEW)
    )
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_rh_extract_cv ON public.candidato_curriculo;
CREATE TRIGGER trg_rh_extract_cv
  AFTER INSERT ON public.candidato_curriculo
  FOR EACH ROW EXECUTE FUNCTION public.notify_rh_extract_cv();
