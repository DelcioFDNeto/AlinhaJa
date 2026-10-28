-- ============================================================
-- Review do módulo de canais e workspaces (16/09/2026 — v1.3.9)
--
-- 1. Pedido de entrada aprovável por admin de QUALQUER canal
--    As policies de gestão de `channel_join_requests` testavam
--      EXISTS (SELECT 1 FROM channel_members cm
--              WHERE cm.channel_id = channel_id AND ...)
--    Dentro da subconsulta, `channel_id` sem qualificação resolve para a
--    coluna de `cm` (escopo mais interno), não para a do pedido. A condição
--    virava `cm.channel_id = cm.channel_id` — sempre verdadeira. Quem fosse
--    admin de um canal qualquer (inclusive um que ele mesmo criou) lia,
--    aprovava e apagava pedidos de todos os canais, e o trigger de aprovação
--    o colocava como membro: a regra "entrada só por convite ou pedido
--    aprovado" (v1.3.7) era contornável.
--
-- 2. `update_channel_info` gravava o metadata inteiro
--    `update_workspace` descarta de propósito as chaves de governança
--    (operadores, arquivamento) para um gestor não se autopromover. Esta
--    função tem a mesma permissão e substituía o metadata sem filtro — era o
--    atalho para o que a outra bloqueia. Também apagava ícone, cor e o
--    `workflow_enabled` quando a tela enviava um metadata incompleto.
--    Agora faz merge raso e descarta as mesmas chaves.
--
-- 3. Contagem de mensagens por membro
--    A tela de informações baixava o `sender_id` de todas as mensagens do
--    canal e contava no app. O PostgREST corta em 1000 linhas, então canais
--    maiores mostravam contagens erradas, e mensagens apagadas contavam.
-- ============================================================

-- ── 1. Policies de gestão de pedidos de entrada ─────────────
CREATE OR REPLACE FUNCTION public.can_review_channel_join_request(p_channel_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Mesmos três papéis de antes (criador, admin do canal, admin global),
  -- agora amarrados ao canal do pedido.
  SELECT auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.channels c
      WHERE c.id = p_channel_id AND c.created_by = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.channel_members cm
      WHERE cm.channel_id = p_channel_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin'
    )
    OR EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid()
        AND COALESCE(u.is_active, TRUE) = TRUE
        AND u.role_level::TEXT IN ('admin', 'super_admin')
    )
  );
$$;

REVOKE ALL ON FUNCTION public.can_review_channel_join_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_review_channel_join_request(UUID) TO authenticated;

DROP POLICY IF EXISTS "Admins can select channel requests" ON public.channel_join_requests;
CREATE POLICY "Admins can select channel requests" ON public.channel_join_requests
  FOR SELECT TO authenticated
  USING (public.can_review_channel_join_request(channel_join_requests.channel_id));

DROP POLICY IF EXISTS "Admins can update channel requests" ON public.channel_join_requests;
CREATE POLICY "Admins can update channel requests" ON public.channel_join_requests
  FOR UPDATE TO authenticated
  USING (public.can_review_channel_join_request(channel_join_requests.channel_id))
  WITH CHECK (status IN ('approved', 'rejected'));

DROP POLICY IF EXISTS "Admins can delete channel requests" ON public.channel_join_requests;
CREATE POLICY "Admins can delete channel requests" ON public.channel_join_requests
  FOR DELETE TO authenticated
  USING (public.can_review_channel_join_request(channel_join_requests.channel_id));

-- ── 2. update_channel_info com merge e chaves protegidas ────
CREATE OR REPLACE FUNCTION public.update_channel_info(
  p_channel_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_metadata JSONB DEFAULT '{}'::JSONB,
  p_posting_permission TEXT DEFAULT 'everyone'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_posting TEXT := LOWER(TRIM(COALESCE(p_posting_permission, 'everyone')));
BEGIN
  IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para atualizar este workspace.';
  END IF;

  IF v_posting = 'all' THEN
    v_posting := 'everyone';
  END IF;
  IF v_posting NOT IN ('everyone', 'admins') THEN
    RAISE EXCEPTION 'Permissão de publicação inválida: %', p_posting_permission;
  END IF;

  UPDATE public.channels
  SET
    name = COALESCE(NULLIF(TRIM(COALESCE(p_name, '')), ''), name),
    description = p_description,
    -- Merge raso, mesmas exclusões de `update_workspace`.
    metadata = COALESCE(metadata, '{}'::JSONB) || (
      COALESCE(p_metadata, '{}'::JSONB)
        - 'assignment_mode'
        - 'operator_ids'
        - 'default_operator_id'
        - 'operator_count'
        - 'archived'
        - 'archived_at'
    ),
    posting_permission = v_posting,
    updated_at = NOW()
  WHERE id = p_channel_id;
END;
$$;

REVOKE ALL ON FUNCTION public.update_channel_info(UUID, TEXT, TEXT, JSONB, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_channel_info(UUID, TEXT, TEXT, JSONB, TEXT) TO authenticated;

-- ── 3. Contagem de mensagens por membro ─────────────────────
-- SECURITY INVOKER: a RLS de `channel_messages` (só membros) vale aqui.
CREATE OR REPLACE FUNCTION public.get_channel_message_counts(p_channel_id UUID)
RETURNS TABLE (sender_id UUID, total BIGINT)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT m.sender_id, COUNT(*)::BIGINT
  FROM public.channel_messages m
  WHERE m.channel_id = p_channel_id
    AND m.deleted_at IS NULL
    AND m.sender_id IS NOT NULL
  GROUP BY m.sender_id;
$$;

REVOKE ALL ON FUNCTION public.get_channel_message_counts(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_channel_message_counts(UUID) TO authenticated;
