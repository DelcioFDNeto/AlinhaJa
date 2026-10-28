-- ============================================================
-- BYOK — Remoção definitiva da chave de IA por organização
-- Complementa 20260708220000_rh4_multitenant_ai_keys.sql.
--
-- delete_org_ai_key → admin da plataforma (super_admin/admin)
--                     apaga a chave da PRÓPRIA org do Vault.
-- O secret é REMOVIDO de vault.secrets (não apenas esvaziado),
-- de modo que não sobra material criptografado no banco — reduz
-- superfície de vazamento/roubo. A extração por IA volta a
-- 'falhou' com 'missing_api_key' até que uma nova chave seja
-- configurada (nada trava o RH — S064).
-- ============================================================

CREATE OR REPLACE FUNCTION public.delete_org_ai_key(p_provider text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid;
  v_name text;
  v_deleted integer;
BEGIN
  -- Guard: admin da plataforma (mesma regra de set_org_ai_key)
  SELECT organization_id INTO v_org
  FROM public.users
  WHERE id = auth.uid()
    AND role_level IN ('super_admin', 'admin');
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Apenas administradores podem remover chaves de IA';
  END IF;

  IF p_provider NOT IN ('anthropic', 'openai') THEN
    RAISE EXCEPTION 'Provedor não suportado: %', p_provider;
  END IF;

  v_name := 'ai_key_' || p_provider || '_' || v_org::text;

  -- Remove o secret por completo (nome escopado à org — nunca toca
  -- em chaves de outras organizações nem em outros secrets do Vault)
  DELETE FROM vault.secrets WHERE name = v_name;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  -- true = havia chave e foi removida; false = já não existia
  RETURN v_deleted > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_org_ai_key(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_org_ai_key(text) TO authenticated;
