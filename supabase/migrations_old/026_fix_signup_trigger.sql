-- ============================================================
-- Migration 026: Atualização do Trigger handle_new_user
-- Garante que TODOS os campos do cadastro (incluindo
-- data_nascimento e sexo) sejam salvos corretamente.
-- ============================================================

-- 1. Garantir que as colunas existam
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS data_nascimento DATE;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS sexo TEXT;

-- 2. Atualizar a trigger para extrair TODOS os campos do signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_role user_role_level := 'staff';
  v_is_active BOOLEAN := false;
  v_branch_id UUID := NULL;
  v_job_function TEXT := NULL;
  v_phone TEXT := NULL;
  v_department TEXT := NULL;
  v_cpf TEXT := NULL;
  v_sexo TEXT := NULL;
  v_data_nascimento DATE := NULL;
  v_branch_str TEXT;
  v_dn_str TEXT;
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

  v_job_function := NEW.raw_user_meta_data ->> 'job_function';
  v_phone := NEW.raw_user_meta_data ->> 'phone';
  v_department := NEW.raw_user_meta_data ->> 'department';
  v_cpf := NEW.raw_user_meta_data ->> 'cpf';
  v_sexo := NEW.raw_user_meta_data ->> 'sexo';

  v_dn_str := NEW.raw_user_meta_data ->> 'data_nascimento';
  IF v_dn_str IS NOT NULL AND v_dn_str != '' THEN
    BEGIN
      v_data_nascimento := v_dn_str::DATE;
    EXCEPTION WHEN invalid_datetime_format THEN
      v_data_nascimento := NULL;
    END;
  END IF;

  INSERT INTO public.users (
    id,
    full_name,
    avatar_url,
    role_level,
    is_active,
    branch_id,
    job_function,
    phone,
    department,
    cpf,
    sexo,
    data_nascimento
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
    v_role,
    v_is_active,
    v_branch_id,
    v_job_function,
    v_phone,
    v_department,
    v_cpf,
    v_sexo,
    v_data_nascimento
  )
  ON CONFLICT (id) DO NOTHING;

  IF v_is_active = false THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;
