-- Corrige a URL hardcoded no trigger do chatbot da IA para usar a URL do ambiente atual (DEV/PROD)
CREATE OR REPLACE FUNCTION public.trg_ai_chatbot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_bot uuid := '00000000-0000-4000-a000-000000000001';
  v_base text := public.get_edge_base_url();
  v_url text;
BEGIN
  IF v_base = '' THEN
    RAISE WARNING 'edge_base_url não configurada no Vault — chatbot não disparado';
    RETURN NEW;
  END IF;

  v_url := v_base || '/functions/v1/ai-chatbot';

  IF NEW.sender_id = v_bot OR NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.chat_members
    WHERE chat_id = NEW.chat_id AND user_id = v_bot
  ) THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.get_webhook_secret()
    ),
    body := jsonb_build_object(
      'type', TG_OP,
      'record', row_to_json(NEW)
    )
  );
  RETURN NEW;
END;
$function$;
