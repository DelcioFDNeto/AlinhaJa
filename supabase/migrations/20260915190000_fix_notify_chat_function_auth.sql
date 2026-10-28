-- ============================================================
-- Fix: notify_chat_function() — autenticação incompatível (401)
--
-- CONTEXTO
-- A função `notify_chat_function()` foi criada antes do sistema de
-- webhook secret e usa `Authorization: Bearer <anon_key>` para chamar
-- a Edge Function `send-chat-notification`. Porém:
--   1. A Edge Function tem `verify_jwt: true` no gateway.
--   2. A anon_key NÃO é um JWT de sessão válido.
--   3. O gateway rejeita com 401 ANTES de a função executar.
--   4. A Edge Function internamente valida via `x-webhook-secret`.
--
-- A migration 20260703120000 corrigiu `notify_workflow_function()` mas
-- esqueceu de atualizar `notify_chat_function()` — que é o trigger
-- mais crítico (disparado em cada mensagem de DM, grupo e canal).
--
-- CORREÇÃO
-- 1. Substituir `Authorization: Bearer` por `x-webhook-secret` (Vault).
-- 2. Re-deploy da Edge Function com `--no-verify-jwt` (feito em paralelo):
--      npx supabase functions deploy send-chat-notification --no-verify-jwt
-- ============================================================

CREATE OR REPLACE FUNCTION public.notify_chat_function()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_url text := 'https://gpeemngsxvqjflasdody.supabase.co/functions/v1/send-chat-notification';
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
      'record', row_to_json(NEW)
    )
  );
  RETURN NEW;
END;
$function$;
