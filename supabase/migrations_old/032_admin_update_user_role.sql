-- Migration 027: RPC segura para alteração de role_level pelo Admin
-- ==============================================================================
-- Substitui o .update() direto que é bloqueado pelo RLS (auth.uid() = id)

CREATE OR REPLACE FUNCTION public.admin_update_user_role(
  p_target_user_id UUID,
  p_new_role TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  -- 1. Verifica se quem está chamando é TI Admin ou Diretor
  SELECT role_level INTO v_caller_role
  FROM public.users WHERE id = auth.uid();

  IF v_caller_role NOT IN ('ti_admin', 'director') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas TI Admin ou Diretores podem alterar níveis de acesso.';
  END IF;

  -- 2. Não permite alterar o próprio role
  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode alterar seu próprio nível de acesso.';
  END IF;

  -- 3. Valida que o novo role é válido no enum
  IF p_new_role NOT IN ('staff', 'store_leader', 'supervisor', 'manager', 'director', 'ti_admin') THEN
    RAISE EXCEPTION 'Role inválido: %. Valores aceitos: staff, store_leader, supervisor, manager, director, ti_admin', p_new_role;
  END IF;

  -- 4. Atualiza o role_level do usuário alvo
  UPDATE public.users
  SET role_level = p_new_role::public.user_role_level
  WHERE id = p_target_user_id;

END;
$$;
