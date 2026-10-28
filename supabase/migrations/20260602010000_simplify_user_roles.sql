-- Migration: Simplificação dos Níveis de Acesso (user_role_level)
-- Restringe os níveis de acesso a somente 4 opções:
-- 1. super_admin (Somente TI)
-- 2. admin (Diretores e gerentes)
-- 3. manager (Supervisores)
-- 4. member (Os demais colaboradores)

-- 1. Dropar RLS policies que dependem da coluna role_level
-- Tabela public.meetings
DROP POLICY IF EXISTS "Apenas cargos gerenciais podem criar reuniões" ON public.meetings;

-- Tabela public.workflow_cards
DROP POLICY IF EXISTS "Operadores e gestores atualizam cards" ON public.workflow_cards;
DROP POLICY IF EXISTS "Responsável atualiza cards" ON public.workflow_cards;

-- Tabela public.support_tickets
DROP POLICY IF EXISTS "TI admin pode ver todos os tickets" ON public.support_tickets;
DROP POLICY IF EXISTS "TI admin pode atualizar todos os tickets" ON public.support_tickets;

-- Tabela public.support_ticket_messages
DROP POLICY IF EXISTS "TI admin vê todas as mensagens do ticket" ON public.support_ticket_messages;
DROP POLICY IF EXISTS "Todos podem inserir mensagens em tickets visíveis" ON public.support_ticket_messages;

-- Tabelas it_support_tickets e it_support_ticket_replies (dropar dinamicamente caso existam)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'it_support_tickets') THEN
    EXECUTE 'DROP POLICY IF EXISTS "Admins podem ver todos os tickets" ON public.it_support_tickets';
    EXECUTE 'DROP POLICY IF EXISTS "Admins podem atualizar tickets" ON public.it_support_tickets';
    EXECUTE 'DROP POLICY IF EXISTS "Admins podem deletar tickets" ON public.it_support_tickets';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'it_support_ticket_replies') THEN
    EXECUTE 'DROP POLICY IF EXISTS "Admins podem ver todas as respostas" ON public.it_support_ticket_replies';
  END IF;
END $$;

-- Tabela public.user_locations
DROP POLICY IF EXISTS "admin_select_all_locations" ON public.user_locations;
DROP POLICY IF EXISTS "admin_delete_locations" ON public.user_locations;

-- Tabela public.location_tracking_settings
DROP POLICY IF EXISTS "admin_read_all_tracking_settings" ON public.location_tracking_settings;
DROP POLICY IF EXISTS "admin_upsert_tracking_settings" ON public.location_tracking_settings;
DROP POLICY IF EXISTS "admin_update_tracking_settings" ON public.location_tracking_settings;


-- 2. Dropar o trigger que impede dropar a função handle_new_user
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;


-- 3. Dropar funções que dependem do tipo user_role_level antigo em suas assinaturas ou corpos
-- Dropar TODOS os overloads de admin_create_user (8, 9 e 10 parâmetros)
DROP FUNCTION IF EXISTS public.admin_create_user(TEXT, TEXT, TEXT, UUID, public.user_role_level, TEXT, TEXT, DATE);
DROP FUNCTION IF EXISTS public.admin_create_user(TEXT, TEXT, TEXT, UUID, public.user_role_level, TEXT, TEXT, TEXT, DATE);
DROP FUNCTION IF EXISTS public.admin_create_user(TEXT, TEXT, TEXT, UUID, public.user_role_level, TEXT, TEXT, TEXT, TEXT, DATE);
DROP FUNCTION IF EXISTS public.admin_reject_user(UUID);
DROP FUNCTION IF EXISTS public.admin_update_user_role(UUID, TEXT);
DROP FUNCTION IF EXISTS public.admin_toggle_user_status(UUID, BOOLEAN);
DROP FUNCTION IF EXISTS public.handle_new_user();


-- 4. Renomear o ENUM antigo para limpeza
ALTER TYPE public.user_role_level RENAME TO user_role_level_old;


-- 5. Criar o novo ENUM contendo apenas os 4 níveis de acesso oficiais
CREATE TYPE public.user_role_level AS ENUM ('super_admin', 'admin', 'manager', 'member');


-- 6. Alterar a coluna na tabela public.users mapeando os dados antigos de forma limpa e sem redundâncias
-- Remove o default antigo antes da alteração
ALTER TABLE public.users ALTER COLUMN role_level DROP DEFAULT;

