-- ============================================================
-- Multi-tenant — Carimbar organization_id na criação de usuários
-- Antes: admin_create_user e handle_new_user dependiam do DEFAULT
-- (org DuBairro) — bug latente que colocaria TODO usuário novo na
-- DuBairro, inclusive os de outras empresas. Agora:
--   • handle_new_user  → lê organization_id do metadata do signup
--                        (fallback DuBairro para compatibilidade)
--   • admin_create_user → carimba a org do admin que está criando
--                        (fn_current_org), isolando por empresa
-- ============================================================

-- ── 1. handle_new_user: respeitar organization_id do metadata ─
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_role user_role_level := 'member';
  v_is_active BOOLEAN := false;
  v_branch_id UUID := NULL;
  v_department_id TEXT := NULL;
  v_job_position_id TEXT := NULL;
  v_phone TEXT := NULL;
  v_cpf TEXT := NULL;
  v_branch_str TEXT;
  v_org_str TEXT;
  -- DuBairro (org inicial) como fallback: mantém o single-tenant atual
  v_org UUID := 'a0000000-0000-4000-8000-000000000001';
BEGIN
  -- Extrai metadados do signup
  v_branch_str := NEW.raw_user_meta_data ->> 'branch_id';
  IF v_branch_str IS NOT NULL AND v_branch_str != '' THEN
    BEGIN
      v_branch_id := v_branch_str::UUID;
    EXCEPTION WHEN invalid_text_representation THEN
      v_branch_id := NULL;
    END;
  END IF;

  -- organization_id explícito (onboarding assistido / signup por empresa)
  v_org_str := NEW.raw_user_meta_data ->> 'organization_id';
  IF v_org_str IS NOT NULL AND v_org_str != '' THEN
    BEGIN
      v_org := v_org_str::UUID;
    EXCEPTION WHEN invalid_text_representation THEN
      v_org := 'a0000000-0000-4000-8000-000000000001';
    END;
  END IF;

  v_department_id := NEW.raw_user_meta_data ->> 'department_id';
  v_job_position_id := NEW.raw_user_meta_data ->> 'job_position_id';
  v_phone := NEW.raw_user_meta_data ->> 'phone';
  v_cpf := NEW.raw_user_meta_data ->> 'cpf';

  INSERT INTO public.users (
    id, full_name, avatar_url, role_level, is_active,
    branch_id, department_id, job_position_id,
    phone, cpf, email, organization_id
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
    v_role,
    v_is_active,
    v_branch_id,
    v_department_id,
    v_job_position_id,
    v_phone,
    v_cpf,
    NEW.email,
    v_org
  )
  ON CONFLICT (id) DO NOTHING;

  IF v_is_active = false THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- ── 2. admin_create_user: carimbar a org do admin criador ────
-- O admin (fn_current_org) só cria usuários na PRÓPRIA empresa.
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
