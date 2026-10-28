-- CONSOLIDATED MIGRATIONS 014 to 020

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
    department,
    email
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
    NEW.raw_user_meta_data ->> 'department',
    NEW.email
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
    extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
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
    cpf,
    email
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
    NEW.email
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
  ('Matriz'),
  ('CD / Fábrica'),
  ('Moju/PA'),
  ('PDV Barcarena/PA'),
  ('PDV Paar/PA'),
  ('São Miguel do Guamá/PA'),
  ('Soure/PA'),
  ('Tailândia/PA'),
  ('Tomé-Açu/PA')
ON CONFLICT (name) DO NOTHING;
-- Criação da tabela de Tokens FCM para Push Notifications
CREATE TABLE IF NOT EXISTS public.user_fcm_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL, -- 'android', 'ios', 'web'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    UNIQUE(user_id, token) -- Um usuário não pode ter o mesmo token repetido
);

-- Habilitar RLS
ALTER TABLE public.user_fcm_tokens ENABLE ROW LEVEL SECURITY;

-- O usuário só pode visualizar seus próprios tokens
CREATE POLICY "Users can view own fcm tokens"
    ON public.user_fcm_tokens FOR SELECT
    USING (auth.uid() = user_id);

-- O usuário só pode inserir seus próprios tokens
CREATE POLICY "Users can insert own fcm tokens"
    ON public.user_fcm_tokens FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- O usuário só pode deletar seus próprios tokens (ex: no logout ou rotate)
CREATE POLICY "Users can delete own fcm tokens"
    ON public.user_fcm_tokens FOR DELETE
    USING (auth.uid() = user_id);

-- Opcional: Atualizar a data se o token for revisto
CREATE OR REPLACE FUNCTION update_user_fcm_tokens_updated_at()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = timezone('utc'::text, now());
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_fcm_tokens_modtime
BEFORE UPDATE ON public.user_fcm_tokens
FOR EACH ROW EXECUTE FUNCTION update_user_fcm_tokens_updated_at();

-- Dar GRANT às roles padrão do Supabase
GRANT ALL ON TABLE public.user_fcm_tokens TO authenticated;
GRANT ALL ON TABLE public.user_fcm_tokens TO service_role;
-- ============================================================
-- 016: Reações com Emoji + Fixar Mensagem
-- ============================================================

-- 1. Tabela de reações
CREATE TABLE IF NOT EXISTS public.message_reactions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id  UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  emoji       TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(message_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_reactions_message ON public.message_reactions(message_id);

-- RLS
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Membros veem reações do seu chat"
  ON public.message_reactions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = message_id AND public.is_chat_member(m.chat_id)
    )
  );

CREATE POLICY "Membros criam suas próprias reações"
  ON public.message_reactions FOR INSERT
  WITH CHECK (
    user_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = message_id AND public.is_chat_member(m.chat_id)
    )
  );

CREATE POLICY "Usuário remove suas próprias reações"
  ON public.message_reactions FOR DELETE
  USING (user_id = auth.uid());

-- 2. Coluna de mensagem fixada nos chats
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS pinned_message_id UUID REFERENCES public.messages(id) ON DELETE SET NULL;
-- ============================================================
-- 019: Pin Chats Feature
-- Adiciona a coluna is_pinned na tabela chat_members
-- e recria a função get_chats_with_preview para
-- priorizar chats fixados na ordenação.
-- ============================================================

-- 1. Adicionar coluna na tabela (se não existir)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name='chat_members' AND column_name='is_pinned'
    ) THEN
        ALTER TABLE public.chat_members ADD COLUMN is_pinned BOOLEAN DEFAULT false;
    END IF;
END
$$;

-- 2. Recriar a RPC get_chats_with_preview com a nova ordenação
CREATE OR REPLACE FUNCTION get_chats_with_preview()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT
      c.id,
      c.type,
      c.name,
      c.description,
      c.avatar_url,
      c.created_by,
      c.metadata,
      c.created_at,
      cm.last_read_at,
      cm.is_pinned, -- Novo atributo
      -- Última mensagem
      (
        SELECT row_to_json(lm)
        FROM (
          SELECT m.id, m.sender_id, m.content, m.content_type,
                 m.media_url, m.created_at
          FROM messages m
          WHERE m.chat_id = c.id AND m.deleted_at IS NULL
          ORDER BY m.created_at DESC
          LIMIT 1
        ) lm
      ) AS last_message,
      -- Contagem de não-lidas (apenas mensagens de OUTROS após last_read_at)
      (
        SELECT COUNT(*)::int
        FROM messages m
        WHERE m.chat_id = c.id
          AND m.deleted_at IS NULL
          AND m.sender_id != v_user_id
          AND m.created_at > cm.last_read_at
      ) AS unread_count,
      -- Outro usuário (para DMs)
      CASE WHEN c.type = 'direct' THEN (
        SELECT row_to_json(ou)
        FROM (
          SELECT u.id, u.full_name, u.avatar_url, u.is_online,
                 u.last_seen_at, u.role_level, u.job_function,
                 b.name AS branch_name
          FROM chat_members cm2
          JOIN users u ON u.id = cm2.user_id
          LEFT JOIN branches b ON b.id = u.branch_id
          WHERE cm2.chat_id = c.id AND cm2.user_id != v_user_id
          LIMIT 1
        ) ou
      ) ELSE NULL END AS other_user
    FROM chat_members cm
    JOIN chats c ON c.id = cm.chat_id
    WHERE cm.user_id = v_user_id
    -- Nova ordem: Primeiro fixados (is_pinned = true DESC), depois a última mensagem
    ORDER BY cm.is_pinned DESC, (
      SELECT m2.created_at FROM messages m2
      WHERE m2.chat_id = c.id AND m2.deleted_at IS NULL
      ORDER BY m2.created_at DESC LIMIT 1
    ) DESC NULLS LAST
  ) t;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;
