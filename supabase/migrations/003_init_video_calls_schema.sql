-- CONSOLIDATED MIGRATIONS 021 to 031

-- =====================================================
-- Migration 022: Adicionar 'meeting' ao enum content_type
-- =====================================================
-- O tipo content_type original não inclui 'meeting',
-- impedindo a inserção/consulta de mensagens de reunião.

ALTER TYPE content_type ADD VALUE IF NOT EXISTS 'meeting';
-- ==============================================================================
-- 022: Correção do Motor de Threads e Limpeza Geral
-- 1. Limpa mensagens antigas corrompidas e inconsistentes.
-- 2. Adiciona a coluna 'thread_reply_count' na tabela messages.
-- 3. Cria os triggers para incrementar/decrementar quando existirem respostas.
-- ==============================================================================

-- 1. Limpar todas as mensagens do banco (Ação irreversível)
DELETE FROM public.messages;

-- 2. Adicionar a coluna que o App Flutter está tentando ler
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS thread_reply_count INT DEFAULT 0;

-- 3. Função para incrementar a contagem quando alguém responder
CREATE OR REPLACE FUNCTION increment_thread_reply_count()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.thread_id IS NOT NULL THEN
    UPDATE public.messages
    SET thread_reply_count = thread_reply_count + 1
    WHERE id = NEW.thread_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger de Inserção (Quando uma nova resposta é enviada)
DROP TRIGGER IF EXISTS on_thread_reply ON public.messages;
CREATE TRIGGER on_thread_reply
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION increment_thread_reply_count();

-- 4. Função para decrementar a contagem quando uma resposta for apagada logicamente
CREATE OR REPLACE FUNCTION decrement_thread_reply_count()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.thread_id IS NOT NULL THEN
    UPDATE public.messages
    SET thread_reply_count = GREATEST(thread_reply_count - 1, 0)
    WHERE id = OLD.thread_id;
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Trigger de Exclusão Lógica (Quando deleted_at é preenchido na resposta)
DROP TRIGGER IF EXISTS on_thread_reply_delete ON public.messages;
CREATE TRIGGER on_thread_reply_delete
AFTER UPDATE OF deleted_at ON public.messages
FOR EACH ROW
WHEN (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)
EXECUTE FUNCTION decrement_thread_reply_count();

-- Concluído! O banco de dados agora possui o motor de Threads totalmente automatizado.
-- Enumeração do tipo e status da chamada
CREATE TYPE call_type AS ENUM ('audio', 'video');
CREATE TYPE call_status AS ENUM ('ringing', 'in_progress', 'ended', 'missed', 'rejected');

-- Tabela principal de Chamadas
CREATE TABLE calls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    caller_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type call_type NOT NULL DEFAULT 'audio',
    status call_status NOT NULL DEFAULT 'ringing',
    provider_room_id VARCHAR(255), -- ID de sessão na Agora.io
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ativar RLS
ALTER TABLE calls ENABLE ROW LEVEL SECURITY;

-- Políticas de RLS
-- Permite que usuários visualizem as chamadas dos chats dos quais participam
CREATE POLICY "Membros do chat podem ver o histórico de chamadas" 
ON calls FOR SELECT 
TO authenticated 
USING (
    EXISTS (
        SELECT 1 FROM chat_members 
        WHERE chat_members.chat_id = calls.chat_id 
        AND chat_members.user_id = auth.uid()
    )
);

