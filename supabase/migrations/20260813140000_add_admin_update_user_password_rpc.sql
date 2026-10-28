-- ============================================================
-- RPC: admin_update_user_password
-- Permite que administradores/super_admins redefinam a senha de
-- qualquer colaborador diretamente pelo perfil de edição de usuário.
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_update_user_password(
  p_target_user_id UUID,
  p_new_password TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  SELECT role_level INTO v_caller_role
  FROM public.users
  WHERE id = auth.uid() AND COALESCE(is_active, true) = true;

  IF v_caller_role NOT IN ('super_admin', 'admin') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas Administradores podem redefinir senhas.';
  END IF;

  IF p_new_password IS NULL OR length(trim(p_new_password)) < 6 THEN
    RAISE EXCEPTION 'A senha deve ter no mínimo 6 caracteres.';
  END IF;

  UPDATE auth.users
  SET encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf', 10)),
      updated_at = NOW()
  WHERE id = p_target_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuário não encontrado em auth.users.';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_user_password(UUID, TEXT) TO authenticated;
