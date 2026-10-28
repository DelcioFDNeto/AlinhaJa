-- ==============================================================================
-- 20260429100000_auto_join_channels.sql
-- ==============================================================================
-- Garante que TODOS os usuários do sistema sejam membros de TODOS os canais.
-- Necessário para que usuários possam visualizar mensagens e entrar em reuniões.
-- ==============================================================================

-- 1. Backfill: Adiciona todos os usuários existentes a todos os canais existentes
INSERT INTO public.chat_members (chat_id, user_id, role)
SELECT c.id, u.id, 'member'
FROM public.chats c
CROSS JOIN public.users u
WHERE c.type = 'channel'
ON CONFLICT (chat_id, user_id) DO NOTHING;

-- 2. Atualizar a trigger handle_new_user para adicionar os novos usuários aos canais
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

  -- NOVO: Inserir usuário em todos os canais existentes
  INSERT INTO public.chat_members (chat_id, user_id, role)
  SELECT id, NEW.id, 'member'
  FROM public.chats
  WHERE type = 'channel'
  ON CONFLICT (chat_id, user_id) DO NOTHING;

  IF v_is_active = false THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;
