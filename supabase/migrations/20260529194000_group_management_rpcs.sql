-- Migration: 20260529194000_group_management_rpcs.sql
-- Description: Add admingroup column to chat_members and update/create secure group management RPCs.

-- 1. Add Group Admin Flag to chat_members
ALTER TABLE public.chat_members ADD COLUMN IF NOT EXISTS admingroup BOOLEAN NOT NULL DEFAULT false;

-- 2. Secure Group Chat Creation (Sets creator as admingroup = true)
CREATE OR REPLACE FUNCTION public.create_group_chat(
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
  INSERT INTO public.chats (type, name, description, created_by)
  VALUES ('group', p_name, p_description, v_user_id)
  RETURNING id INTO v_chat_id;

  -- Adiciona o criador como membro e admin do grupo (admingroup = true)
  INSERT INTO public.chat_members (chat_id, user_id, admingroup)
  VALUES (v_chat_id, v_user_id, true);

  -- Adiciona os membros convidados
  FOREACH v_member_id IN ARRAY p_member_ids LOOP
    IF v_member_id != v_user_id THEN
      INSERT INTO public.chat_members (chat_id, user_id, admingroup)
      VALUES (v_chat_id, v_member_id, false)
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  -- Mensagem de sistema
  INSERT INTO public.messages (chat_id, sender_id, content, content_type, metadata)
  VALUES (v_chat_id, v_user_id, 'criou o grupo', 'text',
    jsonb_build_object('is_system', true));

  RETURN v_chat_id;
END;
$$;

-- 3. Add Member Securely (requires admingroup = true)
CREATE OR REPLACE FUNCTION public.add_group_member(p_chat_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_chat_type TEXT;
  v_is_group_admin BOOLEAN;
BEGIN
  SELECT type INTO v_chat_type FROM public.chats WHERE id = p_chat_id;
  IF v_chat_type != 'group' THEN
    RAISE EXCEPTION 'Não é um chat de grupo';
  END IF;

  SELECT admingroup INTO v_is_group_admin FROM public.chat_members
    WHERE chat_id = p_chat_id AND user_id = v_user_id;
  IF v_is_group_admin IS NOT TRUE THEN
    RAISE EXCEPTION 'Apenas administradores do grupo podem adicionar membros';
  END IF;

  INSERT INTO public.chat_members (chat_id, user_id, admingroup)
  VALUES (p_chat_id, p_user_id, false)
  ON CONFLICT DO NOTHING;

  -- Mensagem de sistema
  INSERT INTO public.messages (chat_id, sender_id, content, content_type, metadata)
  VALUES (p_chat_id, v_user_id,
    'adicionou ' || (SELECT full_name FROM public.users WHERE id = p_user_id),
    'text', jsonb_build_object('is_system', true));
END;
$$;

-- 4. Remove Member Securely (requires admingroup = true or user removing self)
CREATE OR REPLACE FUNCTION public.remove_group_member(p_chat_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_chat_type TEXT;
  v_is_group_admin BOOLEAN;
BEGIN
  SELECT type INTO v_chat_type FROM public.chats WHERE id = p_chat_id;
  IF v_chat_type != 'group' THEN
    RAISE EXCEPTION 'Não é um chat de grupo';
  END IF;

  SELECT admingroup INTO v_is_group_admin FROM public.chat_members
    WHERE chat_id = p_chat_id AND user_id = v_user_id;

  -- Permite se é admin do grupo OU se o próprio membro está saindo
  IF v_is_group_admin IS NOT TRUE AND v_user_id != p_user_id THEN
    RAISE EXCEPTION 'Apenas administradores do grupo podem remover membros';
  END IF;

  DELETE FROM public.chat_members
    WHERE chat_id = p_chat_id AND user_id = p_user_id;

  -- Mensagem de sistema
  IF v_user_id = p_user_id THEN
    INSERT INTO public.messages (chat_id, sender_id, content, content_type, metadata)
    VALUES (p_chat_id, v_user_id, 'saiu do grupo', 'text',
      jsonb_build_object('is_system', true));
  ELSE
    INSERT INTO public.messages (chat_id, sender_id, content, content_type, metadata)
    VALUES (p_chat_id, v_user_id,
      'removeu ' || (SELECT full_name FROM public.users WHERE id = p_user_id),
      'text', jsonb_build_object('is_system', true));
  END IF;
END;
$$;

-- 5. Secure Group Detail Updates (requires admingroup = true)
CREATE OR REPLACE FUNCTION public.update_group_info(
  p_chat_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_avatar_url TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_chat_type TEXT;
  v_is_group_admin BOOLEAN;
  v_old_name TEXT;
  v_old_desc TEXT;
  v_old_avatar TEXT;
  v_sys_msg TEXT := 'alterou as configurações do grupo';
BEGIN
  SELECT type, name, description, avatar_url 
    INTO v_chat_type, v_old_name, v_old_desc, v_old_avatar 
    FROM public.chats 
    WHERE id = p_chat_id;

  IF v_chat_type != 'group' THEN
    RAISE EXCEPTION 'Não é um chat de grupo';
  END IF;

  SELECT admingroup INTO v_is_group_admin FROM public.chat_members
    WHERE chat_id = p_chat_id AND user_id = v_user_id;
  IF v_is_group_admin IS NOT TRUE THEN
    RAISE EXCEPTION 'Apenas administradores do grupo podem atualizar informações';
  END IF;

  -- Customize system message
  IF v_old_name IS DISTINCT FROM p_name THEN
    v_sys_msg := 'alterou o nome do grupo para "' || p_name || '"';
  ELSIF v_old_avatar IS DISTINCT FROM p_avatar_url THEN
    v_sys_msg := 'alterou a imagem do grupo';
  ELSIF v_old_desc IS DISTINCT FROM p_description THEN
    v_sys_msg := 'alterou a descrição do grupo';
  END IF;

  UPDATE public.chats
  SET
    name = p_name,
    description = p_description,
    avatar_url = p_avatar_url
  WHERE id = p_chat_id;

  -- System message insert
  INSERT INTO public.messages (chat_id, sender_id, content, content_type, metadata)
  VALUES (p_chat_id, v_user_id, v_sys_msg, 'text',
    jsonb_build_object('is_system', true));
END;
$$;

-- 6. Manage Group Roles (Promotion / Demotion)
CREATE OR REPLACE FUNCTION public.set_group_member_role(
  p_chat_id UUID,
  p_user_id UUID,
  p_role BOOLEAN
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_chat_type TEXT;
  v_is_group_admin BOOLEAN;
  v_target_name TEXT;
  v_sys_msg TEXT;
BEGIN
  SELECT type INTO v_chat_type FROM public.chats WHERE id = p_chat_id;
  IF v_chat_type != 'group' THEN
    RAISE EXCEPTION 'Não é um chat de grupo';
  END IF;

  SELECT admingroup INTO v_is_group_admin FROM public.chat_members
    WHERE chat_id = p_chat_id AND user_id = v_caller_id;
  IF v_is_group_admin IS NOT TRUE THEN
    RAISE EXCEPTION 'Apenas administradores do grupo podem gerenciar privilégios';
  END IF;

  UPDATE public.chat_members
  SET admingroup = p_role
  WHERE chat_id = p_chat_id AND user_id = p_user_id;

  SELECT full_name INTO v_target_name FROM public.users WHERE id = p_user_id;

  IF p_role = true THEN
    v_sys_msg := 'promoveu ' || v_target_name || ' a administrador do grupo';
  ELSE
    v_sys_msg := 'removeu os privilégios de administrador de ' || v_target_name;
  END IF;

  -- System message insert
  INSERT INTO public.messages (chat_id, sender_id, content, content_type, metadata)
  VALUES (p_chat_id, v_caller_id, v_sys_msg, 'text',
    jsonb_build_object('is_system', true));
END;
$$;
