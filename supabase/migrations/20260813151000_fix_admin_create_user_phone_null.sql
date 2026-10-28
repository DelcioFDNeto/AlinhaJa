-- ============================================================
-- Port do Fluxy (20260810120000_fix_admin_create_user_phone_null.sql)
--
-- PROBLEMA
-- `admin_create_user` insere `phone` como string vazia em `auth.users`.
-- A constraint UNIQUE `users_phone_key` aceita múltiplos NULL, mas só
-- UMA string vazia. Criar o 2º usuário sem telefone falha com
-- `duplicate key value violates unique constraint "users_phone_key"`.
--
-- HISTÓRICO — é a SEGUNDA vez que isso aparece
-- A 020_fix_phone_null_unique_constraint.sql já havia corrigido este
-- mesmo ponto; a 20260713101000_stamp_org_on_user_create.sql reescreveu
-- a função inteira para carimbar a org e trouxe o `''` de volta junto.
-- Ao reescrever `admin_create_user` no futuro, mantenha o `phone` como
-- NULL — o valor correto para "sem telefone".
--
-- SOLUÇÃO
-- 1. Normalizar em NULL os telefones vazios já gravados.
-- 2. Redefinir a função a partir da versão multi-tenant vigente
--    (20260713101000), trocando apenas o `''` do phone por NULL.
-- ============================================================

UPDATE auth.users SET phone = NULL WHERE phone = '';

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
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_new_user_id UUID;
  v_org UUID := public.fn_current_org();
BEGIN
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
    -- carimba a org do admin já no metadata (o trigger usa; o UPDATE reforça)
    jsonb_build_object('full_name', p_full_name, 'organization_id', v_org::text),
    -- phone NULL (não ''): ver cabeçalho, constraint users_phone_key
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
    organization_id = v_org,
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
