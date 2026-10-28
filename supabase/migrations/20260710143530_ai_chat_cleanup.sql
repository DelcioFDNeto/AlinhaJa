-- Migration: Preparação para exclusão física de histórico de IA e Limpeza Periódica

-- 1. Alterar a chave estrangeira reply_to da tabela messages para ON DELETE SET NULL
--    Isso impede que o banco trave ao tentar apagar uma mensagem que foi respondida.
DO $$
DECLARE
    row record;
BEGIN
    FOR row IN
        SELECT tc.constraint_name
        FROM information_schema.table_constraints AS tc
        JOIN information_schema.key_column_usage AS kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_name = 'messages' 
          AND tc.constraint_type = 'FOREIGN KEY' 
          AND kcu.column_name = 'reply_to'
    LOOP
        EXECUTE 'ALTER TABLE public.messages DROP CONSTRAINT ' || quote_ident(row.constraint_name);
    END LOOP;
END;
$$;

ALTER TABLE public.messages 
  ADD CONSTRAINT messages_reply_to_fkey 
  FOREIGN KEY (reply_to) 
  REFERENCES public.messages(id) 
  ON DELETE SET NULL;


-- 2. Ativar e configurar o pg_cron
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Tenta remover o job caso ele já exista para evitar duplicatas (ignora erro se não existir)
DO $$
BEGIN
    PERFORM cron.unschedule('ai_chatbot_cleanup_job');
EXCEPTION WHEN others THEN
    -- Ignorar erro caso o job não exista
END;
$$;

-- 3. Criar a rotina diária (toda madrugada às 03:00) para limpar mensagens antigas
-- Apaga fisicamente mensagens mais velhas que 7 dias apenas em DMs com o Assistente IA
SELECT cron.schedule(
    'ai_chatbot_cleanup_job',
    '0 3 * * *',
    $$
    DELETE FROM public.messages
    WHERE created_at < NOW() - INTERVAL '7 days'
      AND chat_id IN (
        SELECT c.id 
        FROM public.chats c
        JOIN public.chat_members cm ON cm.chat_id = c.id
        WHERE c.type = 'direct' 
          AND cm.user_id = '00000000-0000-4000-a000-000000000001'
      );
    $$
);