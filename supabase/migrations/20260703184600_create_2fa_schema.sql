-- ============================================================
-- 2FA por E-mail — Schema, RPCs e Políticas de Segurança
-- ============================================================

-- Garantir que pgcrypto esteja habilitado (necessário para digest/sha256)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- 1. Tabela: user_trusted_devices
--    Armazena dispositivos confiáveis com validade de 30 dias
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_trusted_devices (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_fingerprint TEXT      NOT NULL,
  device_name      TEXT        NOT NULL DEFAULT 'Dispositivo Desconhecido',
  verified_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at       TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_user_device UNIQUE(user_id, device_fingerprint)
);

CREATE INDEX IF NOT EXISTS idx_trusted_devices_lookup
  ON public.user_trusted_devices(user_id, device_fingerprint);

ALTER TABLE public.user_trusted_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own trusted devices"
  ON public.user_trusted_devices FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own trusted devices"
  ON public.user_trusted_devices FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================
-- 2. Tabela: user_email_otp
--    Armazena códigos OTP temporários (hash SHA-256)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_email_otp (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code_hash   TEXT        NOT NULL,
  expires_at  TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '10 minutes'),
  attempts    INT         NOT NULL DEFAULT 0,
  used        BOOLEAN     NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_email_otp_active
  ON public.user_email_otp(user_id, used, expires_at);

ALTER TABLE public.user_email_otp ENABLE ROW LEVEL SECURITY;

-- Sem políticas de SELECT direto — todo acesso é via RPCs SECURITY DEFINER

-- ============================================================
-- 3. RPC: check_device_trusted
--    Verifica se o dispositivo atual é confiável (30 dias)
--    Admin TI é automaticamente isento do 2FA
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_device_trusted(p_device_fingerprint TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_role    public.user_role_level;
  v_trusted BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- TI Admin bypass — isento de 2FA
  SELECT role_level INTO v_role FROM public.users WHERE id = v_user_id;
  IF v_role = 'super_admin' THEN
    RETURN TRUE;
  END IF;

  -- Verificar se o dispositivo está registrado e não expirou
  SELECT EXISTS(
    SELECT 1 FROM public.user_trusted_devices
    WHERE user_id = v_user_id
      AND device_fingerprint = p_device_fingerprint
      AND expires_at > NOW()
  ) INTO v_trusted;

  RETURN COALESCE(v_trusted, FALSE);
END;
$$;

-- ============================================================
-- 4. RPC: verify_2fa_code
--    Valida o código OTP e registra o dispositivo como confiável
--    Retorna: 'valid', 'invalid', 'expired', 'blocked'
-- ============================================================
CREATE OR REPLACE FUNCTION public.verify_2fa_code(
  p_code              TEXT,
  p_device_fingerprint TEXT,
  p_device_name       TEXT DEFAULT 'Dispositivo Desconhecido'
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID;
  v_otp       RECORD;
  v_code_hash TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Buscar o OTP ativo mais recente
  SELECT * INTO v_otp
  FROM public.user_email_otp
  WHERE user_id = v_user_id
    AND used = false
    AND expires_at > NOW()
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_otp IS NULL THEN
    RETURN 'expired';
  END IF;

  -- Verificar se está bloqueado por excesso de tentativas
  IF v_otp.attempts >= 5 THEN
    UPDATE public.user_email_otp SET used = true WHERE id = v_otp.id;
    RETURN 'blocked';
  END IF;

  -- Gerar hash SHA-256 do código fornecido e comparar
  v_code_hash := encode(extensions.digest(p_code, 'sha256'), 'hex');

  IF v_code_hash = v_otp.code_hash THEN
    -- ✅ Código correto
    UPDATE public.user_email_otp SET used = true WHERE id = v_otp.id;

    -- Registrar/renovar dispositivo confiável por 30 dias
    INSERT INTO public.user_trusted_devices
      (user_id, device_fingerprint, device_name, verified_at, expires_at)
    VALUES
      (v_user_id, p_device_fingerprint, p_device_name, NOW(), NOW() + INTERVAL '30 days')
    ON CONFLICT ON CONSTRAINT uq_user_device
    DO UPDATE SET
      device_name = EXCLUDED.device_name,
      verified_at = NOW(),
      expires_at  = NOW() + INTERVAL '30 days';

    RETURN 'valid';
  ELSE
    -- ❌ Código incorreto — incrementar tentativas
    UPDATE public.user_email_otp
    SET attempts = attempts + 1
    WHERE id = v_otp.id;

    IF v_otp.attempts + 1 >= 5 THEN
      UPDATE public.user_email_otp SET used = true WHERE id = v_otp.id;
      RETURN 'blocked';
    END IF;

    RETURN 'invalid';
  END IF;
END;
$$;

-- ============================================================
-- 5. RPC: revoke_trusted_device
--    Remove a confiança de um dispositivo específico
-- ============================================================
CREATE OR REPLACE FUNCTION public.revoke_trusted_device(p_device_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.user_trusted_devices
  WHERE id = p_device_id AND user_id = auth.uid();
END;
$$;

-- ============================================================
-- 6. RPC: revoke_all_trusted_devices
--    Remove todos os dispositivos confiáveis do usuário
-- ============================================================
CREATE OR REPLACE FUNCTION public.revoke_all_trusted_devices()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.user_trusted_devices
  WHERE user_id = auth.uid();
END;
$$;

-- ============================================================
-- 7. Limpeza automática de OTPs expirados
-- ============================================================
CREATE OR REPLACE FUNCTION public.cleanup_expired_otps()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.user_email_otp
  WHERE expires_at < NOW() - INTERVAL '1 day';
END;
$$;

-- ============================================================
-- 8. Permissões de execução
-- ============================================================
GRANT EXECUTE ON FUNCTION public.check_device_trusted  TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_2fa_code       TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_trusted_device  TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_all_trusted_devices TO authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_otps   TO authenticated;
