-- Migration: Painel Admin para Criação de Usuários
-- Ativa pgcrypto para poder criptografar senhas (necessário para o auth.users)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- RPC para criação de usuários (Apenas para ti_admin)
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
  -- 1. Validação de Segurança: Somente ti_admin pode chamar isso
  IF NOT EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() AND role_level = 'ti_admin'
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas a TI pode criar usuários.';
  END IF;

  -- 2. Gera UUID para o novo usuário
  v_new_user_id := gen_random_uuid();

  -- 3. Insere no auth.users (Tabela raiz de autenticação)
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
    crypt(p_password, gen_salt('bf', 10)), -- Adicionado o custo 10 para o bcrypt (padrão do GoTrue)
    now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', p_full_name),
    '', -- Adicionado phone
    NULL, -- phone_confirmed_at
    '', -- confirmation_token
    '', -- recovery_token
    '', -- email_change_token_new
    '', -- email_change
    now(),
    now()
  );

  -- 4. Insere no auth.identities (Necessário para login via E-mail no Supabase)
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

  -- 5. O Trigger handle_new_user já inseriu o registro em public.users
  -- com is_active=false e banned_until=3000.
  -- Como o ADMIN criou o usuário intencionalmente, ele já está APROVADO.
  -- Precisamos: (a) ativar, (b) setar dados corporativos, (c) remover o banimento.
  
  UPDATE public.users
  SET 
    branch_id = p_branch_id,
    role_level = p_role_level,
    job_function = p_job_function,
    sexo = COALESCE(p_sexo, sexo),
    data_nascimento = COALESCE(p_data_nascimento, data_nascimento),
    is_active = true  -- Admin criou → já aprovado
  WHERE id = v_new_user_id;

  -- Remover o banimento que a trigger aplicou (pois é um cadastro autorizado)
  UPDATE auth.users SET banned_until = NULL WHERE id = v_new_user_id;

  RETURN v_new_user_id;

EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Este e-mail já está cadastrado no sistema.';
END;
$$;
