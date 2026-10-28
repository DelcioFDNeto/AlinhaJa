-- ============================================================
-- posting_permission deixa de ser regra só de tela  (F-02)
--
-- `channels.posting_permission` distingue 'everyone' de 'admins' e é o
-- que faz um canal de avisos ser um mural. Mas a regra vivia apenas no
-- getter `canPost` do ActiveChannelNotifier (Dart): a policy de INSERT
-- em `channel_messages` valida somente membresia. Qualquer membro
-- publicava num canal de avisos por chamada REST direta — a UI escondia
-- o compositor, o banco aceitava a escrita.
--
-- O molde aqui é o mesmo já usado com acerto em
-- 20260810100000_announcement_rbac.sql: policy RESTRICTIVE, que combina
-- por AND com as permissivas existentes. Recriar a permissiva "Membros
-- enviam mensagens" seria pior — ela já foi reescrita por outras
-- migrations e o texto vigente no banco pode não bater com o do
-- repositório.
--
-- A função espelha `canPost` do app, incluindo o caso legado do tipo de
-- canal restrito ('avisos'), para que a trava do banco não seja mais
-- estrita que a tela e passe a recusar quem hoje publica legitimamente.
-- ============================================================

CREATE OR REPLACE FUNCTION public.can_post_in_channel(p_channel_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_posting TEXT;
  v_type TEXT;
  v_role_level TEXT;
  v_department TEXT;
  v_channel_role TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT COALESCE(NULLIF(TRIM(c.posting_permission), ''), 'everyone'),
         LOWER(COALESCE(c.type, 'comum'))
    INTO v_posting, v_type
  FROM public.channels c
  WHERE c.id = p_channel_id;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- Canal aberto libera todo membro. 'all' é sinônimo legado de
  -- 'everyone' (ver active_channel_provider). Os tipos legados que o
  -- getter `isRestricted` reconhece são 'announcement' e 'restricted' —
  -- NÃO 'avisos', que é só o rótulo do seed. Espelhar o app aqui é
  -- essencial: uma trava mais estrita que a tela recusaria quem hoje
  -- publica legitimamente, e o erro apareceria sem explicação.
  IF v_posting IN ('everyone', 'all')
     AND v_type NOT IN ('announcement', 'restricted') THEN
    RETURN TRUE;
  END IF;

  -- Daqui para baixo o canal é restrito: só cargo gerencial publica.
  SELECT u.role_level::TEXT, LOWER(COALESCE(u.department_id::TEXT, ''))
    INTO v_role_level, v_department
  FROM public.users u
  WHERE u.id = v_user_id
    AND COALESCE(u.is_active, TRUE) = TRUE;

  IF v_role_level IN ('admin', 'super_admin') THEN
    RETURN TRUE;
  END IF;

  -- Governança root do departamento de TI, como no app.
  IF v_department = 'ti' THEN
    RETURN TRUE;
  END IF;

  SELECT LOWER(COALESCE(cm.role, 'viewer'))
    INTO v_channel_role
  FROM public.channel_members cm
  WHERE cm.channel_id = p_channel_id
    AND cm.user_id = v_user_id;

  RETURN v_channel_role = 'admin';
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_post_in_channel(UUID) TO authenticated;

COMMENT ON FUNCTION public.can_post_in_channel(UUID) IS
  'Espelha o getter canPost do app: canal aberto libera todo membro, canal '
  'restrito (posting_permission=admins ou type=avisos) exige admin/super_admin, '
  'TI, ou papel admin no próprio canal.';

DROP POLICY IF EXISTS "Publicacao respeita posting_permission" ON public.channel_messages;
CREATE POLICY "Publicacao respeita posting_permission"
  ON public.channel_messages
  AS RESTRICTIVE
  FOR INSERT
  WITH CHECK (
    public.can_post_in_channel(channel_id)
  );
