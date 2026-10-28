-- Envia secret compartilhado (x-webhook-secret) nos webhooks de notificação,
-- permitindo que as Edge Functions rejeitem chamadas forjadas.
--
-- O secret é lido do Supabase Vault (nunca fica no repositório). Provisionar com:
--   SELECT vault.create_secret('<valor forte>', 'webhook_secret');
-- e configurar o mesmo valor nas secrets das Edge Functions:
--   npx supabase secrets set WEBHOOK_SECRET=<valor forte>
--
-- Enquanto o secret não existir no Vault, o header vai vazio e as functions
-- (em modo compatibilidade) apenas registram warning — nada quebra.

CREATE OR REPLACE FUNCTION public.get_webhook_secret()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_secret text;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'webhook_secret'
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;
  RETURN COALESCE(v_secret, '');
END;
$$;

REVOKE ALL ON FUNCTION public.get_webhook_secret() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_webhook_secret() FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_workflow_function()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_url text := 'https://gpeemngsxvqjflasdody.supabase.co/functions/v1/send-workflow-notification';
BEGIN
  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.get_webhook_secret()
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
