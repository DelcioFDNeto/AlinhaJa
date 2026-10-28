-- ============================================================
-- Versiona os triggers de push de mensagens (DM, grupo e canal)
--
-- CONTEXTO
-- A função `notify_chat_function()` (corrigida em 20260915190000) é disparada
-- a cada mensagem, mas os triggers que a chamam foram criados direto no banco
-- de produção e nunca entraram numa migration. Um ambiente recriado a partir
-- do repositório ficava sem nenhuma notificação de mensagem.
--
-- IDEMPOTÊNCIA — POR QUE NÃO É UM CREATE TRIGGER SIMPLES
-- Em produção o trigger já existe, com nome desconhecido e possivelmente como
-- "Database Webhook" do painel (supabase_functions.http_request). Criar um
-- segundo faria cada mensagem gerar DUAS notificações. Por isso o trigger só é
-- criado quando nenhum trigger da tabela já leva à send-chat-notification —
-- seja chamando notify_chat_function, seja passando a URL como argumento,
-- seja por outra função cujo corpo cite a Edge Function.
-- ============================================================

DO $do$
DECLARE
  v_table TEXT;
  v_exists BOOLEAN;
BEGIN
  IF to_regprocedure('public.notify_chat_function()') IS NULL THEN
    RAISE NOTICE 'notify_chat_function() não existe — triggers de push não criados.';
    RETURN;
  END IF;

  FOREACH v_table IN ARRAY ARRAY['messages', 'channel_messages'] LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN
      CONTINUE;
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM pg_trigger t
      JOIN pg_proc p ON p.oid = t.tgfoid
      WHERE t.tgrelid = ('public.' || v_table)::regclass
        AND NOT t.tgisinternal
        AND (
          p.proname = 'notify_chat_function'
          OR p.prosrc ILIKE '%send-chat-notification%'
          OR encode(t.tgargs, 'escape') ILIKE '%send-chat-notification%'
        )
    ) INTO v_exists;

    IF v_exists THEN
      RAISE NOTICE 'public.%: trigger de push já existe — mantido.', v_table;
    ELSE
      EXECUTE format(
        'CREATE TRIGGER trg_notify_chat_push
           AFTER INSERT ON public.%I
           FOR EACH ROW EXECUTE FUNCTION public.notify_chat_function()',
        v_table
      );
      RAISE NOTICE 'public.%: trigger trg_notify_chat_push criado.', v_table;
    END IF;
  END LOOP;
END
$do$;