-- Realiza a conversão de tipo e mapeamento de valores
ALTER TABLE public.users 
  ALTER COLUMN role_level TYPE public.user_role_level 
  USING (
    CASE role_level::text
      WHEN 'ti_admin' THEN 'super_admin'::public.user_role_level
      WHEN 'super_admin' THEN 'super_admin'::public.user_role_level
      WHEN 'director' THEN 'admin'::public.user_role_level
      WHEN 'admin' THEN 'admin'::public.user_role_level
      WHEN 'manager' THEN 'manager'::public.user_role_level
      WHEN 'store_leader' THEN 'manager'::public.user_role_level
      WHEN 'coordinator' THEN 'manager'::public.user_role_level
      WHEN 'staff' THEN 'member'::public.user_role_level
      WHEN 'member' THEN 'member'::public.user_role_level
      ELSE 'member'::public.user_role_level
    END
  );

-- Define o novo valor default como 'member'
ALTER TABLE public.users ALTER COLUMN role_level SET DEFAULT 'member'::public.user_role_level;


-- 7. Dropar o ENUM antigo renomeado
DROP TYPE public.user_role_level_old;


-- 8. Recriar funções de banco com o novo tipo user_role_level

-- admin_create_user
CREATE OR REPLACE FUNCTION public.admin_create_user(
  p_email TEXT,
  p_password TEXT,
  p_full_name TEXT,
  p_branch_id UUID,
  p_role_level public.user_role_level,
  p_job_function TEXT DEFAULT NULL,
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

EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Este e-mail já está cadastrado no sistema.';
END;
$$;

-- handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_role user_role_level := 'member';
  v_is_active BOOLEAN := false;
  v_branch_id UUID := NULL;
  v_job_function TEXT := NULL;
  v_department_id TEXT := NULL;
  v_job_position_id TEXT := NULL;
  v_phone TEXT := NULL;
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
  v_department_id := NEW.raw_user_meta_data ->> 'department_id';
  v_job_position_id := NEW.raw_user_meta_data ->> 'job_position_id';
  v_phone := NEW.raw_user_meta_data ->> 'phone';
  v_cpf := NEW.raw_user_meta_data ->> 'cpf';

  INSERT INTO public.users (
    id, full_name, avatar_url, role_level, is_active,
    branch_id, job_function, department_id, job_position_id,
    phone, cpf, email
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
    v_role,
    v_is_active,
    v_branch_id,
    v_job_function,
    v_department_id,
    v_job_position_id,
    v_phone,
    v_cpf,
    NEW.email
  )
  ON CONFLICT (id) DO NOTHING;

  IF v_is_active = false THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- admin_reject_user
CREATE OR REPLACE FUNCTION public.admin_reject_user(
  p_target_user_id UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  SELECT role_level INTO v_caller_role
  FROM public.users
  WHERE id = auth.uid();

  IF v_caller_role NOT IN ('super_admin', 'admin') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas Administradores podem rejeitar cadastros.';
  END IF;

  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode rejeitar seu próprio cadastro.';
  END IF;

  DELETE FROM auth.users WHERE id = p_target_user_id;
END;
$$;

-- admin_update_user_role
CREATE OR REPLACE FUNCTION public.admin_update_user_role(
  p_target_user_id UUID,
  p_new_role TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  SELECT role_level INTO v_caller_role
  FROM public.users WHERE id = auth.uid();

  IF v_caller_role NOT IN ('super_admin', 'admin') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas Administradores podem alterar níveis de acesso.';
  END IF;

  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode alterar seu próprio nível de acesso.';
  END IF;

  -- Somente super_admin pode promover para super_admin
  IF p_new_role = 'super_admin' AND v_caller_role != 'super_admin' THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas o Super Admin pode promover a este nível.';
  END IF;

  IF p_new_role NOT IN ('super_admin', 'admin', 'manager', 'member') THEN
    RAISE EXCEPTION 'Role inválido: %. Valores aceitos: super_admin, admin, manager, member', p_new_role;
  END IF;

  UPDATE public.users
  SET role_level = p_new_role::public.user_role_level
  WHERE id = p_target_user_id;
END;
$$;

-- admin_toggle_user_status
CREATE OR REPLACE FUNCTION public.admin_toggle_user_status(
  p_target_user_id UUID,
  p_is_active BOOLEAN
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  SELECT role_level INTO v_caller_role 
  FROM public.users WHERE id = auth.uid();

  -- super_admin e admin podem arquivar
  IF v_caller_role NOT IN ('super_admin', 'admin') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas Administradores podem arquivar contas.';
  END IF;

  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode alterar o próprio status.';
  END IF;

  UPDATE public.users SET is_active = p_is_active WHERE id = p_target_user_id;

  IF p_is_active = FALSE THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = p_target_user_id;
  ELSE
    UPDATE auth.users SET banned_until = NULL WHERE id = p_target_user_id;
  END IF;
END;
$$;


-- 9. Recriar o trigger de autenticação que aponta para handle_new_user
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- 10. Recriar RLS Policies com suporte aos novos roles

-- meetings
CREATE POLICY "Apenas cargos gerenciais podem criar reuniões"
ON public.meetings FOR INSERT
WITH CHECK (
  host_id = auth.uid() AND
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role_level IN ('super_admin', 'admin', 'manager')
  )
);

-- workflow_cards
CREATE POLICY "Operadores e gestores atualizam cards"
  ON public.workflow_cards FOR UPDATE
  USING (
    requested_by IS DISTINCT FROM auth.uid()
    AND (
      assigned_to = auth.uid()
      OR (
        EXISTS (
          SELECT 1
          FROM public.users u
          WHERE u.id = auth.uid()
            AND COALESCE(u.is_active, TRUE) = TRUE
            AND u.role_level::TEXT IN ('super_admin', 'admin', 'manager')
        )
        AND EXISTS (
          SELECT 1
          FROM public.channel_members cm
          WHERE cm.channel_id = workflow_cards.channel_id
            AND cm.user_id = auth.uid()
        )
      )
    )
  )
  WITH CHECK (
    requested_by IS DISTINCT FROM auth.uid()
    AND assigned_to IS DISTINCT FROM requested_by
  );

-- support_tickets
CREATE POLICY "TI admin pode ver todos os tickets"
  ON public.support_tickets FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN ('super_admin'))
  );

CREATE POLICY "TI admin pode atualizar todos os tickets"
  ON public.support_tickets FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN ('super_admin'))
  );

