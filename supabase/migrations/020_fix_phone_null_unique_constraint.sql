-- ============================================================
-- Migration 020: Corrigir constraint UNIQUE de phone em auth.users
-- ============================================================
-- O INSERT na auth.users usava '' (string vazia) para phone,
-- causando violação de UNIQUE constraint ao criar o 2º usuário.
-- Solução: usar NULL em vez de ''.
-- ============================================================

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
    NULL, NULL, '', '', '', '', now(), now()
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

EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Este e-mail já está cadastrado no sistema.';
END;
$$;

-- Limpar phones vazios existentes para evitar problemas futuros
UPDATE auth.users SET phone = NULL WHERE phone = '';
