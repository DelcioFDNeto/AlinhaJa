-- ============================================================
-- RBAC — RPCs para o Painel Admin (Gerenciamento de Acessos)
-- Operações administrativas com guarda de papel (fn_is_admin) e
-- escopo de organização (fn_current_org), para o app não precisar
-- conhecer o organization_id nem manipular tabelas diretamente.
-- ============================================================

-- ── 1. Provisionar/garantir os perfis-padrão da org ──────────
-- Usado pelo botão "Criar perfis padrão" quando a lista está vazia.
CREATE OR REPLACE FUNCTION public.rbac_setup_default_roles()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT public.fn_is_admin() THEN
    RAISE EXCEPTION 'Apenas administradores podem configurar perfis';
  END IF;
  PERFORM public.fn_setup_default_roles(public.fn_current_org());
END;
$$;
REVOKE ALL ON FUNCTION public.rbac_setup_default_roles() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rbac_setup_default_roles() TO authenticated;

-- ── 2. Criar um novo perfil na própria org ───────────────────
CREATE OR REPLACE FUNCTION public.rbac_create_role(
  p_name text, p_description text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_org uuid := public.fn_current_org(); v_id uuid;
BEGIN
  IF NOT public.fn_is_admin() THEN
    RAISE EXCEPTION 'Apenas administradores podem criar perfis';
  END IF;
  IF COALESCE(trim(p_name), '') = '' THEN
    RAISE EXCEPTION 'Informe o nome do perfil';
  END IF;
  INSERT INTO public.rbac_roles (organization_id, name, description, is_system)
  VALUES (v_org, trim(p_name), NULLIF(trim(p_description), ''), false)
  ON CONFLICT (organization_id, name) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Já existe um perfil com este nome';
  END IF;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rbac_create_role(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rbac_create_role(text, text) TO authenticated;

-- ── 3. Excluir um perfil (bloqueia perfis de sistema) ────────
CREATE OR REPLACE FUNCTION public.rbac_delete_role(p_role_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_org uuid := public.fn_current_org(); v_sys boolean;
BEGIN
  IF NOT public.fn_is_admin() THEN
    RAISE EXCEPTION 'Apenas administradores podem excluir perfis';
  END IF;
  SELECT is_system INTO v_sys FROM public.rbac_roles
   WHERE id = p_role_id AND organization_id = v_org;
  IF v_sys IS NULL THEN
    RAISE EXCEPTION 'Perfil não encontrado';
  END IF;
  IF v_sys THEN
    RAISE EXCEPTION 'Perfis de sistema não podem ser excluídos';
  END IF;
  -- rbac_role_permissions e rbac_user_roles caem por ON DELETE CASCADE
  DELETE FROM public.rbac_roles WHERE id = p_role_id AND organization_id = v_org;
END;
$$;
REVOKE ALL ON FUNCTION public.rbac_delete_role(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rbac_delete_role(uuid) TO authenticated;

-- ── 4. Definir os perfis de um usuário (substitui os atuais) ─
CREATE OR REPLACE FUNCTION public.rbac_set_user_roles(
  p_user_id uuid, p_role_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_is_admin() THEN
    RAISE EXCEPTION 'Apenas administradores podem atribuir perfis';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users
                 WHERE id = p_user_id AND organization_id = v_org) THEN
    RAISE EXCEPTION 'Usuário não encontrado';
  END IF;

  DELETE FROM public.rbac_user_roles WHERE user_id = p_user_id;

  -- Só aceita perfis da mesma organização
  INSERT INTO public.rbac_user_roles (user_id, role_id)
  SELECT p_user_id, r.id
  FROM public.rbac_roles r
  WHERE r.id = ANY (p_role_ids) AND r.organization_id = v_org
  ON CONFLICT DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.rbac_set_user_roles(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rbac_set_user_roles(uuid, uuid[]) TO authenticated;
