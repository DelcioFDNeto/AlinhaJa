-- ============================================================
-- Migration 014: Aplicação dos Novos Acessos (Functions/Updates)
-- ============================================================

-- Migrar dados existentes de valores antigos para novos:
-- ti_admin → super_admin (será o único super admin real)
-- director → admin
-- manager → manager (sem mudança)
-- store_leader → manager
-- coordinator → manager
-- staff → member
UPDATE public.users SET role_level = 'super_admin' WHERE role_level = 'ti_admin';
UPDATE public.users SET role_level = 'admin'       WHERE role_level = 'director';
UPDATE public.users SET role_level = 'manager'     WHERE role_level IN ('store_leader', 'coordinator');
UPDATE public.users SET role_level = 'member'      WHERE role_level = 'staff';

-- ── 5. Atualizar handle_new_user para usar novos campos ───────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_role user_role_level := 'member';  -- ← Novo padrão: member
  v_is_active BOOLEAN := false;
  v_branch_id UUID := NULL;
  v_job_function TEXT := NULL;
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
  
  v_job_function := NEW.raw_user_meta_data ->> 'job_function';
  v_department_id := NEW.raw_user_meta_data ->> 'department_id';
  v_job_position_id := NEW.raw_user_meta_data ->> 'job_position_id';
  v_phone := NEW.raw_user_meta_data ->> 'phone';
  v_cpf := NEW.raw_user_meta_data ->> 'cpf';

  INSERT INTO public.users (
    id, full_name, avatar_url, role_level, is_active,
    branch_id, job_function, department_id, job_position_id,
    phone, cpf, email
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
    v_role,
    v_is_active,
    v_branch_id,
    v_job_function,
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

-- ── 6. Atualizar admin_create_user para novos campos ──────────
CREATE OR REPLACE FUNCTION public.admin_create_user(
  p_email TEXT,
  p_password TEXT,
  p_full_name TEXT,
  p_branch_id UUID,
  p_role_level public.user_role_level,
  p_job_function TEXT,
  p_department_id TEXT DEFAULT NULL,
  p_job_position_id TEXT DEFAULT NULL,
  p_sexo TEXT DEFAULT NULL,
  p_data_nascimento DATE DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_new_user_id UUID;
BEGIN
  -- Segurança: Somente super_admin e admin podem criar usuários
  IF NOT EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() AND role_level IN ('super_admin', 'admin')
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas Administradores podem criar usuários.';
  END IF;

  v_new_user_id := gen_random_uuid();

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    phone, phone_confirmed_at, confirmation_token, recovery_token,
    email_change_token_new, email_change, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_new_user_id, 'authenticated', 'authenticated',
    LOWER(p_email),
    extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', p_full_name),
    '', NULL, '', '', '', '', now(), now()
  );

  INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_new_user_id, v_new_user_id::text,
    jsonb_build_object('sub', v_new_user_id::text, 'email', LOWER(p_email), 'email_verified', true, 'phone_verified', false),
    'email', now(), now(), now()
  );

  UPDATE public.users
  SET 
    branch_id = p_branch_id,
    role_level = p_role_level,
    job_function = p_job_function,
    department_id = p_department_id,
    job_position_id = p_job_position_id,
    sexo = COALESCE(p_sexo, sexo),
    data_nascimento = COALESCE(p_data_nascimento, data_nascimento),
    is_active = true
  WHERE id = v_new_user_id;

  UPDATE auth.users SET banned_until = NULL WHERE id = v_new_user_id;

  RETURN v_new_user_id;

EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Este e-mail já está cadastrado no sistema.';
END;
$$;

-- ── 7. Atualizar admin_update_user para novos campos ──────────
CREATE OR REPLACE FUNCTION admin_update_user(
  p_target_user_id UUID,
  p_full_name TEXT,
  p_branch_id UUID,
  p_role_level TEXT,
  p_job_function TEXT,
  p_department_id TEXT DEFAULT NULL,
  p_job_position_id TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role TEXT;
BEGIN
  SELECT role_level INTO v_caller_role
  FROM public.users WHERE id = auth.uid();

  -- super_admin e admin podem editar usuários
  IF v_caller_role NOT IN ('super_admin', 'admin') THEN
    RAISE EXCEPTION 'Acesso negado: Somente Administradores podem editar perfis.';
  END IF;

  -- Somente super_admin pode atribuir role super_admin
  IF p_role_level = 'super_admin' AND v_caller_role != 'super_admin' THEN
    RAISE EXCEPTION 'Acesso negado: Apenas o Super Admin pode promover a este nível.';
  END IF;

  UPDATE public.users
  SET 
    full_name = p_full_name,
    branch_id = p_branch_id,
    role_level = p_role_level::user_role_level,
    job_function = p_job_function,
    department_id = p_department_id,
    job_position_id = p_job_position_id,
    updated_at = NOW()
  WHERE id = p_target_user_id;
END;
$$;

-- ── 8. Atualizar admin_toggle_user_status ─────────────────────
CREATE OR REPLACE FUNCTION public.admin_toggle_user_status(
  p_target_user_id UUID,
  p_is_active BOOLEAN
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  SELECT role_level INTO v_caller_role 
  FROM public.users WHERE id = auth.uid();

  -- super_admin e admin podem arquivar
  IF v_caller_role NOT IN ('super_admin', 'admin') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas Administradores podem arquivar contas.';
  END IF;

  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode alterar o próprio status.';
  END IF;

  UPDATE public.users SET is_active = p_is_active WHERE id = p_target_user_id;

  IF p_is_active = FALSE THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = p_target_user_id;
  ELSE
    UPDATE auth.users SET banned_until = NULL WHERE id = p_target_user_id;
  END IF;
END;
$$;

-- ── 9. Atualizar get_chats_with_preview (department nos DMs) ──
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
                 u.last_seen_at, u.role_level, u.job_function,
                 u.department_id,
                 d.name AS department_name,
                 b.name AS branch_name
          FROM chat_members cm2
          JOIN users u ON u.id = cm2.user_id
          LEFT JOIN branches b ON b.id = u.branch_id
          LEFT JOIN departments d ON d.id = u.department_id
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

