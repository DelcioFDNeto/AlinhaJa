-- ============================================================================
-- Migration 021: Sistema de Rastreamento de Localização
-- ============================================================================
-- Tabela para armazenar localizações dos colaboradores.
-- Acesso restrito: apenas super_admin e admin visualizam dados.
-- Retenção: 7 dias, limpeza automática via cron ou edge function.
-- ============================================================================

-- ── 1. Tabela de localizações ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  accuracy DOUBLE PRECISION,
  altitude DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  device_info JSONB,
  battery_level SMALLINT,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 2. Índices para performance ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_user_locations_user_time
  ON public.user_locations(user_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_locations_recorded_at
  ON public.user_locations(recorded_at DESC);

-- ── 3. RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE public.user_locations ENABLE ROW LEVEL SECURITY;

-- Admin (TI) pode visualizar todas as localizações
CREATE POLICY "admin_select_all_locations" ON public.user_locations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role_level IN ('super_admin', 'admin')
    )
  );

-- Usuário pode inserir apenas suas próprias localizações
CREATE POLICY "user_insert_own_location" ON public.user_locations
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- Admin pode deletar (limpeza de dados)
CREATE POLICY "admin_delete_locations" ON public.user_locations
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role_level IN ('super_admin', 'admin')
    )
  );

-- ── 4. Tabela de configurações de rastreamento ──────────────────────────────
-- Controla se o rastreamento está ativado e a frequência para cada usuário.
CREATE TABLE IF NOT EXISTS public.location_tracking_settings (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  interval_minutes SMALLINT NOT NULL DEFAULT 5,
  enabled_by UUID REFERENCES public.users(id),
  enabled_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.location_tracking_settings ENABLE ROW LEVEL SECURITY;

-- Qualquer usuário pode ler suas próprias configurações
CREATE POLICY "user_read_own_tracking_settings" ON public.location_tracking_settings
  FOR SELECT USING (user_id = auth.uid());

-- Admin pode ler todas as configurações
CREATE POLICY "admin_read_all_tracking_settings" ON public.location_tracking_settings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role_level IN ('super_admin', 'admin')
    )
  );

-- Admin pode inserir/atualizar configurações
CREATE POLICY "admin_upsert_tracking_settings" ON public.location_tracking_settings
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role_level IN ('super_admin', 'admin')
    )
  );

CREATE POLICY "admin_update_tracking_settings" ON public.location_tracking_settings
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role_level IN ('super_admin', 'admin')
    )
  );

-- ── 5. Função de limpeza automática (retenção de 7 dias) ────────────────────
CREATE OR REPLACE FUNCTION public.cleanup_old_locations()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM public.user_locations
  WHERE recorded_at < NOW() - INTERVAL '7 days';
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

-- ── 6. RPC para buscar última localização de todos os usuários rastreados ───
CREATE OR REPLACE FUNCTION public.get_latest_user_locations()
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  avatar_url TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  accuracy DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  battery_level SMALLINT,
  recorded_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Verificar se o caller é admin
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid()
    AND role_level IN ('super_admin', 'admin')
  ) THEN
    RAISE EXCEPTION 'Acesso negado: apenas administradores podem visualizar localizações.';
  END IF;

  RETURN QUERY
  SELECT DISTINCT ON (ul.user_id)
    ul.user_id,
    u.full_name,
    u.avatar_url,
    ul.latitude,
    ul.longitude,
    ul.accuracy,
    ul.speed,
    ul.battery_level,
    ul.recorded_at
  FROM public.user_locations ul
  INNER JOIN public.users u ON u.id = ul.user_id
  WHERE ul.recorded_at > NOW() - INTERVAL '1 hour'
  ORDER BY ul.user_id, ul.recorded_at DESC;
END;
$$;

-- ── 7. Habilitar realtime na tabela de localizações ─────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_locations;
