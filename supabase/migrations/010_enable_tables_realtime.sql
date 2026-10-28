-- ==============================================================================
-- Migration 010: Enable Super Realtime
-- Adiciona tabelas essenciais ao supabase_realtime que faltaram na condensação
-- ==============================================================================

BEGIN;

-- 1. Chats (Para atualizar a lista de conversas em tempo real)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'chats'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.chats;
    END IF;
END
$$;

-- 2. Chat Members (Para sincronizar entradas e saídas de canais)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'chat_members'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_members;
    END IF;
END
$$;

-- 3. Message Actions (FUNDAMENTAL para Double Blue Ticks, Enquetes e Cientes)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'message_actions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.message_actions;
    END IF;
END
$$;

-- 4. User Activity History (Histórico em tempo real)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'user_activity_history'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.user_activity_history;
    END IF;
END
$$;

COMMIT;
