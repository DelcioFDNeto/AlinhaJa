-- Enable Realtime for meeting_transcriptions
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'meeting_transcriptions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.meeting_transcriptions;
    END IF;
END $$;
