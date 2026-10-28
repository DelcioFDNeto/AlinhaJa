-- ============================================================
-- 014: User Self-Registration Flow (Approval System)
-- Altera a trigger para cadastros via App nascerem bloqueados.
-- O Painel Admin da TI continuará gerando contas ativas.
-- ============================================================

-- 1. Substituir a Trigger handle_new_user original
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_role user_role_level := 'staff';
  v_is_active BOOLEAN := false; -- Cadastros pelo app nascem inativos!
  v_branch_id UUID := NULL;
  v_job_function TEXT := NULL;
  
  -- Tentamos extrair UUID da filial se foi mandado no JSON do signup
  v_branch_str TEXT;
BEGIN
  -- Verifica se o Signup enviou filial e cargo nos metadados
  v_branch_str := NEW.raw_user_meta_data ->> 'branch_id';
  IF v_branch_str IS NOT NULL AND v_branch_str != '' THEN
    BEGIN
      v_branch_id := v_branch_str::UUID;
    EXCEPTION WHEN invalid_text_representation THEN
      v_branch_id := NULL;
    END;
  END IF;
  
  v_job_function := NEW.raw_user_meta_data ->> 'job_function';

  -- Insere na tabela pública com os metadados fornecidos
  INSERT INTO public.users (
    id, 
    full_name, 
    avatar_url, 
    role_level, 
    is_active,
    branch_id,
    job_function,
    cpf,
    phone,
    department
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
    v_role,
    v_is_active,
    v_branch_id,
    v_job_function,
    NEW.raw_user_meta_data ->> 'cpf',
    NEW.raw_user_meta_data ->> 'phone',
    NEW.raw_user_meta_data ->> 'department'
  )
  ON CONFLICT (id) DO NOTHING;

  -- Se o usuário não for a TI master (nasceu inativo), banimos ele imediatamente 
  -- para impedir a geração de sessão local no App antes da aprovação.
  IF v_is_active = false THEN
    -- Não podemos atualizar o auth.users diretamente DE DENTRO de uma trigger do auth.users.
    -- O correto para o Supabase (Postgres) quando queremos recusar login futuro
    -- é fazer um UPDATE POSTERIOR ou esperar que o próprio App deslogue localmente
    -- (que nós já implementamos no auth_provider.dart: `if (!user.isActive) signOut()`).
    
    -- No entanto, como somos SECURITY DEFINER, podemos atualizar outra coluna se a trigger for AFTER.
    -- Como a trigger já é AFTER INSERT ON auth.users, atualizamos o banned_until:
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;


-- 2. Atualizar o RPC admin_create_user para ignorar o banimento acima
-- (Se a TI cria, a conta já deve nascer 100% livre)
CREATE OR REPLACE FUNCTION public.admin_create_user(
  p_email TEXT,
  p_password TEXT,
  p_full_name TEXT,
  p_branch_id UUID,
  p_role_level public.user_role_level,
  p_job_function TEXT,
  p_sexo TEXT DEFAULT NULL,
  p_data_nascimento DATE DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_new_user_id UUID;
BEGIN
  -- Segurança: Somente TI pode.
  IF NOT EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() AND role_level = 'ti_admin'
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas a TI pode criar usuários diretamente.';
  END IF;

  v_new_user_id := gen_random_uuid();

  -- Insere no auth.users
  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    phone,
    phone_confirmed_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    created_at,
    updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_new_user_id,
    'authenticated',
    'authenticated',
    LOWER(p_email),
    crypt(p_password, gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', p_full_name),
    '',
    NULL,
    '',
    '',
    '',
    '',
    now(),
    now()
  );

  INSERT INTO auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_new_user_id,
    v_new_user_id::text,
    jsonb_build_object('sub', v_new_user_id::text, 'email', LOWER(p_email), 'email_verified', true, 'phone_verified', false),
    'email',
    now(),
    now(),
    now()
  );

  -- Após a Trigger handle_new_user rodar e possivelmente bloquear a conta,
  -- Nós APROVAMOS forçadamente (pois foi a própria TI que criou) e atualizamos tudo.
  UPDATE public.users
  SET 
    branch_id = p_branch_id,
    role_level = p_role_level,
    job_function = p_job_function,
    sexo = p_sexo,
    data_nascimento = p_data_nascimento,
    is_active = true
  WHERE id = v_new_user_id;

  UPDATE auth.users SET banned_until = NULL WHERE id = v_new_user_id;

  RETURN v_new_user_id;
END;
$$;