-- ============================================================
-- 020: Fix FCM Token RLS — Adicionar política de UPDATE
-- Sem ela, o upsert no Flutter falha com erro RLS 42501.
-- ============================================================

-- Adiciona policy de UPDATE que estava faltando
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_fcm_tokens'
          AND policyname = 'Users can update own fcm tokens'
    ) THEN
        CREATE POLICY "Users can update own fcm tokens"
            ON public.user_fcm_tokens FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END
$$;
-- ============================================================
-- 021: Threads e Bots
-- Adiciona suporte a sub-conversas (threads) e mensagens de bot
-- na tabela messages, e cria o usuário-bot do sistema.
-- ============================================================

-- 1. Adicionar colunas na tabela messages
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS thread_id UUID REFERENCES public.messages(id);
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_bot BOOLEAN DEFAULT false;

-- Índice parcial para buscar replies de uma thread rapidamente
CREATE INDEX IF NOT EXISTS idx_messages_thread
  ON public.messages(thread_id, created_at ASC)
  WHERE thread_id IS NOT NULL;

-- 1.5. Garantir que as colunas necessárias pelo trigger 'handle_new_user' existam
-- (Caso alguma migration anterior como a 007 ou 015 tenha sido pulada)
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS department TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS cpf TEXT;

-- 2. Criar o usuário-bot do sistema
-- Inserir na tabela auth.users para satisfazer a foreign key
-- A trigger `handle_new_user` do banco fará o insert automático no public.users.
INSERT INTO auth.users (
  id, 
  instance_id, 
  aud, 
  role, 
  email, 
  encrypted_password, 
  email_confirmed_at, 
  raw_user_meta_data, 
  created_at, 
  updated_at
)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'bot@alinhaja.com.br',
  extensions.crypt('bot_alinhaja_password_123!!', extensions.gen_salt('bf')),
  now(),
  '{"full_name": "AlinhaJá Bot"}'::jsonb,
  now(),
  now()
)
ON CONFLICT (id) DO NOTHING;

-- Atualizar/Inserir dados complementares do bot no schema public.users
INSERT INTO public.users (id, full_name, avatar_url, job_function, role_level, email)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'AlinhaJá Bot',
  NULL,
  'Sistema Automatizado',
  'staff',
  'bot@alinhaja.com.br'
)
ON CONFLICT (id) DO UPDATE SET 
  full_name = EXCLUDED.full_name,
  job_function = EXCLUDED.job_function,
  role_level = EXCLUDED.role_level;

-- 3. Atualizar RPC get_chats_with_preview para excluir threads
-- Mensagens em threads NÃO devem aparecer como last_message nem contar como unread
CREATE OR REPLACE FUNCTION get_chats_with_preview()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT
      c.id,
      c.type,
      c.name,
      c.description,
      c.avatar_url,
      c.created_by,
      c.metadata,
      c.created_at,
      cm.last_read_at,
      cm.is_pinned,
      -- Última mensagem (excluindo threads)
      (
        SELECT row_to_json(lm)
        FROM (
          SELECT m.id, m.sender_id, m.content, m.content_type,
                 m.media_url, m.created_at, m.is_bot
          FROM messages m
          WHERE m.chat_id = c.id
            AND m.deleted_at IS NULL
            AND m.thread_id IS NULL  -- Exclui mensagens de thread
          ORDER BY m.created_at DESC
          LIMIT 1
        ) lm
      ) AS last_message,
      -- Contagem de não-lidas (excluindo threads)
      (
        SELECT COUNT(*)::int
        FROM messages m
        WHERE m.chat_id = c.id
          AND m.deleted_at IS NULL
          AND m.thread_id IS NULL  -- Exclui mensagens de thread
          AND m.sender_id != v_user_id
          AND m.created_at > cm.last_read_at
      ) AS unread_count,
      -- Outro usuário (para DMs)
      CASE WHEN c.type = 'direct' THEN (
        SELECT row_to_json(ou)
        FROM (
          SELECT u.id, u.full_name, u.avatar_url, u.is_online,
                 u.last_seen_at, u.role_level, u.job_function,
                 b.name AS branch_name
          FROM chat_members cm2
          JOIN users u ON u.id = cm2.user_id
          LEFT JOIN branches b ON b.id = u.branch_id
          WHERE cm2.chat_id = c.id AND cm2.user_id != v_user_id
          LIMIT 1
        ) ou
      ) ELSE NULL END AS other_user
    FROM chat_members cm
    JOIN chats c ON c.id = cm.chat_id
    WHERE cm.user_id = v_user_id
    ORDER BY cm.is_pinned DESC, (
      SELECT m2.created_at FROM messages m2
      WHERE m2.chat_id = c.id AND m2.deleted_at IS NULL AND m2.thread_id IS NULL
      ORDER BY m2.created_at DESC LIMIT 1
    ) DESC NULLS LAST
  ) t;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

