-- ============================================================
-- Retenção de geolocalização que realmente executa (achado LGPD 2.1)
--
-- PROBLEMA
-- A 021_create_user_locations_schema.sql criou cleanup_old_locations()
-- com retenção declarada de 7 dias, mas nunca a agendou. O único
-- chamador é o app (location_repository.cleanupOldLocations), acionado
-- manualmente na tela de admin. Na prática o histórico de GPS dos
-- funcionários — o dado mais sensível do sistema — acumula indefinidamente
-- enquanto a documentação afirma reter 7 dias.
--
-- Ter uma política declarada e não cumprida é agravante em fiscalização
-- (LGPD Art. 15/16): não é omissão, é descumprimento da própria regra.
--
-- CORREÇÃO
--   1. Retenção configurável por organização (default: os mesmos 7 dias),
--      seguindo o padrão já usado em fn_org_retencao_meses para candidatos.
--   2. pg_cron diário às 03:20 executando a limpeza de verdade.
--   3. A função passa a respeitar a configuração por org e a registrar
--      quanto apagou, para servir de evidência de cumprimento.
-- ============================================================

-- ── 1. Retenção configurável por org ─────────────────────────
-- Guardada em organizations.settings->>'gps_retencao_dias'.
CREATE OR REPLACE FUNCTION public.fn_org_gps_retencao_dias(p_org uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    NULLIF(settings->>'gps_retencao_dias', '')::int,
    7
  )
  FROM public.organizations WHERE id = p_org;
$$;
REVOKE ALL ON FUNCTION public.fn_org_gps_retencao_dias(uuid) FROM PUBLIC, anon;

-- RPC para o admin da própria org ajustar a política.
CREATE OR REPLACE FUNCTION public.set_retencao_gps(p_dias int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
BEGIN
  -- Multi-tenant: o papel vem da linha do usuário, mas a org-alvo vem de
  -- fn_current_org() — senão o dono da plataforma em "empresa em atuação"
  -- alteraria a retenção da própria org natal em vez da empresa visitada.
  IF NOT EXISTS (
    SELECT 1 FROM public.users
     WHERE id = auth.uid()
       AND role_level IN ('super_admin', 'admin')
       AND is_active
  ) THEN
    RAISE EXCEPTION 'Apenas administradores podem alterar a retenção de localização';
  END IF;

  v_org := public.fn_current_org();

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Organização do usuário não resolvida';
  END IF;

  -- Teto de 180 dias: rastreamento de empregado é dado sensível e reter
  -- mais que isso dificilmente encontra base legal proporcional.
  IF p_dias < 1 OR p_dias > 180 THEN
    RAISE EXCEPTION 'Período inválido (use de 1 a 180 dias)';
  END IF;

  UPDATE public.organizations
     SET settings = jsonb_set(COALESCE(settings, '{}'),
                              '{gps_retencao_dias}', to_jsonb(p_dias)),
         updated_at = NOW()
   WHERE id = v_org;
END;
$$;
REVOKE ALL ON FUNCTION public.set_retencao_gps(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_retencao_gps(int) TO authenticated;

-- ── 2. Limpeza respeitando a retenção de cada org ────────────
-- Substitui a versão de janela fixa de 7 dias. Mantém o mesmo nome e o
-- mesmo retorno (INTEGER) para não quebrar a chamada manual existente em
-- location_repository.cleanupOldLocations().
CREATE OR REPLACE FUNCTION public.cleanup_old_locations()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org           record;
  v_deleted       INTEGER := 0;
  v_total         INTEGER := 0;
BEGIN
  FOR v_org IN SELECT id FROM public.organizations LOOP
    DELETE FROM public.user_locations ul
     WHERE ul.recorded_at < NOW()
           - (public.fn_org_gps_retencao_dias(v_org.id) || ' days')::interval
       AND EXISTS (
         SELECT 1 FROM public.users u
          WHERE u.id = ul.user_id
            AND u.organization_id = v_org.id
       );
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    v_total := v_total + v_deleted;
  END LOOP;

  -- Rede de segurança: registros órfãos (usuário removido) não podem
  -- escapar da retenção por não casarem com nenhuma org.
  DELETE FROM public.user_locations ul
   WHERE ul.recorded_at < NOW() - INTERVAL '7 days'
     AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = ul.user_id);
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_total := v_total + v_deleted;

  RETURN v_total;
END;
$$;

REVOKE ALL ON FUNCTION public.cleanup_old_locations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cleanup_old_locations() TO authenticated;

COMMENT ON FUNCTION public.cleanup_old_locations() IS
  'Aplica a retenção de user_locations por organização (organizations.settings.gps_retencao_dias, default 7). Agendada em pg_cron como gps-retencao-diaria.';

-- ── 3. Agendamento diário (03:20) ────────────────────────────
-- Mesmo bloco tolerante usado nas rotinas de RH: se pg_cron não estiver
-- habilitado, avisa em vez de derrubar a migration.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('gps-retencao-diaria')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'gps-retencao-diaria');
    PERFORM cron.schedule('gps-retencao-diaria', '20 3 * * *',
      $cron$ SELECT public.cleanup_old_locations(); $cron$);
  ELSE
    RAISE WARNING 'pg_cron não habilitado: a retenção de GPS NÃO será aplicada automaticamente.';
    RAISE WARNING 'Habilite a extensão no dashboard e reexecute esta migration.';
  END IF;
END $$;
