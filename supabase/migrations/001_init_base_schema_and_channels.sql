-- CONSOLIDATED MIGRATIONS 001 to 013

-- ============================================================
-- AlinhaJá — Schema completo para Supabase
-- Compatível com Flutter (supabase_flutter) + Realtime + RLS
-- ============================================================
-- Executar no SQL Editor do painel Supabase em um banco NOVO.
-- Este script é seguro para rodar uma única vez.
-- ============================================================

-- ── Extensões ───────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── ENUMs (com verificação de existência) ───────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'chat_type') THEN
    CREATE TYPE chat_type AS ENUM ('direct', 'group', 'channel');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'content_type') THEN
    CREATE TYPE content_type AS ENUM ('text', 'image', 'audio', 'file');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'member_role') THEN
    CREATE TYPE member_role AS ENUM ('owner', 'admin', 'member');
  END IF;
END $$;

-- ── Helper: atualização automática de updated_at ────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- ============================================================
-- 1. USERS (espelha auth.users — criado AUTOMATICAMENTE via trigger)
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
  id             UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name      TEXT NOT NULL DEFAULT '',
  avatar_url     TEXT,
  phone          TEXT,
  email          TEXT,
  -- Campos de integração futura com AlinhaJá
  job_title      TEXT,
  department     TEXT,
  is_online      BOOLEAN NOT NULL DEFAULT false,
  last_seen_at   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS users_updated_at ON users;
CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Usuário lê qualquer perfil"
  ON users FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Usuário edita apenas o próprio perfil"
  ON users FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Usuário cria seu próprio perfil"
  ON users FOR INSERT WITH CHECK (auth.uid() = id);

