-- =====================================================
-- Migration 029: Trigger para notificar N8N quando reunião termina
-- =====================================================

-- Função que dispara webhook quando status da chamada muda para 'ended'
CREATE OR REPLACE FUNCTION public.notify_meeting_ended()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'ended' AND OLD.status != 'ended' THEN
        PERFORM pg_notify(
            'meeting_ended',
            json_build_object(
                'call_id', NEW.id,
                'chat_id', NEW.chat_id,
                'caller_id', NEW.caller_id,
                'type', NEW.type,
                'started_at', NEW.started_at,
                'ended_at', NEW.ended_at,
                'duration', EXTRACT(EPOCH FROM (NEW.ended_at - NEW.started_at))
            )::text
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Criar trigger na tabela calls
DROP TRIGGER IF EXISTS trigger_meeting_ended ON public.calls;
CREATE TRIGGER trigger_meeting_ended
    AFTER UPDATE ON public.calls
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_meeting_ended();
