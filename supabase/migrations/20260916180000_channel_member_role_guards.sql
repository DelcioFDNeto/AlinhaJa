-- ============================================================
-- Guardas de papel e de empresa na gestão de workspaces (16/09/2026 — v1.3.9)
--
-- Achados na replicação da v1.3.9 para o AlinhaJá. Migration idêntica nos
-- dois forks.
--
-- 1. Rebaixar o admin pela porta de "adicionar membro"
--    `add_channel_member` faz upsert do papel. Promover a admin exigia nível
--    admin, mas REBAIXAR um admin (chamar com 'viewer' para quem já é admin)
--    exigia só o nível de gestor. Um editor tirava o admin — inclusive o
--    único, o que anulava a sucessão obrigatória de `leave_channel`.
--
-- 2. Remover o único admin
--    `remove_channel_member` removia o único admin de um canal com outros
--    membros, deixando o workspace sem administração.
--
-- 3. Gestão entre empresas
--    `can_manage_workspace` não conferia a empresa do canal. As funções que a
--    usam são SECURITY DEFINER e não passam pela policy `tenant_isolation`:
--    com o UUID de um canal de outra empresa, um admin adicionava membros,
--    editava ou arquivava o workspace alheio. No Fluxy (empresa única) a
--    checagem é sempre verdadeira; no AlinhaJá é o que isola os tenants. O
--    dono da plataforma segue global, e `fn_current_org()` já considera a
--    empresa em que ele está atuando.
-- ============================================================

-- ── 1. can_manage_workspace com isolamento por empresa ──────
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
  v_visibility TEXT := 'public';
  v_created_by UUID;
  v_channel_org UUID;
  v_channel_role TEXT;
BEGIN
  IF auth.uid() IS NULL OR p_channel_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT c.visibility, c.created_by, c.organization_id
  INTO v_visibility, v_created_by, v_channel_org
  FROM public.channels c
  WHERE c.id = p_channel_id;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- Canal de outra empresa: ninguém gere, exceto o dono da plataforma.
  IF v_channel_org IS DISTINCT FROM public.fn_current_org()
     AND NOT public.fn_is_platform_owner() THEN
    RETURN FALSE;
  END IF;

  SELECT role_level::TEXT, department_id
  INTO v_role, v_department_id
  FROM public.users
  WHERE id = auth.uid()
    AND COALESCE(is_active, TRUE) = TRUE;

  SELECT cm.role
  INTO v_channel_role
  FROM public.channel_members cm
  WHERE cm.channel_id = p_channel_id
    AND cm.user_id = auth.uid();

  -- Dono do canal: para ações de admin, só criador ou admin do canal; para as
  -- demais, admin ou editor.
  IF p_min_role = 'admin' THEN
    v_is_owner := (v_created_by = auth.uid() OR v_channel_role = 'admin');
  ELSE
    v_is_owner := (v_created_by = auth.uid() OR v_channel_role IN ('admin', 'editor'));
  END IF;

  -- Papel global. Em canal privado só admin e super_admin têm override;
  -- gestores gerais precisam ser membros.
  IF v_visibility = 'private' THEN
    v_has_global_role := COALESCE(v_role IN ('super_admin', 'admin'), FALSE);
  ELSIF p_min_role = 'admin' THEN
    v_has_global_role := COALESCE(
      v_role IN ('super_admin', 'admin', 'ti_admin', 'director')
      OR v_department_id = 'ti',
      FALSE
    );
  ELSE
    v_has_global_role := COALESCE(
      v_role IN ('super_admin', 'admin', 'manager', 'ti_admin', 'director', 'store_leader', 'coordinator')
      OR v_department_id = 'ti',
      FALSE
    );
  END IF;

  RETURN COALESCE(v_is_owner, FALSE) OR v_has_global_role;
END;
$$;

-- ── 2. add_channel_member: rebaixar admin exige admin ───────
CREATE OR REPLACE FUNCTION public.add_channel_member(
  p_channel_id UUID,
  p_user_id UUID,
  p_role TEXT DEFAULT 'viewer'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT := LOWER(COALESCE(p_role, 'viewer'));
  v_current TEXT;
BEGIN
  IF v_role NOT IN ('admin', 'editor', 'viewer') THEN
    v_role := 'viewer';
  END IF;

  SELECT role INTO v_current
  FROM public.channel_members
  WHERE channel_id = p_channel_id AND user_id = p_user_id;

  -- Mexer em admin — promover OU rebaixar — é ação de admin.
  IF v_role = 'admin' OR v_current = 'admin' THEN
    IF NOT public.can_manage_workspace(p_channel_id, 'admin') THEN
      RAISE EXCEPTION 'Acesso Negado: apenas administradores podem nomear ou rebaixar administradores.';
    END IF;
  ELSIF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para adicionar membros.';
  END IF;

  IF v_current = 'admin' AND v_role <> 'admin'
     AND public.channel_member_is_sole_admin(p_channel_id, p_user_id) THEN
    RAISE EXCEPTION 'Promova outro membro a administrador antes de rebaixar o único administrador do canal.';
  END IF;

  INSERT INTO public.channel_members (channel_id, user_id, role)
  VALUES (p_channel_id, p_user_id, v_role)
  ON CONFLICT ON CONSTRAINT channel_members_pkey DO UPDATE SET role = EXCLUDED.role;
END;
$$;

-- ── 3. remove_channel_member: não deixa o canal sem admin ───
CREATE OR REPLACE FUNCTION public.remove_channel_member(
  p_channel_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_role TEXT;
BEGIN
  SELECT role INTO v_target_role
  FROM public.channel_members
  WHERE channel_id = p_channel_id AND user_id = p_user_id;

  IF v_target_role = 'admin' THEN
    IF NOT public.can_manage_workspace(p_channel_id, 'admin') THEN
      RAISE EXCEPTION 'Acesso Negado: apenas administradores podem remover outros administradores.';
    END IF;
    IF public.channel_member_is_sole_admin(p_channel_id, p_user_id) THEN
      RAISE EXCEPTION 'Promova outro membro a administrador antes de remover o único administrador do canal.';
    END IF;
  ELSIF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para remover membros.';
  END IF;

  DELETE FROM public.channel_members
  WHERE channel_id = p_channel_id
    AND user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.can_manage_workspace(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_workspace(UUID, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.add_channel_member(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_channel_member(UUID, UUID, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.remove_channel_member(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_channel_member(UUID, UUID) TO authenticated;
