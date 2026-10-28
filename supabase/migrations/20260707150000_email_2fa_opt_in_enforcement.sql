-- ============================================================
-- 2FA por E-mail — Opt-in + Enforcement no banco (RLS)
-- ============================================================
--
-- Antes: o 2FA por e-mail era aplicado a todos os usuários apenas no
-- client (navegação), sem barreira real no banco.
--
-- Agora:
--   1. O usuário ATIVA o 2FA por e-mail (users.email_2fa_enabled).
--   2. Com o 2FA ativo, uma policy RESTRITIVA barra a sessão no banco
--      até que ela cumpra o segundo fator. A sessão é considerada
--      verificada quando existe uma linha em user_2fa_sessions com o
--      `session_id` do JWT — inserida via RPC somente quando o
--      dispositivo é confiável (código validado ou confiança vigente).
--   3. Sessões em aal2 (TOTP nativo) passam automaticamente pelo gate.
--
-- Anti-lockout: ao ativar, o dispositivo atual vira confiável e a
-- sessão atual é registrada como verificada.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Flag de ativação por usuário
-- ------------------------------------------------------------
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS email_2fa_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- ------------------------------------------------------------
-- 2. Sessões que cumpriram o 2FA por e-mail
--    (session_id vem do claim `session_id` do JWT do Supabase)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_2fa_sessions (
  session_id  UUID        PRIMARY KEY,
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  verified_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_2fa_sessions_user
  ON public.user_2fa_sessions(user_id);

ALTER TABLE public.user_2fa_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own 2fa sessions" ON public.user_2fa_sessions;
CREATE POLICY "Users can view own 2fa sessions"
  ON public.user_2fa_sessions FOR SELECT
  USING (auth.uid() = user_id);
-- Inserções apenas via RPC SECURITY DEFINER.

-- ------------------------------------------------------------
-- 3. Helper: gate do 2FA por e-mail
--    Passa quando: 2FA por e-mail desativado, OU sessão em aal2
--    (TOTP cumprido), OU sessão registrada como verificada.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.email_2fa_gate_passed()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    NOT COALESCE(
      (SELECT email_2fa_enabled FROM public.users WHERE id = auth.uid()),
      FALSE
    )
    OR (SELECT auth.jwt()->>'aal') = 'aal2'
    OR EXISTS (
      SELECT 1 FROM public.user_2fa_sessions s
      WHERE s.user_id = auth.uid()
        AND s.session_id = NULLIF(auth.jwt()->>'session_id', '')::uuid
    );
$$;

GRANT EXECUTE ON FUNCTION public.email_2fa_gate_passed() TO authenticated;

-- ------------------------------------------------------------
-- 4. RPC: register_2fa_session
--    Marca a sessão atual como verificada, SOMENTE se o dispositivo
--    informado for confiável (código validado agora ou nos últimos
--    30 dias — validação server-side via check_device_trusted).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_2fa_session(p_device_fingerprint TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    UUID;
  v_session_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_session_id := NULLIF(auth.jwt()->>'session_id', '')::uuid;
  IF v_session_id IS NULL THEN
    RETURN FALSE;
  END IF;

  IF NOT public.check_device_trusted(p_device_fingerprint) THEN
    RETURN FALSE;
  END IF;

  INSERT INTO public.user_2fa_sessions (session_id, user_id, verified_at)
  VALUES (v_session_id, v_user_id, NOW())
  ON CONFLICT (session_id) DO UPDATE SET verified_at = NOW();

  -- Limpeza oportunista de sessões antigas (sessões do GoTrue não
  -- vivem mais que o refresh-token; 35 dias é margem segura).
  DELETE FROM public.user_2fa_sessions
  WHERE verified_at < NOW() - INTERVAL '35 days';

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_2fa_session TO authenticated;

-- ------------------------------------------------------------
-- 5. RPC: set_email_2fa_enabled
--    Ativa/desativa o 2FA por e-mail do próprio usuário.
--    Ao ativar: registra o dispositivo atual como confiável e a
--    sessão atual como verificada (anti-lockout).
--    Ao desativar: exige que a sessão atual tenha cumprido o gate.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_email_2fa_enabled(
  p_enabled            BOOLEAN,
  p_device_fingerprint TEXT DEFAULT NULL,
  p_device_name        TEXT DEFAULT 'Dispositivo Desconhecido'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    UUID;
  v_session_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_enabled THEN
    UPDATE public.users SET email_2fa_enabled = TRUE WHERE id = v_user_id;

    -- Anti-lockout: confia no dispositivo e na sessão atuais.
    IF p_device_fingerprint IS NOT NULL THEN
      INSERT INTO public.user_trusted_devices
        (user_id, device_fingerprint, device_name, verified_at, expires_at)
      VALUES
        (v_user_id, p_device_fingerprint, p_device_name, NOW(), NOW() + INTERVAL '30 days')
      ON CONFLICT ON CONSTRAINT uq_user_device
      DO UPDATE SET
        device_name = EXCLUDED.device_name,
        verified_at = NOW(),
        expires_at  = NOW() + INTERVAL '30 days';

      v_session_id := NULLIF(auth.jwt()->>'session_id', '')::uuid;
      IF v_session_id IS NOT NULL THEN
        INSERT INTO public.user_2fa_sessions (session_id, user_id, verified_at)
        VALUES (v_session_id, v_user_id, NOW())
        ON CONFLICT (session_id) DO UPDATE SET verified_at = NOW();
      END IF;
    END IF;
  ELSE
    -- Só permite desativar a partir de uma sessão que cumpriu o 2FA.
    IF NOT public.email_2fa_gate_passed() THEN
      RAISE EXCEPTION '2FA verification required to disable email 2FA';
    END IF;
    UPDATE public.users SET email_2fa_enabled = FALSE WHERE id = v_user_id;
  END IF;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_email_2fa_enabled TO authenticated;

-- ------------------------------------------------------------
-- 6. Policy RESTRITIVA "require_email_2fa" nas tabelas de conteúdo.
--    Mesma lista/estratégia do gate aal2 do TOTP. Tabelas do fluxo de
--    autenticação (users, user_fcm_tokens, user_trusted_devices,
--    user_email_otp) ficam de fora — o app precisa delas ANTES de
--    completar o segundo fator.
-- ------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
  target_tables TEXT[] := ARRAY[
    'messages',
    'channel_messages',
    'chats',
    'chat_members',
    'channels',
    'channel_members',
    'workflow_cards',
    'workflow_card_comments',
    'workflow_card_history',
    'support_tickets',
    'support_ticket_messages',
    'user_locations',
    'user_activity_history',
    'starred_messages',
    'calls',
    'meetings',
    'message_actions'
  ];
BEGIN
  FOREACH t IN ARRAY target_tables LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE NOTICE 'Tabela public.% inexistente — pulando gate email_2fa.', t;
      CONTINUE;
    END IF;

    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('DROP POLICY IF EXISTS "require_email_2fa" ON public.%I;', t);
    EXECUTE format($f$
      CREATE POLICY "require_email_2fa" ON public.%I
        AS RESTRICTIVE
        FOR ALL
        TO authenticated
        USING (public.email_2fa_gate_passed())
        WITH CHECK (public.email_2fa_gate_passed());
    $f$, t);

    RAISE NOTICE 'Gate email_2fa aplicado em public.%', t;
  END LOOP;
END $$;

-- ============================================================
-- Reversão (manual, se necessário):
--   DROP POLICY "require_email_2fa" em cada tabela;
--   DROP FUNCTION set_email_2fa_enabled, register_2fa_session,
--        email_2fa_gate_passed;
--   DROP TABLE user_2fa_sessions;
--   ALTER TABLE users DROP COLUMN email_2fa_enabled;
-- ============================================================
