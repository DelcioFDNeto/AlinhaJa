-- ============================================================
-- 012: RPCs para Grupos
-- Funções para criar grupo, adicionar/remover membros.
-- ============================================================

-- Cria um grupo com membros iniciais
CREATE OR REPLACE FUNCTION create_group_chat(
  p_name TEXT,
  p_description TEXT DEFAULT NULL,
  p_member_ids UUID[] DEFAULT '{}'::UUID[]
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_chat_id UUID;
  v_member_id UUID;
BEGIN
  -- Cria o chat
  INSERT INTO chats (type, name, description, created_by)
  VALUES ('group', p_name, p_description, v_user_id)
  RETURNING id INTO v_chat_id;

  -- Adiciona o criador como membro
  INSERT INTO chat_members (chat_id, user_id, role)
  VALUES (v_chat_id, v_user_id, 'admin');

  -- Adiciona os membros convidados
  FOREACH v_member_id IN ARRAY p_member_ids LOOP
    IF v_member_id != v_user_id THEN
      INSERT INTO chat_members (chat_id, user_id, role)
      VALUES (v_chat_id, v_member_id, 'member')
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  -- Mensagem de sistema
  INSERT INTO messages (chat_id, sender_id, content, content_type, metadata)
  VALUES (v_chat_id, v_user_id, 'criou o grupo', 'text',
    jsonb_build_object('is_system', true));

  RETURN v_chat_id;
END;
$$;

-- Adiciona um membro ao grupo
CREATE OR REPLACE FUNCTION add_group_member(p_chat_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_chat_type TEXT;
  v_user_role TEXT;
BEGIN
  SELECT type INTO v_chat_type FROM chats WHERE id = p_chat_id;
  IF v_chat_type != 'group' THEN
    RAISE EXCEPTION 'Não é um chat de grupo';
  END IF;

  SELECT role INTO v_user_role FROM chat_members
    WHERE chat_id = p_chat_id AND user_id = v_user_id;
  IF v_user_role IS NULL OR v_user_role != 'admin' THEN
    RAISE EXCEPTION 'Apenas administradores podem adicionar membros';
  END IF;

  INSERT INTO chat_members (chat_id, user_id, role)
  VALUES (p_chat_id, p_user_id, 'member')
  ON CONFLICT DO NOTHING;

  -- Mensagem de sistema
  INSERT INTO messages (chat_id, sender_id, content, content_type, metadata)
  VALUES (p_chat_id, v_user_id,
    'adicionou ' || (SELECT full_name FROM users WHERE id = p_user_id),
    'text', jsonb_build_object('is_system', true));
END;
$$;

-- Remove um membro do grupo
CREATE OR REPLACE FUNCTION remove_group_member(p_chat_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_chat_type TEXT;
  v_user_role TEXT;
BEGIN
  SELECT type INTO v_chat_type FROM chats WHERE id = p_chat_id;
  IF v_chat_type != 'group' THEN
    RAISE EXCEPTION 'Não é um chat de grupo';
  END IF;

  SELECT role INTO v_user_role FROM chat_members
    WHERE chat_id = p_chat_id AND user_id = v_user_id;

  -- Permite se é admin OU se o próprio membro está saindo
  IF v_user_role != 'admin' AND v_user_id != p_user_id THEN
    RAISE EXCEPTION 'Apenas administradores podem remover membros';
  END IF;

  DELETE FROM chat_members
    WHERE chat_id = p_chat_id AND user_id = p_user_id;

  -- Mensagem de sistema
  IF v_user_id = p_user_id THEN
    INSERT INTO messages (chat_id, sender_id, content, content_type, metadata)
    VALUES (p_chat_id, v_user_id, 'saiu do grupo', 'text',
      jsonb_build_object('is_system', true));
  ELSE
    INSERT INTO messages (chat_id, sender_id, content, content_type, metadata)
    VALUES (p_chat_id, v_user_id,
      'removeu ' || (SELECT full_name FROM users WHERE id = p_user_id),
      'text', jsonb_build_object('is_system', true));
  END IF;
END;
$$;
