-- ============================================================
-- Port do Fluxy (20260807190000_fix_triggers_auth_header.sql)
--
-- PROBLEMA
-- O Gateway de Edge Functions do Supabase exige o header
-- `Authorization: Bearer <anon key>` na requisição. Sem ele a chamada
-- é recusada com 401 ("Missing authorization header") ANTES de chegar
-- na função — o `x-webhook-secret` sozinho não basta, porque ele é
-- verificado dentro da função, que nunca executa. Resultado: o bot
-- simplesmente não responde, sem erro visível no app.
--
-- DIFERENÇA EM RELAÇÃO AO FLUXY
-- Lá a anon key entrou hardcoded na função. Aqui não dá: AlinhaJá e
-- Fluxy são projetos Supabase distintos, com chaves distintas, e dev e
-- prod também divergem — a chave literal viajaria errada em pelo menos
-- um ambiente e ficaria versionada no git. Segue-se então o mesmo
-- padrão já usado por `edge_base_url` e `webhook_secret`: leitura do
-- Vault por helper próprio.
--
-- PRÉ-REQUISITO (uma vez por projeto, dev e prod):
--   SELECT vault.create_secret('<anon/publishable key>', 'edge_anon_key');
--
-- Enquanto o segredo não existir, o trigger continua disparando como
-- hoje e apenas registra um WARNING — nada regride.
-- ============================================================

-- ── 1. Helper de leitura da anon key ────────────────────────
CREATE OR REPLACE FUNCTION public.get_edge_anon_key()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_key text;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets
    WHERE name = 'edge_anon_key'
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_key := NULL;
  END;
  RETURN COALESCE(v_key, '');
END;
$$;

REVOKE ALL ON FUNCTION public.get_edge_anon_key() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.get_edge_anon_key() IS
  'Anon/publishable key do projeto, lida do Vault. Usada pelos triggers que chamam Edge Functions (header Authorization exigido pelo Gateway).';

-- ── 2. trg_ai_chatbot com o header Authorization ────────────
-- Mantém tudo que a 20260710180000 já fazia (URL dinâmica por Vault,
-- guard de configuração ausente, branching messages/channel_messages).
CREATE OR REPLACE FUNCTION public.trg_ai_chatbot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_bot uuid := '00000000-0000-4000-a000-000000000001';
  v_base text := public.get_edge_base_url();
  v_anon text := public.get_edge_anon_key();
  v_url text;
  v_headers jsonb;
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

  v_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'x-webhook-secret', public.get_webhook_secret()
  );

  -- Sem a chave no Vault, dispara como antes e avisa: o comportamento
  -- não piora, e o WARNING diz exatamente o que configurar.
  IF v_anon = '' THEN
    RAISE WARNING 'edge_anon_key não configurada no Vault — chamada ao ai-chatbot sairá sem Authorization e o Gateway deve recusar com 401';
  ELSE
    v_headers := v_headers || jsonb_build_object('Authorization', 'Bearer ' || v_anon);
  END IF;

  PERFORM net.http_post(
    url := v_url,
    headers := v_headers,
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
