-- ============================================================================
-- Comunicação em canais: o mínimo que toda plataforma corporativa entrega
-- ============================================================================
-- Entrega quatro coisas e corrige duas falhas encontradas no caminho:
--
--   1. Nível de notificação por canal (`all` / `mentions` / `none`).
--      `channel_members` não tinha equivalente ao `chat_members.muted`, então
--      um workspace movimentado notificava todo mundo para sempre. A própria
--      Edge Function documentava a ausência.
--
--   2. Menção a todos (`@canal` / `@aqui`), pré-requisito para o nível
--      `mentions` ser utilizável.
--
--   3. Editar a própria mensagem em canal (DMs já tinham).
--
--   4. CORREÇÃO — apagar mensagem em canal nunca funcionou.
--      `channel_messages` tem RLS habilitada com policies apenas de SELECT e
--      INSERT. O `UPDATE {deleted_at}` disparado pelo cliente afetava zero
--      linhas e não levantava erro: a bolha sumia na hora e voltava no
--      próximo fetch. Edição e exclusão passam a ser RPC `SECURITY DEFINER`,
--      mantendo a tabela fechada para escrita direta.
--
--   5. CORREÇÃO DE SEGURANÇA — escalonamento de privilégio em channel_members.
--      A policy "Atualizar leitura propria do canal" permite `UPDATE` da
--      própria linha sem restringir colunas, e RLS não restringe coluna. Um
--      `viewer` podia rodar
--          UPDATE channel_members SET role='admin' WHERE user_id = auth.uid()
--      e virar admin do workspace — `can_manage_workspace()` aceita
--      `cm.role IN ('admin','editor')`, o que libera excluir o canal,
--      arquivar, gerir membros e editar o workspace. A policy continua, mas
--      agora o privilégio de UPDATE é concedido por COLUNA.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Nível de notificação por canal
-- ----------------------------------------------------------------------------

ALTER TABLE public.channel_members
  ADD COLUMN IF NOT EXISTS notification_level TEXT NOT NULL DEFAULT 'all';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'channel_members_notification_level_check'
      AND conrelid = 'public.channel_members'::regclass
  ) THEN
    ALTER TABLE public.channel_members
      ADD CONSTRAINT channel_members_notification_level_check
      CHECK (notification_level IN ('all', 'mentions', 'none'));
  END IF;
END $$;

-- A Edge Function filtra destinatários por este par a cada mensagem.
CREATE INDEX IF NOT EXISTS idx_channel_members_notification
  ON public.channel_members (channel_id, notification_level);

-- ----------------------------------------------------------------------------
-- 2. Fecha o escalonamento de privilégio: UPDATE por coluna
-- ----------------------------------------------------------------------------
-- RLS decide QUAIS LINHAS; o GRANT por coluna decide QUAIS COLUNAS. A policy
-- "Atualizar leitura propria do canal" (linha própria) continua valendo — o
-- que muda é que `role` deixa de ser gravável pelo cliente. As RPCs de gestão
-- (`add_channel_member`, `remove_channel_member`, `update_workflow_operators`)
-- são SECURITY DEFINER e seguem funcionando, pois rodam como o dono da função.
REVOKE UPDATE ON public.channel_members FROM authenticated;
GRANT UPDATE (last_read_at, unread_count, notification_level)
  ON public.channel_members TO authenticated;

-- `anon` nunca teve o que fazer nesta tabela.
REVOKE ALL ON public.channel_members FROM anon;

