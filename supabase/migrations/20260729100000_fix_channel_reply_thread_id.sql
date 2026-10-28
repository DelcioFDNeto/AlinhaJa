-- Corrige mensagens de canal que viraram resposta de tópico por engano.
--
-- O app gravava `thread_id = reply_to` ao responder uma mensagem na régua
-- principal do canal. Com a régua agora filtrando `thread_id IS NULL`, essas
-- mensagens sumiriam da conversa e apareceriam como respostas de um tópico que
-- ninguém abriu. O padrão é identificável com precisão: thread_id igual ao
-- reply_to. Respostas legítimas de tópico apontam para a mensagem raiz e não
-- necessariamente para a mensagem citada.

BEGIN;

UPDATE public.channel_messages
SET thread_id = NULL
WHERE thread_id IS NOT NULL
  AND reply_to IS NOT NULL
  AND thread_id = reply_to;

-- Recalcula o contador de respostas afetado pelos triggers de incremento.
UPDATE public.channel_messages parent
SET thread_reply_count = COALESCE(counts.total, 0)
FROM (
  SELECT p.id, COUNT(child.id) AS total
  FROM public.channel_messages p
  LEFT JOIN public.channel_messages child ON child.thread_id = p.id
  GROUP BY p.id
) counts
WHERE parent.id = counts.id
  AND parent.thread_reply_count IS DISTINCT FROM COALESCE(counts.total, 0);

COMMIT;
