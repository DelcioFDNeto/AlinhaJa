-- ============================================================
-- RH-16 / Fase 7 — Portal do Candidato (Auth Customizada)
-- (PLANO-RH-COMPLETO.md). Sem uso do Supabase Auth.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── 1. Tabela de Contas de Candidatos ────────────────────────
CREATE TABLE IF NOT EXISTS public.candidato_usuario (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL CHECK (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  password_hash TEXT NOT NULL,
  nome TEXT NOT NULL CHECK (char_length(trim(nome)) >= 3),
  email_verified BOOLEAN NOT NULL DEFAULT false,
  verification_token UUID DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Nenhuma leitura/escrita anônima (somente Edge Function via service_role)
ALTER TABLE public.candidato_usuario ENABLE ROW LEVEL SECURITY;

-- ── 2. Tabela de Sessões ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.candidato_sessao (
  token UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidato_usuario_id UUID NOT NULL REFERENCES public.candidato_usuario(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '30 days',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sessao_candidato ON public.candidato_sessao(candidato_usuario_id);

ALTER TABLE public.candidato_sessao ENABLE ROW LEVEL SECURITY;

-- ── 3. Vínculo com a tabela de candidaturas ──────────────────
ALTER TABLE public.candidato ADD COLUMN IF NOT EXISTS candidato_usuario_id UUID REFERENCES public.candidato_usuario(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_candidato_usuario ON public.candidato(candidato_usuario_id);

-- ── 4. RPCs de Autenticação (Acessadas via Edge Function) ────

-- a) Signup
CREATE OR REPLACE FUNCTION public.rh_candidato_signup(p_nome TEXT, p_email TEXT, p_password TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
  v_verification UUID;
BEGIN
  INSERT INTO public.candidato_usuario (email, password_hash, nome)
  VALUES (lower(trim(p_email)), crypt(p_password, gen_salt('bf', 8)), trim(p_nome))
  RETURNING id, verification_token INTO v_id, v_verification;
  
  -- Vincula candidaturas antigas automaticamente (mesmo e-mail)
  UPDATE public.candidato SET candidato_usuario_id = v_id
  WHERE lower(trim(email)) = lower(trim(p_email)) AND candidato_usuario_id IS NULL;
  
  RETURN v_verification;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_candidato_signup(TEXT, TEXT, TEXT) FROM public, anon, authenticated;
-- Grant só para service_role (usado na Edge function)
GRANT EXECUTE ON FUNCTION public.rh_candidato_signup(TEXT, TEXT, TEXT) TO service_role;

-- b) Login
CREATE OR REPLACE FUNCTION public.rh_candidato_login(p_email TEXT, p_password TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user RECORD;
  v_token UUID;
BEGIN
  SELECT id, password_hash, email_verified INTO v_user
  FROM public.candidato_usuario WHERE email = lower(trim(p_email));
  
  IF v_user IS NULL OR v_user.password_hash <> crypt(p_password, v_user.password_hash) THEN
    RAISE EXCEPTION 'Credenciais inválidas';
  END IF;
  
  IF NOT v_user.email_verified THEN
    RAISE EXCEPTION 'E-mail não verificado';
  END IF;

  INSERT INTO public.candidato_sessao (candidato_usuario_id) VALUES (v_user.id) RETURNING token INTO v_token;
  RETURN v_token;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_candidato_login(TEXT, TEXT) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_candidato_login(TEXT, TEXT) TO service_role;

-- c) Verificação
CREATE OR REPLACE FUNCTION public.rh_candidato_verify(p_token UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
BEGIN
  UPDATE public.candidato_usuario SET email_verified = true, verification_token = NULL
  WHERE verification_token = p_token RETURNING id INTO v_id;
  
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_candidato_verify(UUID) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_candidato_verify(UUID) TO service_role;

-- d) Get User by Session
CREATE OR REPLACE FUNCTION public.rh_candidato_get_user(p_session_token UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user JSONB;
BEGIN
  -- Limpa sessões expiradas
  DELETE FROM public.candidato_sessao WHERE expires_at < NOW();
  
  SELECT jsonb_build_object('id', u.id, 'email', u.email, 'nome', u.nome) INTO v_user
  FROM public.candidato_sessao s
  JOIN public.candidato_usuario u ON u.id = s.candidato_usuario_id
  WHERE s.token = p_session_token;
  
  RETURN v_user;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_candidato_get_user(UUID) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_candidato_get_user(UUID) TO service_role;
