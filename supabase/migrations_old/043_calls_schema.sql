-- 1. DELETA A TABELA ANTIGA INCOMPLETA QUE ESTÁ CAUSANDO O BUG
DROP TABLE IF EXISTS public.calls;

-- 2. Cria a tabela 'calls' do zero, com todas as conexões (Foreign Keys) corretas
CREATE TABLE public.calls (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
    caller_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT 'audio', -- 'audio' ou 'video'
    status TEXT NOT NULL DEFAULT 'ringing', -- 'ringing', 'in_progress', 'ended', 'missed', 'rejected'
    provider_room_id TEXT, -- Nome do canal gerado para o provedor de mídia da Agora
    started_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Habilita o Realtime nessa tabela para o Flutter conseguir capturar os toques (ringing)
ALTER PUBLICATION supabase_realtime ADD TABLE public.calls;

-- 3. Habilita a Segurança por Nível de Linha (RLS)
ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;

-- 4. Criação da Política de Leitura (SELECT)
-- O usuário só pode ver e escutar chamadas que pertencem a chats que ele participa
CREATE POLICY "Users can view calls of their chats" 
ON public.calls FOR SELECT 
USING (
    chat_id IN (
        SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
    )
);

-- 5. Criação da Política de Inserção (INSERT)
-- O usuário pode criar chamadas se for membro do chat e ele for o caller_id
CREATE POLICY "Users can create calls in their chats" 
ON public.calls FOR INSERT 
WITH CHECK (
    caller_id = auth.uid() 
    AND 
    chat_id IN (
        SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
    )
);

-- 6. Criação da Política de Atualização (UPDATE)
-- O usuário pode atualizar status da chamada se for membro do chat
CREATE POLICY "Users can update calls of their chats" 
ON public.calls FOR UPDATE 
USING (
    chat_id IN (
        SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
    )
);
