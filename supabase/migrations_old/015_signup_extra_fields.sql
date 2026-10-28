-- ============================================================
-- 015: Campos adicionais para verificação de cadastro
-- Adiciona coluna CPF e atualiza trigger para extrair
-- phone, department e cpf dos metadados do signup.
-- ============================================================

-- 1. Adicionar coluna CPF (única, opcional para retrocompatibilidade)
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS cpf TEXT UNIQUE;

-- 2. Atualizar a trigger para extrair os novos campos
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
  v_branch_str TEXT;
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
    cpf
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
    v_cpf
  )
  ON CONFLICT (id) DO NOTHING;

  IF v_is_active = false THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- 3. Garantir constraint UNIQUE no nome da filial
ALTER TABLE public.branches ADD CONSTRAINT branches_name_unique UNIQUE (name);

-- 4. Popular filiais disponíveis para cadastro
INSERT INTO public.branches (name) VALUES
  ('Acará/PA'),
  ('Ananindeua/PA'),
  ('Barcarena/PA'),
  ('Belém/PA'),
  ('Bragança/PA'),
  ('Breves/PA'),
  ('Cametá/PA'),
  ('Capanema/PA'),
  ('Capitão Poço/PA'),
  ('Castanhal/PA'),
  ('Concórdia do Pará/PA'),
  ('Curuçá/PA'),
  ('Fortaleza (Aldeota)/CE'),
  ('Icoaraci/PA'),
  ('Igarapé Miri/PA'),
  ('Matriz / CD'),
  ('Moju/PA'),
  ('PDV Barcarena/PA'),
  ('PDV Paar/PA'),
  ('São Miguel do Guamá/PA'),
  ('Soure/PA'),
  ('Tailândia/PA'),
  ('Tomé-Açu/PA')
ON CONFLICT (name) DO NOTHING;