-- ── Trigger: cria perfil automaticamente no sign-up ─────────
-- SECURITY DEFINER bypassa RLS (o trigger roda como owner do banco).
-- Lê full_name de raw_user_meta_data (passado pelo app no signUp).
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  INSERT INTO public.users (id, full_name, avatar_url, email)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
    NEW.email
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- Aplica o trigger na tabela auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 2. CHATS
-- ============================================================
CREATE TABLE IF NOT EXISTS chats (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type        chat_type NOT NULL DEFAULT 'direct',
  name        TEXT,
  description TEXT,
  avatar_url  TEXT,
  created_by  UUID REFERENCES users(id),
  -- Campo extensível para integração com AlinhaJá
  metadata    JSONB NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS chats_updated_at ON chats;
CREATE TRIGGER chats_updated_at
  BEFORE UPDATE ON chats
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- 3. CHAT_MEMBERS
-- ============================================================
CREATE TABLE IF NOT EXISTS chat_members (
  chat_id      UUID NOT NULL REFERENCES chats(id)  ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
  role         member_role NOT NULL DEFAULT 'member',
  last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  joined_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (chat_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_members_user ON chat_members(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_chat ON chat_members(chat_id);

-- ============================================================
-- 4. MESSAGES
-- ============================================================
CREATE TABLE IF NOT EXISTS messages (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id          UUID NOT NULL REFERENCES chats(id)    ON DELETE CASCADE,
  sender_id        UUID NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  content          TEXT,
  content_type     content_type NOT NULL DEFAULT 'text',
  media_url        TEXT,
  media_mime_type  TEXT,
  media_size_bytes INTEGER,
  reply_to         UUID REFERENCES messages(id),
  -- Campo JSONB extensível:
  --   image: { image_width, image_height }
  --   audio: { duration_seconds, ai_transcription }  ← futura IA
  --   file:  { original_filename }
  metadata         JSONB NOT NULL DEFAULT '{}',
  deleted_at       TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_chat_created ON messages(chat_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender       ON messages(sender_id);

-- ── RLS das tabelas que dependem umas das outras ────────────
-- Para evitar recursão infinita (chat_members referenciando
-- a si mesma via policy), usamos uma função SECURITY DEFINER
-- que bypassa RLS ao checar membership.

CREATE OR REPLACE FUNCTION public.is_chat_member(p_chat_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM chat_members
    WHERE chat_id = p_chat_id AND user_id = auth.uid()
  );
END;
$$;

-- CHATS RLS
ALTER TABLE chats ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Membros e criadores veem o chat"
  ON public.chats FOR SELECT
  USING (
    created_by = auth.uid() OR
    public.is_chat_member(id)
  );
CREATE POLICY "Membros criam chats"
  ON chats FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- CHAT_MEMBERS RLS
ALTER TABLE chat_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Membro vê os membros do seu chat"
  ON chat_members FOR SELECT
  USING (public.is_chat_member(chat_id));
CREATE POLICY "Membro atualiza seu próprio last_read_at"
  ON chat_members FOR UPDATE
  USING (user_id = auth.uid());
CREATE POLICY "Inserção de membros"
  ON chat_members FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- MESSAGES RLS
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Membros leem mensagens do seu chat"
  ON messages FOR SELECT
  USING (public.is_chat_member(chat_id));
CREATE POLICY "Membros inserem mensagens no seu chat"
  ON messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid() AND
    public.is_chat_member(chat_id)
  );
CREATE POLICY "Autor pode apagar (soft delete) a mensagem"
  ON messages FOR UPDATE
  USING (sender_id = auth.uid());
CREATE POLICY "Autor pode deletar mensagem"
  ON messages FOR DELETE
  USING (sender_id = auth.uid());

-- ── Habilita Realtime para a tabela messages ────────────────
-- A publicação supabase_realtime já existe em projetos Supabase.
-- Usamos DO para evitar erro se a tabela já estiver adicionada.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE messages;
  END IF;
END $$;

-- ============================================================
-- 5. FUNÇÃO: create_direct_chat
--    Cria DM entre dois usuários (idempotente — reutiliza se já existe)
--    SECURITY DEFINER: executa com permissão do owner, bypassando RLS
-- ============================================================
CREATE OR REPLACE FUNCTION create_direct_chat(other_user_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_chat_id UUID;
BEGIN
  -- Verifica se já existe DM entre os dois
  SELECT cm1.chat_id INTO v_chat_id
  FROM chat_members cm1
  INNER JOIN chat_members cm2 ON cm1.chat_id = cm2.chat_id
  INNER JOIN chats c ON c.id = cm1.chat_id
  WHERE cm1.user_id = auth.uid()
    AND cm2.user_id = other_user_id
    AND c.type = 'direct'
  LIMIT 1;

  -- Se não existe, cria
  IF v_chat_id IS NULL THEN
    INSERT INTO chats (type, created_by)
    VALUES ('direct', auth.uid())
    RETURNING id INTO v_chat_id;

    INSERT INTO chat_members (chat_id, user_id, role) VALUES
      (v_chat_id, auth.uid(),      'owner'),
      (v_chat_id, other_user_id,   'member');
  END IF;

  RETURN v_chat_id;
END;
$$;
-- ============================================================
-- AlinhaJá — Supabase Storage
-- Executar APÓS o 001_initial_schema.sql
-- ============================================================
-- Seguro para rodar em banco novo.
-- ============================================================

-- 1. Cria o bucket público para mídias do chat (idempotente)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-media',
  'chat-media',
  true,
  26214400,  -- 25 MB em bytes
  ARRAY['image/jpeg','image/png','image/webp','image/gif',
        'audio/mpeg','audio/ogg','audio/wav','audio/m4a',
        'application/pdf','application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
)
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Leitura pública (necessário para NetworkImage no Flutter)
-- Drop + Create para evitar conflito em re-execuções
DROP POLICY IF EXISTS "Leitura pública das mídias" ON storage.objects;
CREATE POLICY "Leitura pública das mídias"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'chat-media');

-- 3. Upload apenas por usuários autenticados
DROP POLICY IF EXISTS "Upload autenticado de mídias" ON storage.objects;
CREATE POLICY "Upload autenticado de mídias"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'chat-media' AND
    auth.role() = 'authenticated'
  );

-- 4. Atualização (necessária para upserts do Storage)
DROP POLICY IF EXISTS "Update autenticado de mídias" ON storage.objects;
CREATE POLICY "Update autenticado de mídias"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'chat-media' AND
    auth.role() = 'authenticated'
  );

-- 5. Deleção apenas por usuários autenticados membros do chat
--    Convenção de path: chats/{chatId}/{uuid}.ext
DROP POLICY IF EXISTS "Deleção pelo membro do chat" ON storage.objects;
DROP POLICY IF EXISTS "Deleção pelo autor" ON storage.objects;
CREATE POLICY "Deleção pelo membro do chat"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'chat-media' AND
    auth.role() = 'authenticated' AND
    EXISTS (
      SELECT 1 FROM public.chat_members
      WHERE chat_id = (string_to_array(name, '/'))[2]::uuid
        AND user_id = auth.uid()
    )
  );
-- ============================================================
-- Migração 003: Hierarquia Corporativa e Filiais (RBAC)
-- ============================================================

-- ── 1. Helper: atualização automática de updated_at para a nova tabela
-- (Reaproveita a função set_updated_at() já criada no schema 001)

-- ── 2. Tabela de Filiais (branches) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branches (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  is_headquarters BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS branches_updated_at ON public.branches;
CREATE TRIGGER branches_updated_at
  BEFORE UPDATE ON public.branches
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- RLS: Qualquer usuário autenticado pode ler as filiais
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Leitura de filiais para autenticados"
  ON public.branches FOR SELECT
  USING (auth.role() = 'authenticated');

-- Insere filiais iniciais de exemplo se a tabela estiver vazia
INSERT INTO public.branches (name, is_headquarters) 
SELECT 'Matriz Corporativa', true
WHERE NOT EXISTS (SELECT 1 FROM public.branches);

-- ── 3. ENUM: Nível de Acesso Hierárquico ──────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role_level') THEN
    CREATE TYPE user_role_level AS ENUM ('ti_admin', 'director', 'manager', 'coordinator', 'staff');
  END IF;
END $$;

-- ── 4. Atualização da Tabela users ────────────────────────────────────
ALTER TABLE public.users 
  ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS role_level user_role_level NOT NULL DEFAULT 'staff',
  ADD COLUMN IF NOT EXISTS job_function TEXT;

CREATE INDEX IF NOT EXISTS idx_users_branch ON public.users(branch_id);
CREATE INDEX IF NOT EXISTS idx_users_role   ON public.users(role_level);

-- ── 5. Atualização do Trigger de Criação de Usuário (Admin Master) ────
-- A promoção de uma conta fixa no cadastro foi removida (20261028120000):
-- o primeiro administrador é definido na instalação.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_role user_role_level := 'staff';
BEGIN
  INSERT INTO public.users (
    id, full_name, avatar_url, role_level, email
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
    v_role,
    NEW.email
  )
  ON CONFLICT (id) DO NOTHING;
  
  RETURN NEW;
END;
$$;

-- Aplica retroativamente o cargo de TI para contas já criadas com este email
DO $$
DECLARE
  v_ti_id UUID;
BEGIN
  SELECT id INTO v_ti_id FROM auth.users WHERE email = 'ti@alinhaja.com.br';
  IF v_ti_id IS NOT NULL THEN
    UPDATE public.users SET role_level = 'ti_admin' WHERE id = v_ti_id;
  END IF;
END $$;
-- ============================================================
-- Migração 004: Canais Oficiais e Assinatura Digital
-- ============================================================

-- ── 1. Tabela: message_acknowledgements ──────────────────────────────
-- Armazena o registro de ciência/assinatura digital de comunicados.
CREATE TABLE IF NOT EXISTS public.message_acknowledgements (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id      UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  acknowledged_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Campos para auditoria/rastreabilidade legal
  ip_address      TEXT,
  device_info     TEXT,
  UNIQUE(message_id, user_id) -- Um usuário só assina a mesma mensagem uma vez
);

CREATE INDEX IF NOT EXISTS idx_msg_ack_message ON public.message_acknowledgements(message_id);
CREATE INDEX IF NOT EXISTS idx_msg_ack_user    ON public.message_acknowledgements(user_id);

-- RLS
ALTER TABLE public.message_acknowledgements ENABLE ROW LEVEL SECURITY;

-- Usuários podem ver as assinaturas das mensagens dos chats que eles participam
CREATE POLICY "Membros veem assinaturas do seu chat"
  ON public.message_acknowledgements FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = message_id AND public.is_chat_member(m.chat_id)
    )
  );

-- Usuários só podem assinar por eles mesmos
CREATE POLICY "Usuário cria sua própria assinatura"
  ON public.message_acknowledgements FOR INSERT
  WITH CHECK (
    user_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = message_id AND public.is_chat_member(m.chat_id)
    )
  );

