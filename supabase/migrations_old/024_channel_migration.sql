-- ======================================================================================
-- MIGRATION: SEPARAÇÃO ARQUITETURAL DOS CANAIS (PHASE 11)
-- ======================================================================================
-- Este script cria um ecossistema independente para os Canais da Empresa,
-- isolando o tráfego pesado de workflows das tabelas normais de DMs e Grupos (`chats` e `messages`).

-- 1. TABELA DE CANAIS
CREATE TABLE IF NOT EXISTS public.channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    type TEXT DEFAULT 'comum', -- 'comum', 'avisos', 'operacional'
    last_message_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- 2. TABELA DE MEMBROS E PERMISSÕES DO CANAL
CREATE TABLE IF NOT EXISTS public.channel_members (
    channel_id UUID REFERENCES public.channels(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'viewer', -- 'admin', 'editor', 'viewer'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    PRIMARY KEY (channel_id, user_id)
);

-- 3. TABELA DE MENSAGENS E THREADS DOS CANAIS
CREATE TABLE IF NOT EXISTS public.channel_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id UUID REFERENCES public.channels(id) ON DELETE CASCADE NOT NULL,
    sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    content TEXT,
    content_type TEXT DEFAULT 'text',
    media_url TEXT,
    local_file_path TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    is_bot BOOLEAN DEFAULT false,
    is_system BOOLEAN DEFAULT false,
    read_by UUID[] DEFAULT '{}'::uuid[],
    
    -- Motor de Threads e Respostas Isolado!
    thread_id UUID REFERENCES public.channel_messages(id) ON DELETE CASCADE,
    reply_to UUID REFERENCES public.channel_messages(id) ON DELETE SET NULL,
    thread_reply_count INT DEFAULT 0,
    
    deleted_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ======================================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ======================================================================================

ALTER TABLE public.channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_messages ENABLE ROW LEVEL SECURITY;

-- Canais: Visíveis apenas para membros
CREATE POLICY "Membros podem ver canais" ON public.channels
FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.channel_members WHERE channel_id = id AND user_id = auth.uid())
);

-- Membros: Todos do canal podem ver outros membros
CREATE POLICY "Ver membros do mesmo canal" ON public.channel_members
FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.channel_members cm WHERE cm.channel_id = channel_id AND cm.user_id = auth.uid())
);

-- Mensagens: Ver mensagens do canal
CREATE POLICY "Membros veem mensagens" ON public.channel_messages
FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.channel_members WHERE channel_id = public.channel_messages.channel_id AND user_id = auth.uid())
);

-- Mensagens: Enviar (Verifica restrição no Backend se necessário, mas por padrão aberto para membros)
CREATE POLICY "Membros enviam mensagens" ON public.channel_messages
FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.channel_members WHERE channel_id = public.channel_messages.channel_id AND user_id = auth.uid())
);

-- ======================================================================================
-- TRIGGERS DE THREADS E OTIMIZAÇÕES
-- ======================================================================================

-- Contagem de Tópicos
CREATE OR REPLACE FUNCTION increment_channel_thread_reply()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.thread_id IS NOT NULL THEN
    UPDATE public.channel_messages
    SET thread_reply_count = thread_reply_count + 1
    WHERE id = NEW.thread_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_channel_thread_reply
AFTER INSERT ON public.channel_messages
FOR EACH ROW EXECUTE FUNCTION increment_channel_thread_reply();

CREATE OR REPLACE FUNCTION decrement_channel_thread_reply()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.thread_id IS NOT NULL THEN
    UPDATE public.channel_messages
    SET thread_reply_count = GREATEST(thread_reply_count - 1, 0)
    WHERE id = OLD.thread_id;
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_channel_thread_reply_del
AFTER UPDATE OF deleted_at ON public.channel_messages
FOR EACH ROW WHEN (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)
EXECUTE FUNCTION decrement_channel_thread_reply();

-- Atualiza 'last_message_at' do Canal
CREATE OR REPLACE FUNCTION update_channel_last_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.channels
  SET last_message_at = NEW.created_at
  WHERE id = NEW.channel_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_channel_message_insert
AFTER INSERT ON public.channel_messages
FOR EACH ROW EXECUTE FUNCTION update_channel_last_message();

-- FIM DA MIGRATION
