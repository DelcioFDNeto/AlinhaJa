-- ==============================================================================
-- Migration 008: Tabela de Histórico de Atividades
-- Restaura a tabela user_activity_history que foi perdida na condensação
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.user_activity_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL,
    description TEXT,
    target_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.user_activity_history ENABLE ROW LEVEL SECURITY;

-- Usuários só veem seu próprio histórico
CREATE POLICY "Users can view their own activity history" 
ON public.user_activity_history FOR SELECT 
TO authenticated
USING (user_id = auth.uid());

-- Triggers para popular o histórico
-- 1. Criação de chats
CREATE OR REPLACE FUNCTION log_chat_creation()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.created_by IS NOT NULL THEN
        INSERT INTO public.user_activity_history (user_id, activity_type, description, target_name)
        VALUES (NEW.created_by, 'chat_created', 'Criou um novo chat', NEW.name);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_chat_created_log
AFTER INSERT ON public.chats
FOR EACH ROW EXECUTE FUNCTION log_chat_creation();

-- 2. Entrou em canal (membro)
CREATE OR REPLACE FUNCTION log_channel_join()
RETURNS TRIGGER AS $$
DECLARE
    v_chat_name TEXT;
BEGIN
    IF NEW.user_id IS NOT NULL THEN
        SELECT name INTO v_chat_name FROM public.chats WHERE id = NEW.chat_id;
        INSERT INTO public.user_activity_history (user_id, activity_type, description, target_name)
        VALUES (NEW.user_id, 'channel_joined', 'Ingressou na sala', v_chat_name);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_chat_member_joined_log
AFTER INSERT ON public.chat_members
FOR EACH ROW EXECUTE FUNCTION log_channel_join();
