-- ============================================================
-- Corrige regressão: a migration 20260710160500 (suporte a canais)
-- reintroduziu a URL HARDCODED do projeto de produção no trigger do
-- chatbot, desfazendo o fix dinâmico de 20260710160002. Isso quebra a
-- separação DEV/PROD: no ambiente cujo ref difere do hardcoded, o
-- trigger dispara a Edge Function do projeto errado e o bot nunca
-- responde.
--
-- Esta migration reúne as DUAS correções de uma vez:
--   • URL dinâmica por ambiente via public.get_edge_base_url() (Vault),
--     com guard quando não configurada (RAISE WARNING, não dispara);
--   • branching de tabela (messages + channel_messages) para o suporte
--     a canais introduzido em 20260710160500.
-- ============================================================
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
$function$;

DROP TRIGGER IF EXISTS trg_ai_chatbot ON public.messages;
CREATE TRIGGER trg_ai_chatbot
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.trg_ai_chatbot();

DROP TRIGGER IF EXISTS trg_ai_chatbot ON public.channel_messages;
CREATE TRIGGER trg_ai_chatbot
  AFTER INSERT ON public.channel_messages
  FOR EACH ROW EXECUTE FUNCTION public.trg_ai_chatbot();
