-- ============================================================
-- Migration 018: Remover envio de job_function nas funções legadas
-- ============================================================
-- As funções handle_new_user e get_chats_with_preview ainda estavam 
-- tentando selecionar ou inserir a coluna 'job_function' excluída na migration 015.
-- ============================================================

-- ── 1. handle_new_user (Trigger de cadastro Autenticado) ──────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_role user_role_level := 'member';
  v_is_active BOOLEAN := false;
  v_branch_id UUID := NULL;
  v_department_id TEXT := NULL;
  v_job_position_id TEXT := NULL;
  v_phone TEXT := NULL;
  v_cpf TEXT := NULL;
  v_branch_str TEXT;
BEGIN
  -- Extrai metadados do signup
  v_branch_str := NEW.raw_user_meta_data ->> 'branch_id';
  IF v_branch_str IS NOT NULL AND v_branch_str != '' THEN
    BEGIN
      v_branch_id := v_branch_str::UUID;
    EXCEPTION WHEN invalid_text_representation THEN
      v_branch_id := NULL;
    END;
  END IF;
  
  v_department_id := NEW.raw_user_meta_data ->> 'department_id';
  v_job_position_id := NEW.raw_user_meta_data ->> 'job_position_id';
  v_phone := NEW.raw_user_meta_data ->> 'phone';
  v_cpf := NEW.raw_user_meta_data ->> 'cpf';

  INSERT INTO public.users (
    id, full_name, avatar_url, role_level, is_active,
    branch_id, department_id, job_position_id,
    phone, cpf, email
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
    v_role,
    v_is_active,
    v_branch_id,
    v_department_id,
    v_job_position_id,
    v_phone,
    v_cpf,
    NEW.email
  )
  ON CONFLICT (id) DO NOTHING;

  IF v_is_active = false THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- ── 2. get_chats_with_preview (Preview na Aba de Mensagens) ──
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
      c.id, c.type, c.name, c.description, c.avatar_url,
      c.created_by, c.metadata, c.created_at,
      cm.last_read_at, cm.is_pinned,
      (
        SELECT row_to_json(lm) FROM (
          SELECT m.id, m.sender_id, m.content, m.content_type,
                 m.media_url, m.created_at, m.is_bot
          FROM messages m
          WHERE m.chat_id = c.id AND m.deleted_at IS NULL AND m.thread_id IS NULL
          ORDER BY m.created_at DESC LIMIT 1
        ) lm
      ) AS last_message,
      (
        SELECT COUNT(*)::int FROM messages m
        WHERE m.chat_id = c.id AND m.deleted_at IS NULL
          AND m.thread_id IS NULL AND m.sender_id != v_user_id
          AND m.created_at > cm.last_read_at
      ) AS unread_count,
      CASE WHEN c.type = 'direct' THEN (
        SELECT row_to_json(ou) FROM (
          SELECT u.id, u.full_name, u.avatar_url, u.is_online,
                 u.last_seen_at, u.role_level, u.job_position_id,
                 u.department_id,
                 d.name AS department_name,
                 jp.name AS job_position_name,
                 b.name AS branch_name
          FROM chat_members cm2
          JOIN users u ON u.id = cm2.user_id
          LEFT JOIN branches b ON b.id = u.branch_id
          LEFT JOIN departments d ON d.id = u.department_id
          LEFT JOIN job_positions jp ON jp.id = u.job_position_id
          WHERE cm2.chat_id = c.id AND cm2.user_id != v_user_id
          LIMIT 1
        ) ou
      ) ELSE NULL END AS other_user
    FROM chat_members cm
    JOIN chats c ON c.id = cm.chat_id
    WHERE cm.user_id = v_user_id
    ORDER BY cm.is_pinned DESC, (
      SELECT m2.created_at FROM messages m2
      WHERE m2.chat_id = c.id AND m2.deleted_at IS NULL AND m2.thread_id IS NULL
      ORDER BY m2.created_at DESC LIMIT 1
    ) DESC NULLS LAST
  ) t;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;
