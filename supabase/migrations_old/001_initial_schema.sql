-- ============================================================
-- Chat BySabel — Schema completo para Supabase
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
  -- Campos de integração futura com OS BySabel
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
  INSERT INTO public.users (id, full_name, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL)
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
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  type        chat_type NOT NULL DEFAULT 'direct',
  name        TEXT,
  description TEXT,
  avatar_url  TEXT,
  created_by  UUID REFERENCES users(id),
  -- Campo extensível para integração com OS BySabel
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
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
CREATE POLICY "Membros veem o chat"
  ON chats FOR SELECT
  USING (public.is_chat_member(id));
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
