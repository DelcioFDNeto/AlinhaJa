-- ============================================================
-- 019: Pin Chats Feature
-- Adiciona a coluna is_pinned na tabela chat_members
-- e recria a função get_chats_with_preview para
-- priorizar chats fixados na ordenação.
-- ============================================================

-- 1. Adicionar coluna na tabela (se não existir)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name='chat_members' AND column_name='is_pinned'
    ) THEN
        ALTER TABLE public.chat_members ADD COLUMN is_pinned BOOLEAN DEFAULT false;
    END IF;
END
$$;

-- 2. Recriar a RPC get_chats_with_preview com a nova ordenação
CREATE OR REPLACE FUNCTION get_chats_with_preview()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT
      c.id,
      c.type,
      c.name,
      c.description,
      c.avatar_url,
      c.created_by,
      c.metadata,
      c.created_at,
      cm.last_read_at,
      cm.is_pinned, -- Novo atributo
      -- Última mensagem
      (
        SELECT row_to_json(lm)
        FROM (
          SELECT m.id, m.sender_id, m.content, m.content_type,
                 m.media_url, m.created_at
          FROM messages m
          WHERE m.chat_id = c.id AND m.deleted_at IS NULL
          ORDER BY m.created_at DESC
          LIMIT 1
        ) lm
      ) AS last_message,
      -- Contagem de não-lidas (apenas mensagens de OUTROS após last_read_at)
      (
        SELECT COUNT(*)::int
        FROM messages m
        WHERE m.chat_id = c.id
          AND m.deleted_at IS NULL
          AND m.sender_id != v_user_id
          AND m.created_at > cm.last_read_at
      ) AS unread_count,
      -- Outro usuário (para DMs)
      CASE WHEN c.type = 'direct' THEN (
        SELECT row_to_json(ou)
        FROM (
          SELECT u.id, u.full_name, u.avatar_url, u.is_online,
                 u.last_seen_at, u.role_level, u.job_function,
                 b.name AS branch_name
          FROM chat_members cm2
          JOIN users u ON u.id = cm2.user_id
          LEFT JOIN branches b ON b.id = u.branch_id
          WHERE cm2.chat_id = c.id AND cm2.user_id != v_user_id
          LIMIT 1
        ) ou
      ) ELSE NULL END AS other_user
    FROM chat_members cm
    JOIN chats c ON c.id = cm.chat_id
    WHERE cm.user_id = v_user_id
    -- Nova ordem: Primeiro fixados (is_pinned = true DESC), depois a última mensagem
    ORDER BY cm.is_pinned DESC, (
      SELECT m2.created_at FROM messages m2
      WHERE m2.chat_id = c.id AND m2.deleted_at IS NULL
      ORDER BY m2.created_at DESC LIMIT 1
    ) DESC NULLS LAST
  ) t;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;