CREATE OR REPLACE FUNCTION public.set_channel_notification_level(
  p_channel_id UUID,
  p_level TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_level TEXT := LOWER(TRIM(COALESCE(p_level, 'all')));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  IF v_level NOT IN ('all', 'mentions', 'none') THEN
    RAISE EXCEPTION 'Nível de notificação inválido: %', p_level;
  END IF;

  UPDATE public.channel_members
  SET notification_level = v_level
  WHERE channel_id = p_channel_id
    AND user_id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Você não é membro deste canal.';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_channel_notification_level(UUID, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. Editar e apagar a própria mensagem de canal
-- ----------------------------------------------------------------------------
-- Feito por RPC de propósito. Uma policy de UPDATE em `channel_messages`
-- liberaria o autor a reescrever QUALQUER coluna da linha (`is_system`,
-- `content_type`, `media_url`, `thread_reply_count`…), porque RLS não
-- restringe coluna; e um GRANT por coluna não daria conta porque as regras
-- variam por papel (autor edita conteúdo, moderador só apaga).

CREATE OR REPLACE FUNCTION public.edit_channel_message(
  p_message_id UUID,
  p_content TEXT,
  p_mentions UUID[] DEFAULT ARRAY[]::UUID[],
  p_mentions_everyone BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_msg RECORD;
  v_content TEXT := NULLIF(TRIM(COALESCE(p_content, '')), '');
  v_metadata JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  IF v_content IS NULL THEN
    RAISE EXCEPTION 'A mensagem não pode ficar vazia. Use apagar.';
  END IF;

  SELECT id, channel_id, sender_id, content_type, deleted_at, metadata
  INTO v_msg
  FROM public.channel_messages
  WHERE id = p_message_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mensagem não encontrada.';
  END IF;

  IF v_msg.sender_id IS DISTINCT FROM v_user_id THEN
    RAISE EXCEPTION 'Você só pode editar as próprias mensagens.';
  END IF;

  IF v_msg.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Mensagem apagada não pode ser editada.';
  END IF;

  -- Legenda de mídia é conteúdo textual e pode ser corrigida; o binário não.
  IF COALESCE(v_msg.content_type, 'text') NOT IN ('text', 'image', 'video', 'file') THEN
    RAISE EXCEPTION 'Este tipo de mensagem não pode ser editado.';
  END IF;

  -- Anúncio e enquete carregam estado próprio (ciência, votos) e sairiam de
  -- sincronia com o texto — ficam fora da edição.
  IF COALESCE(v_msg.metadata->>'type', '') IN ('announcement', 'poll', 'date_event') THEN
    RAISE EXCEPTION 'Anúncios e enquetes não podem ser editados.';
  END IF;

  v_metadata := COALESCE(v_msg.metadata, '{}'::JSONB)
    || jsonb_build_object(
      'mentions', COALESCE(to_jsonb(p_mentions), '[]'::JSONB),
      'mentions_everyone', COALESCE(p_mentions_everyone, FALSE)
    );

  -- `edited_at` é carimbado pelo trigger fn_channel_messages_guard_immutable.
  UPDATE public.channel_messages
  SET content = v_content,
      metadata = v_metadata,
      updated_at = NOW()
  WHERE id = p_message_id;

  RETURN jsonb_build_object('ok', TRUE, 'id', p_message_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.edit_channel_message(UUID, TEXT, UUID[], BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_channel_message(p_message_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_msg RECORD;
  v_is_moderator BOOLEAN;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  SELECT id, channel_id, sender_id, deleted_at
  INTO v_msg
  FROM public.channel_messages
  WHERE id = p_message_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mensagem não encontrada.';
  END IF;

  IF v_msg.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', TRUE, 'already_deleted', TRUE);
  END IF;

  -- Moderação: quem administra o workspace apaga mensagem de terceiro.
  v_is_moderator := public.can_manage_workspace(v_msg.channel_id, 'manager');

  IF v_msg.sender_id IS DISTINCT FROM v_user_id AND NOT v_is_moderator THEN
    RAISE EXCEPTION 'Sem permissão para apagar esta mensagem.';
  END IF;

  UPDATE public.channel_messages
  SET deleted_at = NOW(),
      updated_at = NOW()
  WHERE id = p_message_id;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'moderated', v_msg.sender_id IS DISTINCT FROM v_user_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_channel_message(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. Marcar canal como lido / marcar todos como lidos
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.mark_all_channels_as_read()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_count INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  WITH touched AS (
    UPDATE public.channel_members
    SET last_read_at = NOW(), unread_count = 0
    WHERE user_id = v_user_id
      AND unread_count > 0
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_count FROM touched;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_all_channels_as_read() TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. Índice para o divisor de não lidas
-- ----------------------------------------------------------------------------
-- A régua "novas mensagens" pergunta pela primeira mensagem depois do
-- `last_read_at` do usuário.
CREATE INDEX IF NOT EXISTS idx_channel_messages_channel_created
  ON public.channel_messages (channel_id, created_at)
  WHERE deleted_at IS NULL;
