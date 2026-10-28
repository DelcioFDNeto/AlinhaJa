-- ============================================================================
-- Harden workspace/channel security without changing the existing UX.
-- Workspaces are chats(type = 'channel') with workflow metadata.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.current_user_can_create_workspace()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_department_id TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT role_level::TEXT, department_id
  INTO v_role, v_department_id
  FROM public.users
  WHERE id = auth.uid()
    AND COALESCE(is_active, TRUE) = TRUE;

  RETURN COALESCE(
    v_role IN (
      'super_admin',
      'admin',
      'manager',
      -- Legacy role names kept for databases that were not fully migrated yet.
      'ti_admin',
      'director',
      'store_leader',
      'coordinator'
    ) OR v_department_id = 'ti',
    FALSE
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.can_manage_workspace(
  p_channel_id UUID,
  p_min_role TEXT DEFAULT 'manager'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_department_id TEXT;
  v_is_owner BOOLEAN := FALSE;
  v_has_global_role BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NULL OR p_channel_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT role_level::TEXT, department_id
  INTO v_role, v_department_id
  FROM public.users
  WHERE id = auth.uid()
    AND COALESCE(is_active, TRUE) = TRUE;

  SELECT EXISTS (
    SELECT 1
    FROM public.chats c
    WHERE c.id = p_channel_id
      AND c.created_by = auth.uid()
  ) OR EXISTS (
    SELECT 1
    FROM public.chat_members cm
    WHERE cm.chat_id = p_channel_id
      AND cm.user_id = auth.uid()
      AND cm.role::TEXT IN ('owner', 'admin')
  )
  INTO v_is_owner;

  IF p_min_role = 'admin' THEN
    v_has_global_role := COALESCE(
      v_role IN ('super_admin', 'admin', 'ti_admin', 'director')
      OR v_department_id = 'ti',
      FALSE
    );
  ELSE
    v_has_global_role := COALESCE(
      v_role IN (
        'super_admin',
        'admin',
        'manager',
        'ti_admin',
        'director',
        'store_leader',
        'coordinator'
      ) OR v_department_id = 'ti',
      FALSE
    );
  END IF;

  RETURN v_is_owner OR v_has_global_role;
END;
$$;

GRANT EXECUTE ON FUNCTION public.current_user_can_create_workspace() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_workspace(UUID, TEXT) TO authenticated;

-- Restrict direct channel creation at the database boundary.
DROP POLICY IF EXISTS "Membros criam chats" ON public.chats;
DROP POLICY IF EXISTS "Usuários criam chats permitidos" ON public.chats;
CREATE POLICY "Usuários criam chats permitidos"
  ON public.chats FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated'
    AND (
      type <> 'channel'::chat_type
      OR public.current_user_can_create_workspace()
    )
  );

-- Restrict member insertion while preserving:
-- - joining a public/non-archived channel as yourself;
-- - creator adding members immediately after creating a workspace;
-- - managers/admins managing membership.
DROP POLICY IF EXISTS "Inserção de membros" ON public.chat_members;
DROP POLICY IF EXISTS "Inserção segura de membros" ON public.chat_members;
CREATE POLICY "Inserção segura de membros"
  ON public.chat_members FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated'
    AND (
      (
        user_id = auth.uid()
        AND role::TEXT = 'member'
        AND EXISTS (
          SELECT 1
          FROM public.chats c
          WHERE c.id = chat_id
            AND c.type = 'channel'::chat_type
            AND LOWER(COALESCE(c.metadata->>'archived', 'false')) <> 'true'
        )
      )
      OR EXISTS (
        SELECT 1
        FROM public.chats c
        WHERE c.id = chat_id
          AND c.created_by = auth.uid()
      )
      OR public.can_manage_workspace(chat_id, 'manager')
    )
  );

