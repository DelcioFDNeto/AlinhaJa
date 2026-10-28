-- ==============================================================================
-- RESET OPERACIONAL - Limpa TODOS os dados transacionais preservando usuários
-- ==============================================================================
-- LEGADO: para execucao manual atual, prefira:
--   supabase/scripts/reset_and_seed_operational_data.sql
-- A fonte unica atual e a migration 20260512180000_unified_workflow_channel_seed.sql.
-- ==============================================================================
-- Limpa: mensagens, canais, cards, reuniões, chamadas, notificações, tickets
-- Preserva: auth.users, auth.identities, public.users, departments, job_positions
-- ==============================================================================

DO $$
DECLARE
  t TEXT;
  tables_to_truncate TEXT[] := ARRAY[
    'workflow_card_comments',
    'workflow_card_history',
    'workflow_status_config',
    'workflow_cards',
    'message_reactions',
    'announcement_acks',
    'poll_votes',
    'message_read_status',
    'messages',
    'chat_members',
    'chats',
    'calls',
    'meetings',
    'notifications',
    'it_support_tickets',
    'user_activities',
    'user_locations',
    'fcm_tokens'
  ];
BEGIN
  FOREACH t IN ARRAY tables_to_truncate
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t) THEN
      EXECUTE format('TRUNCATE TABLE public.%I CASCADE', t);
      RAISE NOTICE 'Truncated: %', t;
    ELSE
      RAISE NOTICE 'Skipped (not found): %', t;
    END IF;
  END LOOP;
END $$;

-- ==============================================================================
-- FIM - Todos os dados transacionais foram limpos.
-- Usuários e estrutura organizacional (departments, job_positions) preservados.
-- ==============================================================================
