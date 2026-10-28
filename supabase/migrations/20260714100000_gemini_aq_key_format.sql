-- ============================================================
-- BYOK — o Google passou a emitir chaves do Gemini no novo formato
-- "Auth key", que começa com 'AQ.Ab' em vez do clássico 'AIza'
-- (as chaves 'AIza' deixam de funcionar em setembro/2026). Esta
-- migração relaxa a validação de set_org_ai_key para aceitar ambos
-- os prefixos no provedor gemini. Estende 20260710150000.
-- ============================================================

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

  IF p_provider NOT IN ('anthropic', 'openai', 'gemini', 'groq') THEN
    RAISE EXCEPTION 'Provedor não suportado: %', p_provider;
  END IF;

  p_key := trim(p_key);
  IF p_provider = 'anthropic' AND p_key NOT LIKE 'sk-ant-%' THEN
    RAISE EXCEPTION 'Chave Anthropic inválida (deve começar com sk-ant-)';
  END IF;
  IF p_provider = 'openai' AND p_key NOT LIKE 'sk-%' THEN
    RAISE EXCEPTION 'Chave OpenAI inválida (deve começar com sk-)';
  END IF;
  -- Gemini: 'AIza' (Standard key) ou 'AQ.' (novo formato Auth key).
  IF p_provider = 'gemini'
     AND p_key NOT LIKE 'AIza%'
     AND p_key NOT LIKE 'AQ.%' THEN
    RAISE EXCEPTION 'Chave Gemini inválida (deve começar com AIza ou AQ.)';
  END IF;
  IF p_provider = 'groq' AND p_key NOT LIKE 'gsk_%' THEN
    RAISE EXCEPTION 'Chave Groq inválida (deve começar com gsk_)';
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
