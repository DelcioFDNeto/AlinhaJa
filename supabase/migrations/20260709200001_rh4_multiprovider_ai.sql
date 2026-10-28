-- ============================================================
-- BYOK multi-provedor — Anthropic (Claude), OpenAI (GPT) e
-- Google (Gemini). Estende 20260708220000 e 20260709190000.
--
-- • set_org_ai_key / delete_org_ai_key passam a aceitar 'gemini'
--   (com validação de formato da chave por provedor).
-- • O provedor ATIVO para a extração de RH é por organização,
--   guardado em organizations.settings->>'ai_provider'
--   (default 'anthropic'). set/get abaixo, restritos a admin.
-- A leitura da CHAVE continua exclusiva da service role via
-- get_org_ai_key (definida em 20260708220000).
-- ============================================================

-- ── set_org_ai_key: adiciona provedor gemini ─────────────────
CREATE OR REPLACE FUNCTION public.set_org_ai_key(p_provider text, p_key text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid;
  v_name text;
  v_secret_id uuid;
BEGIN
  SELECT organization_id INTO v_org
  FROM public.users
  WHERE id = auth.uid()
    AND role_level IN ('super_admin', 'admin');
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Apenas administradores podem configurar chaves de IA';
  END IF;

  IF p_provider NOT IN ('anthropic', 'openai', 'gemini') THEN
    RAISE EXCEPTION 'Provedor não suportado: %', p_provider;
  END IF;

  p_key := trim(p_key);
  IF p_provider = 'anthropic' AND p_key NOT LIKE 'sk-ant-%' THEN
    RAISE EXCEPTION 'Chave Anthropic inválida (deve começar com sk-ant-)';
  END IF;
  IF p_provider = 'openai' AND p_key NOT LIKE 'sk-%' THEN
    RAISE EXCEPTION 'Chave OpenAI inválida (deve começar com sk-)';
  END IF;
  IF p_provider = 'gemini' AND p_key NOT LIKE 'AIza%' THEN
    RAISE EXCEPTION 'Chave Gemini inválida (deve começar com AIza)';
  END IF;
  IF length(p_key) < 20 THEN
    RAISE EXCEPTION 'Chave muito curta';
  END IF;

  v_name := 'ai_key_' || p_provider || '_' || v_org::text;

  SELECT id INTO v_secret_id FROM vault.secrets WHERE name = v_name;
  IF v_secret_id IS NULL THEN
    PERFORM vault.create_secret(p_key, v_name);
  ELSE
    PERFORM vault.update_secret(v_secret_id, p_key);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_org_ai_key(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_org_ai_key(text, text) TO authenticated;

-- ── delete_org_ai_key: adiciona provedor gemini ──────────────
CREATE OR REPLACE FUNCTION public.delete_org_ai_key(p_provider text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid;
  v_name text;
  v_deleted integer;
BEGIN
  SELECT organization_id INTO v_org
  FROM public.users
  WHERE id = auth.uid()
    AND role_level IN ('super_admin', 'admin');
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Apenas administradores podem remover chaves de IA';
  END IF;

  IF p_provider NOT IN ('anthropic', 'openai', 'gemini') THEN
    RAISE EXCEPTION 'Provedor não suportado: %', p_provider;
  END IF;

  v_name := 'ai_key_' || p_provider || '_' || v_org::text;
  DELETE FROM vault.secrets WHERE name = v_name;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_org_ai_key(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_org_ai_key(text) TO authenticated;

-- ── Provedor ativo por organização (settings.ai_provider) ────
CREATE OR REPLACE FUNCTION public.set_org_ai_provider(p_provider text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid;
BEGIN
  SELECT organization_id INTO v_org
  FROM public.users
  WHERE id = auth.uid()
    AND role_level IN ('super_admin', 'admin');
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Apenas administradores podem definir o provedor de IA';
  END IF;

  IF p_provider NOT IN ('anthropic', 'openai', 'gemini') THEN
    RAISE EXCEPTION 'Provedor não suportado: %', p_provider;
  END IF;

  UPDATE public.organizations
  SET settings = jsonb_set(
        COALESCE(settings, '{}'::jsonb),
        '{ai_provider}', to_jsonb(p_provider), true)
  WHERE id = v_org;
END;
$$;

REVOKE ALL ON FUNCTION public.set_org_ai_provider(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_org_ai_provider(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_org_ai_provider()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid;
  v_provider text;
BEGIN
  SELECT organization_id INTO v_org
  FROM public.users
  WHERE id = auth.uid()
    AND role_level IN ('super_admin', 'admin');
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Apenas administradores podem consultar o provedor de IA';
  END IF;

  SELECT COALESCE(settings->>'ai_provider', 'anthropic') INTO v_provider
  FROM public.organizations WHERE id = v_org;

  RETURN COALESCE(v_provider, 'anthropic');
END;
$$;

REVOKE ALL ON FUNCTION public.get_org_ai_provider() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_org_ai_provider() TO authenticated;
