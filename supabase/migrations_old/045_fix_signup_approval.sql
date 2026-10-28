-- ============================================================
-- Migration 045: FIX CRÍTICO — Trigger handle_new_user
-- PROBLEMA: Usuários auto-cadastrados entravam sem aprovação TI.
-- CAUSA: 1) Trigger desatualizado no banco, 2) coluna is_active DEFAULT true
-- SOLUÇÃO: Recriar trigger com is_active=false + banned_until + dados completos
-- ============================================================

-- 1. Coluna is_active DEFAULT deve ser FALSE (segurança: ninguém nasce ativo)
ALTER TABLE public.users ALTER COLUMN is_active SET DEFAULT false;

-- 2. Recriar a trigger COMPLETA (copia dados do metadata corretamente)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_role user_role_level := 'staff';
  v_is_active BOOLEAN := false;  -- SEMPRE inativo por padrão
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
  -- Extrair metadados do signup (raw_user_meta_data)
  v_branch_str := NEW.raw_user_meta_data ->> 'branch_id';
  IF v_branch_str IS NOT NULL AND v_branch_str != '' THEN
    BEGIN
      v_branch_id := v_branch_str::UUID;
    EXCEPTION WHEN invalid_text_representation THEN
      -- Se branch_id não for UUID válido (ex: fallback string), tenta buscar pelo nome
      SELECT id INTO v_branch_id FROM public.branches WHERE name = v_branch_str LIMIT 1;
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
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.users.full_name),
    branch_id = COALESCE(EXCLUDED.branch_id, public.users.branch_id),
    job_function = COALESCE(EXCLUDED.job_function, public.users.job_function),
    phone = COALESCE(EXCLUDED.phone, public.users.phone),
    department = COALESCE(EXCLUDED.department, public.users.department),
    cpf = COALESCE(EXCLUDED.cpf, public.users.cpf),
    sexo = COALESCE(EXCLUDED.sexo, public.users.sexo),
    data_nascimento = COALESCE(EXCLUDED.data_nascimento, public.users.data_nascimento);

  -- CRÍTICO: Se o cadastro não é o admin master, BANE o usuário até aprovação.
  IF v_is_active = false THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- 3. Garantir que o trigger existe (idempotente)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 4. Permitir leitura de branches para usuários NÃO autenticados (necessário no signup)
-- Apenas SELECT, sem mutação
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'branches' AND policyname = 'branches_public_read'
  ) THEN
    CREATE POLICY branches_public_read ON public.branches
      FOR SELECT USING (true);
  END IF;
END $$;
