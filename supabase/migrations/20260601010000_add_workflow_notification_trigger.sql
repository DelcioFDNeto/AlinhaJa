-- Adiciona trigger e função para notificação assíncrona de alterações em workflow_cards
CREATE OR REPLACE FUNCTION public.notify_workflow_function()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_url text := 'https://hzvmqsgpopgfkvdxyain.supabase.co/functions/v1/send-workflow-notification';
  v_anon_key text := 'sb_publishable_7Vhf6Dw1Hvb4kkI1DaCMzw_gspYnCgx';
BEGIN
  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon_key
    ),
    body := jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW),
      'old_record', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE null END
    )
  );
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER trigger_workflow_notification
  AFTER INSERT OR UPDATE ON public.workflow_cards
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_workflow_function();
