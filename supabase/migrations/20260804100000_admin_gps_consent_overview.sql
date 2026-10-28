-- ============================================================
-- Visão admin do consentimento GPS
--
-- O dashboard de rastreamento só mostra quem tem pontos
-- coletados na última hora. Quem ainda não consentiu
-- simplesmente desaparece — sem nenhum sinal para o admin.
--
-- Esta RPC devolve todos os usuários que têm registro em
-- location_tracking_settings, com o estado atual do
-- consentimento, para que o admin saiba quem está
-- "aguardando consentimento", quem consentiu e quem revogou.
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_gps_consent_overview()
RETURNS TABLE (
  user_id        uuid,
  full_name      text,
  avatar_url     text,
  is_enabled     boolean,
  consent_active boolean,
  consent_given_at   timestamptz,
  consent_revoked_at timestamptz,
  consent_version    text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Verificar se o caller é admin da mesma org
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid()
    AND role_level IN ('super_admin', 'admin')
  ) THEN
    RAISE EXCEPTION 'Acesso restrito a administradores';
  END IF;

  RETURN QUERY
  SELECT
    s.user_id,
    u.full_name,
    u.avatar_url,
    COALESCE(s.is_enabled, false),
    public.fn_gps_consent_active(s.user_id),
    s.consent_given_at,
    s.consent_revoked_at,
    s.consent_version
  FROM public.location_tracking_settings s
  INNER JOIN public.users u ON u.id = s.user_id
  -- Multi-tenant: fn_current_org() honra a "empresa em atuação" do dono da
  -- plataforma (20260728100000); a org natal listaria a empresa errada.
  WHERE u.organization_id = public.fn_current_org()
  ORDER BY
    -- Sem consentimento primeiro (ação necessária)
    public.fn_gps_consent_active(s.user_id) ASC,
    u.full_name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_gps_consent_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_gps_consent_overview() TO authenticated;