-- ── 2. RPC: acknowledge_message ───────────────────────────────────────
-- Função facilitadora para o app assinar uma mensagem.
CREATE OR REPLACE FUNCTION public.acknowledge_message(
  p_message_id UUID,
  p_ip_address TEXT DEFAULT NULL,
  p_device_info TEXT DEFAULT NULL
)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  -- Verifica se a mensagem exige assinatura
  IF NOT EXISTS (
    SELECT 1 FROM public.messages 
    WHERE id = p_message_id AND (metadata->>'requires_acknowledgement')::boolean = true
  ) THEN
    RAISE EXCEPTION 'This message does not require acknowledgement.';
  END IF;

  INSERT INTO public.message_acknowledgements (message_id, user_id, ip_address, device_info)
  VALUES (p_message_id, auth.uid(), p_ip_address, p_device_info)
  ON CONFLICT (message_id, user_id) DO NOTHING;

  RETURN TRUE;
END;
$$;

-- ── 3. RPC: create_company_channel ────────────────────────────────────
-- Cria um "Megalofone" (canal) e adiciona TODOS os usuários da empresa.
-- Apenas admins/diretores deveriam chamar isso.
CREATE OR REPLACE FUNCTION public.create_company_channel(
  p_name TEXT,
  p_description TEXT
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_chat_id UUID;
  v_user RECORD;
BEGIN
  -- Cria o chat do tipo canal
  INSERT INTO public.chats (type, name, description, created_by)
  VALUES ('channel', p_name, p_description, auth.uid())
  RETURNING id INTO v_chat_id;

  -- Adiciona o criador como 'owner'
  INSERT INTO public.chat_members (chat_id, user_id, role)
  VALUES (v_chat_id, auth.uid(), 'owner');

  -- Adiciona todos os outros usuários como 'member'
  FOR v_user IN SELECT id FROM public.users WHERE id != auth.uid() LOOP
    INSERT INTO public.chat_members (chat_id, user_id, role)
    VALUES (v_chat_id, v_user.id, 'member')
    ON CONFLICT (chat_id, user_id) DO NOTHING;
  END LOOP;

  RETURN v_chat_id;
END;
$$;

-- ── 4. Trigger: Auto-adicionar novos colaboradores em Canais ─────────
-- Sempre que uma nova pessoa entra na empresa, ela é adicionada 
-- automaticamente em todos os chats do tipo 'channel'.
CREATE OR REPLACE FUNCTION public.add_new_user_to_channels()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_channel RECORD;
BEGIN
  FOR v_channel IN SELECT id FROM public.chats WHERE type = 'channel' LOOP
    INSERT INTO public.chat_members (chat_id, user_id, role)
    VALUES (v_channel.id, NEW.id, 'member')
    ON CONFLICT (chat_id, user_id) DO NOTHING;
  END LOOP;
  RETURN NEW;
END;
$$;

-- Aplica o trigger na tabela public.users
DROP TRIGGER IF EXISTS on_user_created_add_to_channels ON public.users;
CREATE TRIGGER on_user_created_add_to_channels
  AFTER INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.add_new_user_to_channels();
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
    extensions.crypt(p_password, extensions.gen_salt('bf', 10)), -- Adicionado o custo 10 para o bcrypt (padrão do GoTrue)
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
-- Migration: Adicionar 'store_leader' ao ENUM user_role_level
-- Segurança: COMMIT não é necessário no Supabase free, mas ALTER TYPE não roda
-- dentro de transações padrão do PostgreSQL em algumas versões se não for feito separadamente.

ALTER TYPE public.user_role_level ADD VALUE IF NOT EXISTS 'store_leader' AFTER 'manager';
-- Migration 007: Arquivamento de Usuários (Soft Delete) e Bloqueio de Acesso
-- ==============================================================================

-- 1. Adicionar flag de inativação lógica na tabela pública de usuários
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- 2. Atualizar a Política RLS para garantir que inativos não façam bagunça?
-- Na verdade, a política padrão do app permite Selects/Inserts de autenticados,
-- mas podemos deixar a flag `is_active` governar a UI. O DB não negará leitura, 
-- mas a UI vai chutar ele. Para bloqueio definitivo do Supabase, usaremos a RPC.

-- 3. Função RPC Segura para o Admin alternar o status do funcionário (Arquivar/Desarquivar)
-- Quando arquivamos (is_active = false), nós também cravamos um banimento no auth.users
CREATE OR REPLACE FUNCTION public.admin_toggle_user_status(
  p_target_user_id UUID,
  p_is_active BOOLEAN
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  -- 1. Verifica se quem tá chamando é da Alta Gestão (TI ou Diretor)
  SELECT role_level INTO v_caller_role 
  FROM public.users WHERE id = auth.uid();

  IF v_caller_role NOT IN ('ti_admin', 'director') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas TI ou Diretores podem arquivar contas.';
  END IF;

  -- 2. Não permite que a pessoa se auto-bloqueie por engano
  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode alterar o próprio status de arquivamento.';
  END IF;

  -- 3. Atualiza a flag na nossa tabela pública
  UPDATE public.users SET is_active = p_is_active WHERE id = p_target_user_id;

  -- 4. Atualiza a restrição de login profundo no Supabase Auth
  -- Se p_is_active for FALSE, banimos ele até o ano 3000 (Bloqueio Total).
  -- Se p_is_active for TRUE, tiramos o banimento (NULL).
  IF p_is_active = FALSE THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = p_target_user_id;
  ELSE
    UPDATE auth.users SET banned_until = NULL WHERE id = p_target_user_id;
  END IF;

END;
$$;
-- ============================================================
-- Migration 008: Admin Edit User (Profile Editing Support)
-- ============================================================
-- Este script adiciona uma função RPC segura (SECURITY DEFINER)
-- permitindo que a TI atualize os perfis de outros funcionários
-- (Nome Completo, Filial de Lotação, Cargo e Função) ignorando as 
-- travas do RLS que impedem os usuários de editar uns aos outros.
-- ============================================================

CREATE OR REPLACE FUNCTION admin_update_user(
  p_target_user_id UUID,
  p_full_name TEXT,
  p_branch_id UUID,
  p_role_level TEXT,
  p_job_function TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER -- Executa com os privilégios do criador (bypass RLS)
SET search_path = public
AS $$
DECLARE
  v_caller_role TEXT;
BEGIN
  -- 1. Verificar se quem chama tem permissões administrativas (TI)
  SELECT role_level INTO v_caller_role
  FROM public.users
  WHERE id = auth.uid();

  IF v_caller_role IS DISTINCT FROM 'ti_admin' THEN
    RAISE EXCEPTION 'Acesso negado: Somente Administradores TI podem editar perfis.';
  END IF;

  -- 2. Atualizar o registro do funcionário no esquema public
  UPDATE public.users
  SET 
    full_name = p_full_name,
    branch_id = p_branch_id,
    role_level = p_role_level::user_role_level,
    job_function = p_job_function,
    updated_at = NOW()
  WHERE id = p_target_user_id;

  -- Se o usuário não for encontrado (ex: inativo ou soft deleted),
  -- o UPDATE apenas afetará 0 linhas silenciosamente, o que é seguro.
END;
$$;
-- ============================================================
-- 010: RPC get_chats_with_preview
-- Retorna todos os chats de um usuário com:
-- - Última mensagem (preview)
-- - Contagem de não-lidas (apenas mensagens de OUTROS)
-- - Dados do outro usuário em DMs
-- Executa tudo em UMA ÚNICA query, eliminando N+1.
-- ============================================================

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
    ORDER BY (
      SELECT m2.created_at FROM messages m2
      WHERE m2.chat_id = c.id AND m2.deleted_at IS NULL
      ORDER BY m2.created_at DESC LIMIT 1
    ) DESC NULLS LAST
  ) t;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;
-- ============================================================
-- 011: Índice de Busca Full-Text + RPC de pesquisa
-- Permite pesquisar mensagens de texto em todos os chats do
-- usuário autenticado, retornando contexto e localização.
-- ============================================================

-- Índice GIN para busca rápida em mensagens de texto
CREATE INDEX IF NOT EXISTS idx_messages_content_search
  ON messages USING GIN (to_tsvector('portuguese', COALESCE(content, '')));

-- RPC de busca de mensagens
CREATE OR REPLACE FUNCTION search_messages(p_query TEXT, p_limit INT DEFAULT 30)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT
      m.id,
      m.chat_id,
      m.sender_id,
      m.content,
      m.content_type,
      m.created_at,
      u.full_name AS sender_name,
      COALESCE(c.name, ou.full_name, 'Chat') AS chat_name
    FROM messages m
    JOIN chat_members cm ON cm.chat_id = m.chat_id AND cm.user_id = v_user_id
    JOIN users u ON u.id = m.sender_id
    JOIN chats c ON c.id = m.chat_id
    LEFT JOIN chat_members cm2 ON cm2.chat_id = c.id AND cm2.user_id != v_user_id AND c.type = 'direct'
    LEFT JOIN users ou ON ou.id = cm2.user_id
    WHERE m.deleted_at IS NULL
      AND m.content IS NOT NULL
      AND to_tsvector('portuguese', m.content) @@ plainto_tsquery('portuguese', p_query)
    ORDER BY m.created_at DESC
    LIMIT p_limit
  ) t;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;
-- ============================================================
-- 012: RPCs para Grupos
-- Funções para criar grupo, adicionar/remover membros.
-- ============================================================

-- Cria um grupo com membros iniciais
CREATE OR REPLACE FUNCTION create_group_chat(
  p_name TEXT,
  p_description TEXT DEFAULT NULL,
  p_member_ids UUID[] DEFAULT '{}'::UUID[]
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_chat_id UUID;
  v_member_id UUID;
BEGIN
  -- Cria o chat
  INSERT INTO chats (type, name, description, created_by)
  VALUES ('group', p_name, p_description, v_user_id)
  RETURNING id INTO v_chat_id;

  -- Adiciona o criador como membro
  INSERT INTO chat_members (chat_id, user_id, role)
  VALUES (v_chat_id, v_user_id, 'admin');

  -- Adiciona os membros convidados
  FOREACH v_member_id IN ARRAY p_member_ids LOOP
    IF v_member_id != v_user_id THEN
      INSERT INTO chat_members (chat_id, user_id, role)
      VALUES (v_chat_id, v_member_id, 'member')
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  -- Mensagem de sistema
  INSERT INTO messages (chat_id, sender_id, content, content_type, metadata)
  VALUES (v_chat_id, v_user_id, 'criou o grupo', 'text',
    jsonb_build_object('is_system', true));

  RETURN v_chat_id;
END;
$$;

-- Adiciona um membro ao grupo
CREATE OR REPLACE FUNCTION add_group_member(p_chat_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_chat_type TEXT;
  v_user_role TEXT;
BEGIN
  SELECT type INTO v_chat_type FROM chats WHERE id = p_chat_id;
  IF v_chat_type != 'group' THEN
    RAISE EXCEPTION 'Não é um chat de grupo';
  END IF;

  SELECT role INTO v_user_role FROM chat_members
    WHERE chat_id = p_chat_id AND user_id = v_user_id;
  IF v_user_role IS NULL OR v_user_role != 'admin' THEN
    RAISE EXCEPTION 'Apenas administradores podem adicionar membros';
  END IF;

  INSERT INTO chat_members (chat_id, user_id, role)
  VALUES (p_chat_id, p_user_id, 'member')
  ON CONFLICT DO NOTHING;

  -- Mensagem de sistema
  INSERT INTO messages (chat_id, sender_id, content, content_type, metadata)
  VALUES (p_chat_id, v_user_id,
    'adicionou ' || (SELECT full_name FROM users WHERE id = p_user_id),
    'text', jsonb_build_object('is_system', true));
END;
$$;

-- Remove um membro do grupo
CREATE OR REPLACE FUNCTION remove_group_member(p_chat_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_chat_type TEXT;
  v_user_role TEXT;
BEGIN
  SELECT type INTO v_chat_type FROM chats WHERE id = p_chat_id;
  IF v_chat_type != 'group' THEN
    RAISE EXCEPTION 'Não é um chat de grupo';
  END IF;

  SELECT role INTO v_user_role FROM chat_members
    WHERE chat_id = p_chat_id AND user_id = v_user_id;

  -- Permite se é admin OU se o próprio membro está saindo
  IF v_user_role != 'admin' AND v_user_id != p_user_id THEN
    RAISE EXCEPTION 'Apenas administradores podem remover membros';
  END IF;

  DELETE FROM chat_members
    WHERE chat_id = p_chat_id AND user_id = p_user_id;

  -- Mensagem de sistema
  IF v_user_id = p_user_id THEN
    INSERT INTO messages (chat_id, sender_id, content, content_type, metadata)
    VALUES (p_chat_id, v_user_id, 'saiu do grupo', 'text',
      jsonb_build_object('is_system', true));
  ELSE
    INSERT INTO messages (chat_id, sender_id, content, content_type, metadata)
    VALUES (p_chat_id, v_user_id,
      'removeu ' || (SELECT full_name FROM users WHERE id = p_user_id),
      'text', jsonb_build_object('is_system', true));
  END IF;
END;
$$;
-- ============================================================
-- 013: Correção da Primary Key do chat_members para Streams
-- O Supabase Realtime (PostgresChanges) não lida bem com PKs compostas.
-- Esta migration adiciona um ID único dedicado à sincronização.
-- ============================================================

-- 1. Adicionar uma nova coluna sync_id gerada automaticamente
ALTER TABLE chat_members
ADD COLUMN sync_id UUID DEFAULT gen_random_uuid();

-- 2. Garantir que todo registro futuro tenha esse UUID único
ALTER TABLE chat_members
ADD CONSTRAINT chat_members_sync_id_key UNIQUE (sync_id);

-- Nota: A PK real da tabela continuará sendo (chat_id, user_id) para garantir
-- as FKs e regras de negócio de que um usuário não pode estar 2x no chat.
-- Usaremos o `sync_id` APENAS no filtro `.stream(primaryKey: ['sync_id'])` 
-- do Flutter para evitar crashes do Supabase Client.