-- Permite que usuários iniciem/atualizem chamadas (ex: aceitar, rejeitar) se estiverem no chat
CREATE POLICY "Membros do chat podem criar e atualizar chamadas" 
ON calls FOR ALL 
TO authenticated 
USING (
    EXISTS (
        SELECT 1 FROM chat_members 
        WHERE chat_members.chat_id = calls.chat_id 
        AND chat_members.user_id = auth.uid()
    )
);
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
-- ============================================================
-- Migration 025: RPC para Rejeição de Cadastro de Usuário
-- ============================================================
-- Permite que ti_admin rejeite um cadastro pendente,
-- removendo o registro de public.users e auth.users.
-- SECURITY DEFINER bypassa RLS.
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_reject_user(
  p_target_user_id UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  -- 1. Verificar se quem chama é ti_admin
  SELECT role_level INTO v_caller_role
  FROM public.users
  WHERE id = auth.uid();

  IF v_caller_role IS DISTINCT FROM 'ti_admin' THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas a TI pode rejeitar cadastros.';
  END IF;

  -- 2. Não permite rejeitar a si mesmo
  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode rejeitar seu próprio cadastro.';
  END IF;

  -- 3. Deletar de auth.users (o CASCADE cuida de public.users automaticamente)
  DELETE FROM auth.users WHERE id = p_target_user_id;
END;
$$;
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
-- =====================================================
-- Migration 027: Criar tabela meetings para videoconferência
-- =====================================================

-- Verifica se a tabela já existe e adiciona colunas faltantes
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'meetings') THEN
        CREATE TABLE public.meetings (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            room_id TEXT NOT NULL UNIQUE,
            host_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
            title TEXT,
            started_at TIMESTAMP WITH TIME ZONE,
            ended_at TIMESTAMP WITH TIME ZONE,
            is_recording BOOLEAN DEFAULT false,
            recording_url TEXT,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    ELSE
        -- Adicionar colunas se não existirem
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'meetings' AND column_name = 'room_id') THEN
            ALTER TABLE public.meetings ADD COLUMN room_id TEXT NOT NULL UNIQUE;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'meetings' AND column_name = 'host_id') THEN
            ALTER TABLE public.meetings ADD COLUMN host_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'meetings' AND column_name = 'title') THEN
            ALTER TABLE public.meetings ADD COLUMN title TEXT;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'meetings' AND column_name = 'started_at') THEN
            ALTER TABLE public.meetings ADD COLUMN started_at TIMESTAMP WITH TIME ZONE;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'meetings' AND column_name = 'ended_at') THEN
            ALTER TABLE public.meetings ADD COLUMN ended_at TIMESTAMP WITH TIME ZONE;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'meetings' AND column_name = 'is_recording') THEN
            ALTER TABLE public.meetings ADD COLUMN is_recording BOOLEAN DEFAULT false;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'meetings' AND column_name = 'recording_url') THEN
            ALTER TABLE public.meetings ADD COLUMN recording_url TEXT;
        END IF;
    END IF;
END $$;

ALTER TABLE public.meetings ENABLE ROW LEVEL SECURITY;

-- Policies RLS (drop se existirem para evitar erro)
DROP POLICY IF EXISTS "Users can view meetings of their chats" ON public.meetings;
DROP POLICY IF EXISTS "Users can create meetings" ON public.meetings;
DROP POLICY IF EXISTS "Host can update meetings" ON public.meetings;

-- Policy de leitura: membros do chat relacionado podem ver
CREATE POLICY "Users can view meetings of their chats" 
ON public.meetings FOR SELECT 
USING (
    room_id IN (
        SELECT CONCAT('call_', id)::text FROM public.chats 
        WHERE id IN (
            SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
        )
    )
    OR host_id = auth.uid()
);

-- Policy de inserção: qualquer usuário logado pode criar
CREATE POLICY "Users can create meetings" 
ON public.meetings FOR INSERT 
WITH CHECK (host_id = auth.uid());

-- Policy de update: só o host pode atualizar
CREATE POLICY "Host can update meetings" 
ON public.meetings FOR UPDATE 
USING (host_id = auth.uid());
-- =====================================================
-- Migration 028: Tabela para transcrições de reuniões (IA)
-- =====================================================

CREATE TABLE IF NOT EXISTS public.meeting_transcriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id UUID NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    content TEXT NOT NULL,
    language TEXT DEFAULT 'pt-BR',
    confidence FLOAT,
    is_final BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.meeting_transcriptions ENABLE ROW LEVEL SECURITY;

