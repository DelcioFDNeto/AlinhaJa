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
