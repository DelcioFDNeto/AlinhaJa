-- =====================================================
-- Migration 027: Criar tabela meetings para videoconferência
-- =====================================================

-- Verifica se a tabela já existe e adiciona colunas faltantes
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'meetings') THEN
        CREATE TABLE public.meetings (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
