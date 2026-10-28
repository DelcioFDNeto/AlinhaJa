-- Recibos de entrega/leitura na lista de conversas.
--
-- Problema: `get_chats_with_preview` nunca devolvia `status` dentro de
-- `last_message`, então o app caía no default ('sent') e a lista exibia
-- sempre um único check — sem distinguir enviado / entregue / lido.
--
-- Além disso não existia nenhum marcador de ENTREGA: o status só saía de
-- 'sent' quando o destinatário abria a conversa (mark_messages_as_read).
-- Sem o estado intermediário, "1 check x 2 checks" não tinha significado.

-- ──────────────────────────────────────────────────────────────────────
-- 1) Marcação de entrega
-- ──────────────────────────────────────────────────────────────────────
-- Chamada pelo destinatário quando o app recebe as mensagens (sessão ativa
-- ou primeira abertura após ficar offline) — mesma semântica do WhatsApp:
-- 'delivered' = chegou ao dispositivo, ainda não foi aberta.
CREATE OR REPLACE FUNCTION public.mark_messages_as_delivered(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Guard: a função é SECURITY DEFINER, então só o próprio usuário pode
  -- confirmar as suas entregas.
  IF p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não é permitido confirmar entregas de outro usuário';
  END IF;

  UPDATE public.messages m
  SET status = 'delivered'
  WHERE m.sender_id <> p_user_id
    AND m.status = 'sent'
    AND m.deleted_at IS NULL
    AND m.chat_id IN (
      SELECT cm.chat_id
      FROM public.chat_members cm
      WHERE cm.user_id = p_user_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_messages_as_delivered(uuid) TO authenticated;

-- Índice parcial: o UPDATE acima roda a cada lote de mensagens novas e só
-- olha as pendentes de entrega.
CREATE INDEX IF NOT EXISTS idx_messages_pending_delivery
  ON public.messages (chat_id, sender_id)
  WHERE status = 'sent';

-- ──────────────────────────────────────────────────────────────────────
-- 2) Preview da lista com status + recibo de leitura dos outros membros
-- ──────────────────────────────────────────────────────────────────────
-- Mantém a definição de 20260512184000 e acrescenta:
--   • last_message.status  → sent / delivered / read
--   • other_read_at        → maior last_read_at entre os DEMAIS membros,
--                            usado para o check azul (mesma regra da bolha
--                            dentro da conversa).
CREATE OR REPLACE FUNCTION public.get_chats_with_preview()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT
      c.id, c.type, c.name, c.description, c.avatar_url,
      c.created_by, c.metadata, c.created_at,
      cm.last_read_at, cm.is_pinned,
      (
        SELECT row_to_json(lm) FROM (
          SELECT m.id, m.sender_id, m.content, m.content_type,
                 m.media_url, m.created_at, m.is_bot, m.status
          FROM public.messages m
          WHERE m.chat_id = c.id
            AND m.deleted_at IS NULL
            AND m.thread_id IS NULL
          ORDER BY m.created_at DESC
          LIMIT 1
        ) lm
      ) AS last_message,
      (
        SELECT MAX(cm3.last_read_at)
        FROM public.chat_members cm3
        WHERE cm3.chat_id = c.id
          AND cm3.user_id <> v_user_id
      ) AS other_read_at,
      (
        SELECT COUNT(*)::int
        FROM public.messages m
        WHERE m.chat_id = c.id
          AND m.deleted_at IS NULL
          AND m.thread_id IS NULL
          AND m.sender_id != v_user_id
          AND m.created_at > cm.last_read_at
      ) AS unread_count,
      CASE WHEN c.type = 'direct' THEN (
        SELECT row_to_json(ou) FROM (
          SELECT u.id, u.full_name, u.avatar_url, u.is_online,
                 u.last_seen_at, u.role_level,
                 u.branch_id, u.department_id, u.job_position_id,
                 json_build_object('name', d.name) AS departments,
                 json_build_object('name', jp.name) AS job_positions,
                 json_build_object('name', b.name) AS branches,
                 d.name AS department_name,
                 jp.name AS job_position_name,
                 b.name AS branch_name
          FROM public.chat_members cm2
          JOIN public.users u ON u.id = cm2.user_id
          LEFT JOIN public.branches b ON b.id = u.branch_id
          LEFT JOIN public.departments d ON d.id = u.department_id
          LEFT JOIN public.job_positions jp ON jp.id = u.job_position_id
          WHERE cm2.chat_id = c.id
            AND cm2.user_id != v_user_id
          LIMIT 1
        ) ou
      ) ELSE NULL END AS other_user
    FROM public.chat_members cm
    JOIN public.chats c ON c.id = cm.chat_id
    WHERE cm.user_id = v_user_id
      AND NOT (
        c.type = 'channel'::chat_type
        AND LOWER(COALESCE(c.metadata->>'archived', 'false')) = 'true'
      )
    ORDER BY cm.is_pinned DESC, (
      SELECT m2.created_at
      FROM public.messages m2
      WHERE m2.chat_id = c.id
        AND m2.deleted_at IS NULL
        AND m2.thread_id IS NULL
      ORDER BY m2.created_at DESC
      LIMIT 1
    ) DESC NULLS LAST
  ) t;

  RETURN COALESCE(v_result, '[]'::JSON);
END;
$$;
