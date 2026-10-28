-- ============================================================
-- 011: Índice de Busca Full-Text + RPC de pesquisa
-- Permite pesquisar mensagens de texto em todos os chats do
-- usuário autenticado, retornando contexto e localização.
-- ============================================================

-- Índice GIN para busca rápida em mensagens de texto
CREATE INDEX IF NOT EXISTS idx_messages_content_search
  ON messages USING GIN (to_tsvector('portuguese', COALESCE(content, '')));

-- RPC de busca de mensagens
CREATE OR REPLACE FUNCTION search_messages(p_query TEXT, p_limit INT DEFAULT 30)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT
      m.id,
      m.chat_id,
      m.sender_id,
      m.content,
      m.content_type,
      m.created_at,
      u.full_name AS sender_name,
      COALESCE(c.name, ou.full_name, 'Chat') AS chat_name
    FROM messages m
    JOIN chat_members cm ON cm.chat_id = m.chat_id AND cm.user_id = v_user_id
    JOIN users u ON u.id = m.sender_id
    JOIN chats c ON c.id = m.chat_id
    LEFT JOIN chat_members cm2 ON cm2.chat_id = c.id AND cm2.user_id != v_user_id AND c.type = 'direct'
    LEFT JOIN users ou ON ou.id = cm2.user_id
    WHERE m.deleted_at IS NULL
      AND m.content IS NOT NULL
      AND to_tsvector('portuguese', m.content) @@ plainto_tsquery('portuguese', p_query)
    ORDER BY m.created_at DESC
    LIMIT p_limit
  ) t;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;
