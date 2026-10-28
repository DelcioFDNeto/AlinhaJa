-- ============================================================
-- 016: Reações com Emoji + Fixar Mensagem
-- ============================================================

-- 1. Tabela de reações
CREATE TABLE IF NOT EXISTS public.message_reactions (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id  UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  emoji       TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(message_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_reactions_message ON public.message_reactions(message_id);

-- RLS
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Membros veem reações do seu chat"
  ON public.message_reactions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = message_id AND public.is_chat_member(m.chat_id)
    )
  );

CREATE POLICY "Membros criam suas próprias reações"
  ON public.message_reactions FOR INSERT
  WITH CHECK (
    user_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = message_id AND public.is_chat_member(m.chat_id)
    )
  );

CREATE POLICY "Usuário remove suas próprias reações"
  ON public.message_reactions FOR DELETE
  USING (user_id = auth.uid());

-- 2. Coluna de mensagem fixada nos chats
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS pinned_message_id UUID REFERENCES public.messages(id) ON DELETE SET NULL;
