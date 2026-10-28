CREATE OR REPLACE FUNCTION public.trg_ai_chatbot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_bot uuid := '00000000-0000-4000-a000-000000000001';
  v_url text := 'https://gpeemngsxvqjflasdody.supabase.co/functions/v1/ai-chatbot';
BEGIN
  -- Nunca reage às próprias mensagens (evita loop) nem a apagadas.
  IF NEW.sender_id = v_bot OR NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Só desperta a Edge Function se o bot participar deste chat/canal.
  IF TG_TABLE_NAME = 'messages' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.chat_members
      WHERE chat_id = NEW.chat_id AND user_id = v_bot
    ) THEN
      RETURN NEW;
    END IF;
  ELSIF TG_TABLE_NAME = 'channel_messages' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.channel_members
      WHERE channel_id = NEW.channel_id AND user_id = v_bot
    ) THEN
      RETURN NEW;
    END IF;
  END IF;

  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.get_webhook_secret()
    ),
    body := jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'record', row_to_json(NEW)
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ai_chatbot ON public.messages;
CREATE TRIGGER trg_ai_chatbot
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.trg_ai_chatbot();

DROP TRIGGER IF EXISTS trg_ai_chatbot ON public.channel_messages;
CREATE TRIGGER trg_ai_chatbot
  AFTER INSERT ON public.channel_messages
  FOR EACH ROW EXECUTE FUNCTION public.trg_ai_chatbot();