-- support_ticket_messages
CREATE POLICY "TI admin vê todas as mensagens do ticket"
  ON public.support_ticket_messages FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN ('super_admin'))
  );

CREATE POLICY "Todos podem inserir mensagens em tickets visíveis"
  ON public.support_ticket_messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid() AND
    (
      EXISTS (SELECT 1 FROM public.support_tickets st WHERE st.id = ticket_id AND st.creator_id = auth.uid())
      OR 
      EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN ('super_admin'))
    )
  );

-- it_support_tickets e it_support_ticket_replies (recriar dinamicamente caso existam)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'it_support_tickets') THEN
    EXECUTE '
      CREATE POLICY "Admins podem ver todos os tickets"
        ON public.it_support_tickets FOR SELECT
        USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN (''super_admin'', ''admin'')))
    ';
    EXECUTE '
      CREATE POLICY "Admins podem atualizar tickets"
        ON public.it_support_tickets FOR UPDATE
        USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN (''super_admin'', ''admin'')))
    ';
    EXECUTE '
      CREATE POLICY "Admins podem deletar tickets"
        ON public.it_support_tickets FOR DELETE
        USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN (''super_admin'', ''admin'')))
    ';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'it_support_ticket_replies') THEN
    EXECUTE '
      CREATE POLICY "Admins podem ver todas as respostas"
        ON public.it_support_ticket_replies FOR SELECT
        USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN (''super_admin'', ''admin'')))
    ';
  END IF;
END $$;

-- user_locations
CREATE POLICY "admin_select_all_locations" ON public.user_locations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role_level IN ('super_admin', 'admin')
    )
  );

CREATE POLICY "admin_delete_locations" ON public.user_locations
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role_level IN ('super_admin', 'admin')
    )
  );

-- location_tracking_settings
CREATE POLICY "admin_read_all_tracking_settings" ON public.location_tracking_settings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role_level IN ('super_admin', 'admin')
    )
  );

CREATE POLICY "admin_upsert_tracking_settings" ON public.location_tracking_settings
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role_level IN ('super_admin', 'admin')
    )
  );

CREATE POLICY "admin_update_tracking_settings" ON public.location_tracking_settings
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role_level IN ('super_admin', 'admin')
    )
  );
