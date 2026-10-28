-- Migration: 20260724100000_rh19_automacoes_comunicacao.sql

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ==============================================================================
-- 1. org_smtp_config
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.org_smtp_config (
  organization_id UUID PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
  host TEXT NOT NULL,
  port INTEGER NOT NULL DEFAULT 465,
  username TEXT NOT NULL,
  password_encrypted BYTEA NOT NULL,
  from_email TEXT NOT NULL,
  from_name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==============================================================================
-- 2. rh_email_template
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.rh_email_template (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  nome TEXT NOT NULL,
  assunto TEXT NOT NULL,
  body_html TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rh_email_template_org ON public.rh_email_template(organization_id);

-- ==============================================================================
-- 3. rh_automacao
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.rh_automacao (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  evento TEXT NOT NULL,
  condicao JSONB NOT NULL,
  acao TEXT NOT NULL,
  template_id UUID REFERENCES public.rh_email_template(id) ON DELETE SET NULL,
  ativo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rh_automacao_org ON public.rh_automacao(organization_id);

-- ==============================================================================
-- 4. rh_comunicacao_log
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.rh_comunicacao_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  candidato_id UUID NOT NULL REFERENCES public.candidato(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL,
  assunto TEXT,
  status TEXT NOT NULL,
  erro_detalhe TEXT,
  enviado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rh_comunicacao_log_org ON public.rh_comunicacao_log(organization_id);
CREATE INDEX idx_rh_comunicacao_log_cand ON public.rh_comunicacao_log(candidato_id);

-- ==============================================================================
-- Triggers de Updated_at
-- ==============================================================================
CREATE TRIGGER trg_org_smtp_config_updated_at
BEFORE UPDATE ON public.org_smtp_config
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_rh_email_template_updated_at
BEFORE UPDATE ON public.rh_email_template
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_rh_automacao_updated_at
BEFORE UPDATE ON public.rh_automacao
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ==============================================================================
-- RLS (Row Level Security)
-- ==============================================================================
ALTER TABLE public.org_smtp_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_email_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_automacao ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_comunicacao_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin manage org_smtp_config"
  ON public.org_smtp_config FOR ALL
  USING (organization_id = public.fn_current_org() AND (public.fn_is_admin() OR public.fn_is_rh()));

CREATE POLICY "RH manage rh_email_template"
  ON public.rh_email_template FOR ALL
  USING (organization_id = public.fn_current_org() AND public.fn_is_rh());

CREATE POLICY "RH manage rh_automacao"
  ON public.rh_automacao FOR ALL
  USING (organization_id = public.fn_current_org() AND public.fn_is_rh());

CREATE POLICY "RH view rh_comunicacao_log"
  ON public.rh_comunicacao_log FOR SELECT
  USING (organization_id = public.fn_current_org() AND public.fn_is_rh());

CREATE POLICY "RH insert rh_comunicacao_log"
  ON public.rh_comunicacao_log FOR INSERT
  WITH CHECK (organization_id = public.fn_current_org() AND public.fn_is_rh());

-- ==============================================================================
-- RPCs para Salvar e Ler Configuração SMTP (com PGCrypto)
-- ==============================================================================
-- Usamos a chave da env var 'app.encryption_key' ou um fallback (em prod, isso deve ser configurado via SQL)
-- Para simplificar sem exigir configuração manual do dev, usaremos uma chave estática no BD para PGCrypto,
-- ou melhor ainda, uma chave atrelada ao organization_id para isolamento.

CREATE OR REPLACE FUNCTION public.rh_save_smtp_config(
  p_host TEXT,
  p_port INTEGER,
  p_username TEXT,
  p_password TEXT,
  p_from_email TEXT,
  p_from_name TEXT
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_org_id UUID;
  v_secret TEXT;
BEGIN
  v_org_id := public.fn_current_org();
  IF NOT (public.fn_is_admin() OR public.fn_is_rh()) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  -- Chave de criptografia baseada no ID da organização + um salt estático do sistema
  v_secret := v_org_id::TEXT || '_alinha_ja_smtp_secret';

  INSERT INTO public.org_smtp_config (
    organization_id, host, port, username, password_encrypted, from_email, from_name
  ) VALUES (
    v_org_id, p_host, p_port, p_username, pgp_sym_encrypt(p_password, v_secret), p_from_email, p_from_name
  )
  ON CONFLICT (organization_id) DO UPDATE SET
    host = EXCLUDED.host,
    port = EXCLUDED.port,
    username = EXCLUDED.username,
    password_encrypted = EXCLUDED.password_encrypted,
    from_email = EXCLUDED.from_email,
    from_name = EXCLUDED.from_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.rh_get_smtp_config()
RETURNS TABLE (
  host TEXT, port INTEGER, username TEXT, from_email TEXT, from_name TEXT, password_decrypted TEXT
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_org_id UUID;
  v_secret TEXT;
BEGIN
  v_org_id := public.fn_current_org();
  IF NOT (public.fn_is_admin() OR public.fn_is_rh()) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  v_secret := v_org_id::TEXT || '_alinha_ja_smtp_secret';

  RETURN QUERY
  SELECT
    c.host, c.port, c.username, c.from_email, c.from_name,
    pgp_sym_decrypt(c.password_encrypted, v_secret) AS password_decrypted
  FROM public.org_smtp_config c
  WHERE c.organization_id = v_org_id;
END;
$$;
