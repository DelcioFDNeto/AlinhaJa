-- Permite favoritar mensagens de canal, não só de conversas.
--
-- `starred_messages.chat_message_id` era NOT NULL com FK para `messages`, o que
-- deixava `channel_messages` de fora. Passa a existir uma coluna irmã para
-- canais e exatamente uma das duas deve estar preenchida.

BEGIN;

ALTER TABLE public.starred_messages
  ADD COLUMN IF NOT EXISTS channel_message_id UUID
    REFERENCES public.channel_messages(id) ON DELETE CASCADE;

ALTER TABLE public.starred_messages
  ALTER COLUMN chat_message_id DROP NOT NULL;

-- `chat_id` guardava a conversa; agora também recebe o canal de origem.
ALTER TABLE public.starred_messages
  ALTER COLUMN chat_id DROP NOT NULL;

-- Exatamente uma origem por favorito.
ALTER TABLE public.starred_messages
  DROP CONSTRAINT IF EXISTS starred_messages_exactly_one_source;

ALTER TABLE public.starred_messages
  ADD CONSTRAINT starred_messages_exactly_one_source
  CHECK (num_nonnulls(chat_message_id, channel_message_id) = 1);

-- Um favorito por usuário por mensagem (a UI faz toggle e precisa disso para
-- não duplicar quando o mesmo item é marcado em lote duas vezes).
CREATE UNIQUE INDEX IF NOT EXISTS starred_messages_user_chat_msg_uniq
  ON public.starred_messages (user_id, chat_message_id)
  WHERE chat_message_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS starred_messages_user_channel_msg_uniq
  ON public.starred_messages (user_id, channel_message_id)
  WHERE channel_message_id IS NOT NULL;

COMMIT;
