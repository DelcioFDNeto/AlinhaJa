-- Ensure dedicated workspace cards are visible after channels were isolated
-- from chats/chat_members into channels/channel_members.

INSERT INTO public.channel_members (channel_id, user_id, role)
SELECT
  c.id,
  u.id,
  CASE
    WHEN c.created_by = u.id
      OR u.role_level::TEXT IN ('super_admin', 'admin', 'ti_admin', 'director')
      OR u.department_id = 'ti'
      THEN 'admin'
    ELSE 'viewer'
  END
FROM public.channels c
CROSS JOIN public.users u
WHERE COALESCE(u.is_active, TRUE) = TRUE
  AND LOWER(COALESCE(c.metadata->>'archived', 'false')) <> 'true'
  AND (
    c.metadata->>'workspace' = 'alinha_operations'
    OR LOWER(COALESCE(c.metadata->>'workflow_enabled', 'false')) = 'true'
  )
ON CONFLICT ON CONSTRAINT channel_members_pkey DO NOTHING;

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

  INSERT INTO public.channel_members (channel_id, user_id, role)
  SELECT
    c.id,
    NEW.id,
    CASE
      WHEN v_role::TEXT IN ('super_admin', 'admin', 'ti_admin', 'director')
        OR v_department_id = 'ti'
        THEN 'admin'
      ELSE 'viewer'
    END
  FROM public.channels c
  WHERE LOWER(COALESCE(c.metadata->>'archived', 'false')) <> 'true'
    AND (
      c.metadata->>'workspace' = 'alinha_operations'
      OR LOWER(COALESCE(c.metadata->>'workflow_enabled', 'false')) = 'true'
    )
  ON CONFLICT ON CONSTRAINT channel_members_pkey DO NOTHING;

  IF v_is_active = false THEN
    UPDATE auth.users
    SET banned_until = '3000-01-01 00:00:00+00'
    WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;
