-- ============================================================
-- Migration 008: Admin Edit User (Profile Editing Support)
-- ============================================================
-- Este script adiciona uma função RPC segura (SECURITY DEFINER)
-- permitindo que a TI atualize os perfis de outros funcionários
-- (Nome Completo, Filial de Lotação, Cargo e Função) ignorando as 
-- travas do RLS que impedem os usuários de editar uns aos outros.
-- ============================================================

CREATE OR REPLACE FUNCTION admin_update_user(
  p_target_user_id UUID,
  p_full_name TEXT,
  p_branch_id UUID,
  p_role_level TEXT,
  p_job_function TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER -- Executa com os privilégios do criador (bypass RLS)
SET search_path = public
AS $$
DECLARE
  v_caller_role TEXT;
BEGIN
  -- 1. Verificar se quem chama tem permissões administrativas (TI)
  SELECT role_level INTO v_caller_role
  FROM public.users
  WHERE id = auth.uid();

  IF v_caller_role IS DISTINCT FROM 'ti_admin' THEN
    RAISE EXCEPTION 'Acesso negado: Somente Administradores TI podem editar perfis.';
  END IF;

  -- 2. Atualizar o registro do funcionário no esquema public
  UPDATE public.users
  SET 
    full_name = p_full_name,
    branch_id = p_branch_id,
    role_level = p_role_level::user_role_level,
    job_function = p_job_function,
    updated_at = NOW()
  WHERE id = p_target_user_id;

  -- Se o usuário não for encontrado (ex: inativo ou soft deleted),
  -- o UPDATE apenas afetará 0 linhas silenciosamente, o que é seguro.
END;
$$;
