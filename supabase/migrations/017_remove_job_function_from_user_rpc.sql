-- ============================================================
-- Migration 017: Remover p_job_function de admin_create_user e admin_update_user
-- ============================================================
-- O campo job_function foi removido da tabela users (migration 015).
-- As funções RPC precisam ser atualizadas para não exigir mais esse parâmetro.
-- ============================================================

-- ── 1. Recriar admin_create_user SEM p_job_function ───────────
-- Primeiro dropa a versão antiga (com p_job_function)
DROP FUNCTION IF EXISTS public.admin_create_user(TEXT, TEXT, TEXT, UUID, public.user_role_level, TEXT, TEXT, TEXT, TEXT, DATE);

CREATE OR REPLACE FUNCTION public.admin_create_user(
  p_email TEXT,
  p_password TEXT,
  p_full_name TEXT,
  p_branch_id UUID,
  p_role_level public.user_role_level,
  p_department_id TEXT DEFAULT NULL,
  p_job_position_id TEXT DEFAULT NULL,
  p_sexo TEXT DEFAULT NULL,
  p_data_nascimento DATE DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_new_user_id UUID;
BEGIN
  -- Segurança: Somente super_admin e admin podem criar usuários
  IF NOT EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() AND role_level IN ('super_admin', 'admin')
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas Administradores podem criar usuários.';
  END IF;

  v_new_user_id := gen_random_uuid();

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    phone, phone_confirmed_at, confirmation_token, recovery_token,
    email_change_token_new, email_change, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_new_user_id, 'authenticated', 'authenticated',
    LOWER(p_email),
    extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', p_full_name),
    '', NULL, '', '', '', '', now(), now()
  );

  INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_new_user_id, v_new_user_id::text,
    jsonb_build_object('sub', v_new_user_id::text, 'email', LOWER(p_email), 'email_verified', true, 'phone_verified', false),
    'email', now(), now(), now()
  );

  UPDATE public.users
  SET 
    branch_id = p_branch_id,
    role_level = p_role_level,
    department_id = p_department_id,
    job_position_id = p_job_position_id,
    sexo = COALESCE(p_sexo, sexo),
    data_nascimento = COALESCE(p_data_nascimento, data_nascimento),
    is_active = true
  WHERE id = v_new_user_id;

  UPDATE auth.users SET banned_until = NULL WHERE id = v_new_user_id;

  RETURN v_new_user_id;

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Detailed Error: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END;
$$;

-- ── 2. Recriar admin_update_user SEM p_job_function ───────────
DROP FUNCTION IF EXISTS public.admin_update_user(UUID, TEXT, UUID, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.admin_update_user(
  p_target_user_id UUID,
  p_full_name TEXT,
  p_branch_id UUID,
  p_role_level TEXT,
  p_department_id TEXT DEFAULT NULL,
  p_job_position_id TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role TEXT;
BEGIN
  SELECT role_level INTO v_caller_role
  FROM public.users WHERE id = auth.uid();

  IF v_caller_role NOT IN ('super_admin', 'admin') THEN
    RAISE EXCEPTION 'Acesso negado: Somente Administradores podem editar perfis.';
  END IF;

  IF p_role_level = 'super_admin' AND v_caller_role != 'super_admin' THEN
    RAISE EXCEPTION 'Acesso negado: Apenas o Super Admin pode promover a este nível.';
  END IF;

  UPDATE public.users
  SET 
    full_name = p_full_name,
    branch_id = p_branch_id,
    role_level = p_role_level::user_role_level,
    department_id = p_department_id,
    job_position_id = p_job_position_id,
    updated_at = NOW()
  WHERE id = p_target_user_id;
END;
$$;
