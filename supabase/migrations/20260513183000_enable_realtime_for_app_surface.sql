-- Garante que as superficies principais do app estejam no Supabase Realtime.
-- Idempotente para bancos que ja receberam parte dessas publicacoes em migrations antigas.

DO $$
DECLARE
  table_name text;
  realtime_tables text[] := ARRAY[
    'messages',
    'message_actions',
    'chat_members',
    'chats',
    'channels',
    'channel_members',
    'channel_messages',
    'workflow_cards',
    'workflow_card_comments',
    'workflow_card_history',
    'workflow_status_config',
    'support_tickets',
    'support_ticket_messages',
    'calls',
    'meetings',
    'users',
    'branches',
    'departments',
    'job_positions',
    'user_locations',
    'user_activity_history'
  ];
BEGIN
  FOREACH table_name IN ARRAY realtime_tables
  LOOP
    IF to_regclass(format('public.%I', table_name)) IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = table_name
      )
    THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', table_name);
    END IF;
  END LOOP;
END $$;
