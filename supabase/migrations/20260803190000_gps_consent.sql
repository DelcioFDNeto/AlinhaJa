-- ============================================================
-- Rastreamento GPS passa a exigir consentimento do titular
--                                              (achado LGPD 2.2)
--
-- PROBLEMA
-- `location_tracking_settings.enabled_by` diz tudo: quem liga o
-- rastreamento é o ADMIN. Não havia campo de consentimento, aviso ao
-- funcionário nem registro de base legal. E a RLS de `user_locations`
-- só dava SELECT ao admin — o próprio rastreado não conseguia ver o
-- que era coletado sobre ele.
--
-- Rastrear empregado exige transparência (Art. 6º, VI) e o titular tem
-- direito de acesso (Art. 18, II). Além da LGPD há exposição
-- trabalhista independente.
--
-- O QUE MUDA
--   1. Consentimento explícito, versionado, dado pelo PRÓPRIO titular —
--      admin não consegue consentir por ele.
--   2. Coleta bloqueada no banco sem consentimento ativo: não depende
--      de o cliente se comportar.
--   3. O titular passa a ler e a apagar o próprio histórico.
--   4. Revogação a qualquer momento, que desliga o rastreamento.
-- ============================================================

-- ── 1. Campos de consentimento ───────────────────────────────
ALTER TABLE public.location_tracking_settings
  ADD COLUMN IF NOT EXISTS consent_given_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS consent_revoked_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS consent_version     TEXT,
  ADD COLUMN IF NOT EXISTS finalidade          TEXT;

COMMENT ON COLUMN public.location_tracking_settings.consent_given_at IS
  'Quando o TITULAR consentiu. Nulo = sem consentimento; a coleta é bloqueada.';
COMMENT ON COLUMN public.location_tracking_settings.finalidade IS
  'Base legal / finalidade declarada ao titular no momento do aceite.';

-- Consentimento ativo = concedido e não revogado depois.
CREATE OR REPLACE FUNCTION public.fn_gps_consent_active(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (SELECT s.consent_given_at IS NOT NULL
        AND (s.consent_revoked_at IS NULL
             OR s.consent_revoked_at < s.consent_given_at)
       FROM public.location_tracking_settings s
      WHERE s.user_id = p_user_id),
    false);
$$;
REVOKE ALL ON FUNCTION public.fn_gps_consent_active(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_gps_consent_active(uuid) TO authenticated;

-- ── 2. Coleta bloqueada sem consentimento ────────────────────
-- Trigger e não apenas policy: vale para qualquer caminho de escrita,
-- inclusive service_role e importações.
CREATE OR REPLACE FUNCTION public.fn_guard_location_consent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.fn_gps_consent_active(NEW.user_id) THEN
    RAISE EXCEPTION
      'Coleta de localização sem consentimento ativo do titular (LGPD Art. 6º)';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_location_consent ON public.user_locations;
CREATE TRIGGER trg_guard_location_consent
  BEFORE INSERT ON public.user_locations
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_location_consent();

-- ── 3. Consentir / revogar (só o titular) ────────────────────
CREATE OR REPLACE FUNCTION public.gps_grant_consent(
  p_version    text DEFAULT 'v1',
  p_finalidade text DEFAULT 'Acompanhamento de equipe em atividade externa durante a jornada de trabalho'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida';
  END IF;

  INSERT INTO public.location_tracking_settings
    (user_id, is_enabled, consent_given_at, consent_revoked_at,
     consent_version, finalidade)
  VALUES (auth.uid(), false, NOW(), NULL, p_version, p_finalidade)
  ON CONFLICT (user_id) DO UPDATE SET
    consent_given_at   = NOW(),
    consent_revoked_at = NULL,
    consent_version    = EXCLUDED.consent_version,
    finalidade         = EXCLUDED.finalidade,
    updated_at         = NOW();

  PERFORM public.fn_audit('gps.consent_granted', 'user', auth.uid()::text,
    jsonb_build_object('versao', p_version, 'finalidade', p_finalidade));
END;
$$;
REVOKE ALL ON FUNCTION public.gps_grant_consent(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gps_grant_consent(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.gps_revoke_consent()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida';
  END IF;

  -- Revogar desliga o rastreamento no mesmo ato: manter is_enabled
  -- ligado sem consentimento só produziria erro a cada coleta.
  UPDATE public.location_tracking_settings
     SET consent_revoked_at = NOW(),
         is_enabled         = false,
         updated_at         = NOW()
   WHERE user_id = auth.uid();

  PERFORM public.fn_audit('gps.consent_revoked', 'user', auth.uid()::text, '{}');
END;
$$;
REVOKE ALL ON FUNCTION public.gps_revoke_consent() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gps_revoke_consent() TO authenticated;

-- ── 4. Direito de acesso e eliminação do titular ─────────────
-- Antes só o admin lia user_locations; o rastreado não via o próprio
-- rastro (Art. 18, II) nem podia apagá-lo.
DROP POLICY IF EXISTS "user_read_own_locations" ON public.user_locations;
CREATE POLICY "user_read_own_locations"
  ON public.user_locations FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "user_delete_own_locations" ON public.user_locations;
CREATE POLICY "user_delete_own_locations"
  ON public.user_locations FOR DELETE
  USING (user_id = auth.uid());

-- ── 5. Estado do consentimento para a UI ─────────────────────
CREATE OR REPLACE FUNCTION public.gps_my_consent_status()
RETURNS TABLE (
  consent_active     boolean,
  consent_given_at   timestamptz,
  consent_revoked_at timestamptz,
  consent_version    text,
  finalidade         text,
  is_enabled         boolean,
  pontos_coletados   bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    public.fn_gps_consent_active(auth.uid()),
    s.consent_given_at,
    s.consent_revoked_at,
    s.consent_version,
    s.finalidade,
    COALESCE(s.is_enabled, false),
    (SELECT COUNT(*) FROM public.user_locations l WHERE l.user_id = auth.uid())
  FROM public.location_tracking_settings s
  WHERE s.user_id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.gps_my_consent_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gps_my_consent_status() TO authenticated;