CREATE OR REPLACE FUNCTION public.create_workspace(
  p_name TEXT,
  p_description TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::JSONB,
  p_member_ids UUID[] DEFAULT ARRAY[]::UUID[],
  p_status_config JSONB DEFAULT '[]'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_channel_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  IF NOT public.current_user_can_create_workspace() THEN
    RAISE EXCEPTION 'Acesso Negado: apenas gestores ou administradores podem criar workspaces.';
  END IF;

  INSERT INTO public.chats (type, name, description, created_by, metadata)
  VALUES (
    'channel',
    NULLIF(TRIM(p_name), ''),
    NULLIF(TRIM(COALESCE(p_description, '')), ''),
    v_user_id,
    COALESCE(p_metadata, '{}'::JSONB)
      || jsonb_build_object('archived', FALSE)
  )
  RETURNING id INTO v_channel_id;

  INSERT INTO public.chat_members (chat_id, user_id, role)
  VALUES (v_channel_id, v_user_id, 'owner')
  ON CONFLICT (chat_id, user_id) DO UPDATE SET role = 'owner';

  INSERT INTO public.chat_members (chat_id, user_id, role)
  SELECT v_channel_id, member_id, 'member'
  FROM (
    SELECT DISTINCT unnest(COALESCE(p_member_ids, ARRAY[]::UUID[])) AS member_id
  ) members
  WHERE member_id IS NOT NULL
    AND member_id <> v_user_id
  ON CONFLICT (chat_id, user_id) DO NOTHING;

  INSERT INTO public.workflow_status_config (
    channel_id,
    status,
    status_order,
    color,
    icon,
    is_final
  )
  SELECT
    v_channel_id,
    NULLIF(TRIM(status), ''),
    COALESCE(status_order, (ROW_NUMBER() OVER ())::INT),
    COALESCE(color, '#6B7280'),
    COALESCE(icon, 'circle'),
    COALESCE(is_final, FALSE)
  FROM jsonb_to_recordset(COALESCE(p_status_config, '[]'::JSONB))
    AS x(status TEXT, status_order INT, color TEXT, icon TEXT, is_final BOOLEAN)
  WHERE NULLIF(TRIM(status), '') IS NOT NULL;

  RETURN v_channel_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_workspace(TEXT, TEXT, JSONB, UUID[], JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_workflow_card(
  p_card_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_channel_id UUID;
  v_assigned_to UUID;
  v_requested_by UUID;
  v_status TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  SELECT channel_id, assigned_to, requested_by, status
  INTO v_channel_id, v_assigned_to, v_requested_by, v_status
  FROM public.workflow_cards
  WHERE id = p_card_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Card não encontrado.';
  END IF;

  IF LOWER(COALESCE(v_status, '')) = 'cancelado' THEN
    RAISE EXCEPTION 'Card cancelado não pode ser assumido.';
  END IF;

  IF v_requested_by = v_user_id THEN
    RAISE EXCEPTION 'O solicitante não deve assumir o próprio atendimento.';
  END IF;

  IF v_assigned_to IS NOT NULL AND v_assigned_to <> v_user_id THEN
    RAISE EXCEPTION 'Este card já possui responsável.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.chat_members cm
    WHERE cm.chat_id = v_channel_id
      AND cm.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não participa deste workspace.';
  END IF;

  UPDATE public.workflow_cards
  SET assigned_to = v_user_id,
      updated_at = NOW()
  WHERE id = p_card_id;

  INSERT INTO public.workflow_card_history (
    card_id, user_id, action, field_changed, old_value, new_value, observations
  )
  VALUES (
    p_card_id,
    v_user_id,
    'Card assumido',
    'assigned_to',
    COALESCE(v_assigned_to::TEXT, ''),
    v_user_id::TEXT,
    'Operador assumiu o atendimento'
  );

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_workflow_card(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_channel(p_channel_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_manage_workspace(p_channel_id, 'admin') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para excluir este workspace.';
  END IF;

  DELETE FROM public.workflow_card_comments
  WHERE card_id IN (SELECT id FROM public.workflow_cards WHERE channel_id = p_channel_id);

  DELETE FROM public.workflow_card_history
  WHERE card_id IN (SELECT id FROM public.workflow_cards WHERE channel_id = p_channel_id);

  DELETE FROM public.workflow_cards
  WHERE channel_id = p_channel_id;

  DELETE FROM public.workflow_status_config
  WHERE channel_id = p_channel_id;

  DELETE FROM public.messages
  WHERE chat_id = p_channel_id;

  DELETE FROM public.chat_members
  WHERE chat_id = p_channel_id;

  DELETE FROM public.chats
  WHERE id = p_channel_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.archive_channel(p_channel_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para arquivar este workspace.';
  END IF;

  UPDATE public.chats
  SET metadata = COALESCE(metadata, '{}'::JSONB)
      || jsonb_build_object('archived', TRUE, 'archived_at', NOW()::TEXT)
  WHERE id = p_channel_id;

  DELETE FROM public.chat_members
  WHERE chat_id = p_channel_id
    AND role::TEXT <> 'owner';
END;
$$;

CREATE OR REPLACE FUNCTION public.add_channel_member(
  p_channel_id UUID,
  p_user_id UUID,
  p_role TEXT DEFAULT 'member'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para adicionar membros.';
  END IF;

  IF LOWER(COALESCE(p_role, 'member')) NOT IN ('owner', 'admin', 'member') THEN
    RAISE EXCEPTION 'Papel de membro inválido: %', p_role;
  END IF;

  INSERT INTO public.chat_members (chat_id, user_id, role)
  VALUES (p_channel_id, p_user_id, LOWER(COALESCE(p_role, 'member'))::member_role)
  ON CONFLICT (chat_id, user_id) DO UPDATE
  SET role = EXCLUDED.role;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_channel_member(
  p_channel_id UUID,
  p_user_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para remover membros.';
  END IF;

  DELETE FROM public.chat_members
  WHERE chat_id = p_channel_id
    AND user_id = p_user_id
    AND role::TEXT <> 'owner';
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_channel(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_channel(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_channel_member(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_channel_member(UUID, UUID) TO authenticated;

-- Active lists should not return archived workspaces.
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
                 m.media_url, m.created_at, m.is_bot
          FROM public.messages m
          WHERE m.chat_id = c.id
            AND m.deleted_at IS NULL
            AND m.thread_id IS NULL
          ORDER BY m.created_at DESC
          LIMIT 1
        ) lm
      ) AS last_message,
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

-- Prevent archived channels from receiving newly-created users automatically.
CREATE OR REPLACE FUNCTION public.add_new_user_to_channels()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_channel RECORD;
BEGIN
  FOR v_channel IN
    SELECT id
    FROM public.chats
    WHERE type = 'channel'
      AND LOWER(COALESCE(metadata->>'archived', 'false')) <> 'true'
  LOOP
    INSERT INTO public.chat_members (chat_id, user_id, role)
    VALUES (v_channel.id, NEW.id, 'member')
    ON CONFLICT (chat_id, user_id) DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Current auth.users signup trigger also auto-joins channels; keep its behavior,
-- but skip archived workspaces.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  INSERT INTO public.chat_members (chat_id, user_id, role)
  SELECT id, NEW.id, 'member'
  FROM public.chats
  WHERE type = 'channel'
    AND LOWER(COALESCE(metadata->>'archived', 'false')) <> 'true'
  ON CONFLICT (chat_id, user_id) DO NOTHING;

  IF v_is_active = false THEN
    UPDATE auth.users
    SET banned_until = '3000-01-01 00:00:00+00'
    WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;
