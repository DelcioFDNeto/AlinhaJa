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