-- Policy: apenas participantes da reunião
CREATE POLICY "Users can view transcriptions of their meetings" 
ON public.meeting_transcriptions FOR SELECT 
USING (
    meeting_id IN (
        SELECT id FROM public.meetings 
        WHERE host_id = auth.uid()
        OR room_id IN (
            SELECT CONCAT('call_', id)::text FROM public.chats 
            WHERE id IN (
                SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
            )
        )
    )
);

-- Policy: qualquer usuário pode inserir (via N8N/webhook)
CREATE POLICY "Service can insert transcriptions" 
ON public.meeting_transcriptions FOR INSERT 
WITH CHECK (true);

-- Policy: host pode atualizar
CREATE POLICY "Host can update transcriptions" 
ON public.meeting_transcriptions FOR UPDATE 
USING (
    meeting_id IN (
        SELECT id FROM public.meetings WHERE host_id = auth.uid()
    )
);
-- =====================================================
-- Migration 029: Trigger para notificar N8N quando reunião termina
-- =====================================================

-- Função que dispara webhook quando status da chamada muda para 'ended'
CREATE OR REPLACE FUNCTION public.notify_meeting_ended()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'ended' AND OLD.status != 'ended' THEN
        PERFORM pg_notify(
            'meeting_ended',
            json_build_object(
                'call_id', NEW.id,
                'chat_id', NEW.chat_id,
                'caller_id', NEW.caller_id,
                'type', NEW.type,
                'started_at', NEW.started_at,
                'ended_at', NEW.ended_at,
                'duration', EXTRACT(EPOCH FROM (NEW.ended_at - NEW.started_at))
            )::text
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Criar trigger na tabela calls
DROP TRIGGER IF EXISTS trigger_meeting_ended ON public.calls;
CREATE TRIGGER trigger_meeting_ended
    AFTER UPDATE ON public.calls
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_meeting_ended();
-- =====================================================
-- Migration 030: Adicionar campos de chamada na tabela meetings
-- Necessário para separar videochamadas de chamadas de áudio
-- =====================================================

-- Adicionar coluna chat_id para linkar com o chat
ALTER TABLE public.meetings 
ADD COLUMN IF NOT EXISTS chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE;

-- Adicionar coluna caller_id para identificar quem iniciou
ALTER TABLE public.meetings 
ADD COLUMN IF NOT EXISTS caller_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- Adicionar coluna de status
ALTER TABLE public.meetings 
ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'ringing';

-- Criar índice para melhorar performance nas queries
CREATE INDEX IF NOT EXISTS idx_meetings_chat_id ON public.meetings(chat_id);
CREATE INDEX IF NOT EXISTS idx_meetings_caller_id ON public.meetings(caller_id);
CREATE INDEX IF NOT EXISTS idx_meetings_status ON public.meetings(status);

-- Atualizar RLS para permitir que membros do chat vejam as videochamadas
DROP POLICY IF EXISTS "Members can view video meetings of their chats" ON public.meetings;

CREATE POLICY "Members can view video meetings of their chats" 
ON public.meetings FOR SELECT 
USING (
    -- Membros do chat podem ver
    chat_id IN (
        SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
    )
    OR host_id = auth.uid()
    OR caller_id = auth.uid()
);

-- Policy de update para participantes
DROP POLICY IF EXISTS "Participants can update video meetings" ON public.meetings;

CREATE POLICY "Participants can update video meetings" 
ON public.meetings FOR UPDATE 
USING (
    chat_id IN (
        SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
    )
    OR host_id = auth.uid()
    OR caller_id = auth.uid()
);
-- =====================================================
-- Migration 031: Adicionar coluna audio_url para gravação de chamadas
-- =====================================================

-- Adicionar coluna audio_url na tabela calls
ALTER TABLE public.calls 
ADD COLUMN IF NOT EXISTS audio_url TEXT;

-- Adicionar coluna audio_url na tabela meetings
ALTER TABLE public.meetings 
ADD COLUMN IF NOT EXISTS audio_url TEXT;

-- Criar índices para performance
CREATE INDEX IF NOT EXISTS idx_calls_audio_url ON public.calls(audio_url);
CREATE INDEX IF NOT EXISTS idx_meetings_audio_url ON public.meetings(audio_url);

