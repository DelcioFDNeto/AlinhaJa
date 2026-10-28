-- ============================================================
-- BYOK — Chaves de IA por organização (SaaS multi-tenant)
-- Cada empresa fornece sua própria chave de API (Anthropic, e
-- futuramente outros provedores). As chaves ficam no Supabase
-- Vault (criptografadas), nunca em organizations/settings.
--
-- Modelo de acesso (write-only para o app):
--   set_org_ai_key  → admin da plataforma (role_level admin+)
--                     grava/atualiza a chave da PRÓPRIA org
--   has_org_ai_key  → admin consulta se está configurada (+ last4)
--   get_org_ai_key  → SOMENTE service role (Edge Functions);
--                     revogada de anon/authenticated — nenhuma
--                     sessão de usuário consegue ler a chave
-- ============================================================

-- ── 1. Gravar/atualizar a chave (upsert no Vault) ────────────
CREATE OR REPLACE FUNCTION public.set_org_ai_key(p_provider text, p_key text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid;
  v_name text;
  v_secret_id uuid;
BEGIN
  -- Guard: admin da plataforma (custo de IA é decisão da empresa,
  -- não do papel operacional de RH)
  SELECT organization_id INTO v_org
  FROM public.users
  WHERE id = auth.uid()
    AND role_level IN ('super_admin', 'admin');
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Apenas administradores podem configurar chaves de IA';
  END IF;

  IF p_provider NOT IN ('anthropic', 'openai') THEN
    RAISE EXCEPTION 'Provedor não suportado: %', p_provider;
  END IF;

  -- Validação superficial de formato (evita salvar lixo)
  p_key := trim(p_key);
  IF p_provider = 'anthropic' AND p_key NOT LIKE 'sk-ant-%' THEN
    RAISE EXCEPTION 'Chave Anthropic inválida (deve começar com sk-ant-)';
  END IF;
  IF p_provider = 'openai' AND p_key NOT LIKE 'sk-%' THEN
    RAISE EXCEPTION 'Chave OpenAI inválida (deve começar com sk-)';
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

-- ── 2. Consulta de status para a UI (nunca retorna a chave) ──
CREATE OR REPLACE FUNCTION public.has_org_ai_key(p_provider text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid;
  v_key text;
BEGIN
  SELECT organization_id INTO v_org
  FROM public.users
  WHERE id = auth.uid()
    AND role_level IN ('super_admin', 'admin');
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Apenas administradores podem consultar chaves de IA';
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets
    WHERE name = 'ai_key_' || p_provider || '_' || v_org::text
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_key := NULL;
  END;

  IF v_key IS NULL THEN
    RETURN jsonb_build_object('configured', false);
  END IF;
  RETURN jsonb_build_object(
    'configured', true,
    'last4', right(v_key, 4)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.has_org_ai_key(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_org_ai_key(text) TO authenticated;

-- ── 3. Leitura da chave — EXCLUSIVA da service role ──────────
CREATE OR REPLACE FUNCTION public.get_org_ai_key(p_org_id uuid, p_provider text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_key text;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets
    WHERE name = 'ai_key_' || p_provider || '_' || p_org_id::text
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_key := NULL;
  END;
  RETURN v_key;
END;
$$;

-- Nenhuma sessão de usuário lê a chave — nem admin (write-only p/ o app)
REVOKE ALL ON FUNCTION public.get_org_ai_key(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_org_ai_key(uuid, text) TO service_role;
