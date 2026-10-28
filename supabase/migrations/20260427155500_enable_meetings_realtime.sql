-- ==============================================================================
-- FIX: Adicionar tabela 'meetings' ao Supabase Realtime
-- ==============================================================================
-- A tabela meetings nunca foi adicionada à publicação supabase_realtime,
-- o que impedia que clients web recebessem eventos de videochamada/reunião.
-- ==============================================================================

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'meetings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.meetings;
    RAISE NOTICE 'meetings adicionada ao supabase_realtime';
  ELSE
    RAISE NOTICE 'meetings já estava no supabase_realtime';
  END IF;
END $$;
