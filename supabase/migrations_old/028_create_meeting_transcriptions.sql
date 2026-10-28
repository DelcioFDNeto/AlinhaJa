-- =====================================================
-- Migration 028: Tabela para transcrições de reuniões (IA)
-- =====================================================

CREATE TABLE IF NOT EXISTS public.meeting_transcriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
