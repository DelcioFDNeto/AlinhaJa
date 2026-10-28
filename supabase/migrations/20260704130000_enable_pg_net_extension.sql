-- ============================================================
-- Habilita a extensão pg_net (schema `net`)
-- ============================================================
--
-- Necessária para os triggers de NOTIFICAÇÃO ASSÍNCRONA que usam
-- `net.http_post(...)`:
--   - notify_workflow_function() em workflow_cards (novo card → push)
--   - qualquer webhook de mensagens/canais que dispare Edge Functions
--
-- Sintoma sem a extensão (projeto migrado onde pg_net não foi ativado):
--   INSERT em workflow_cards falha com
--   PostgrestException(message: schema "net" does not exist, code: 3F000)
--
-- pg_net é fire-and-forget: enfileira a requisição e retorna na hora, então o
-- INSERT conclui mesmo que a Edge Function alvo ainda não esteja deployada.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net;
