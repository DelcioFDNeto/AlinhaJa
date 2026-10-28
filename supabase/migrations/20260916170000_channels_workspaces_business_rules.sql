-- ============================================================
-- Regras de Negócio e Governança (16/09/2026 — v1.3.9)
--
-- 1. Comentários em cards de workflow pelo solicitante
--    A policy anterior só permitia que o solicitante comentasse após
--    a conclusão do card (`is_final = TRUE`), impedindo-o de responder
--    em etapas de interação direta como "Aguardando Solicitante".
--    Agora qualquer participante do canal (inclusive o solicitante) pode
--    inserir comentários em cards do canal.
--
-- 2. Governança e privacidade de workspaces (`can_manage_workspace`)
--    - Em canais privados (`visibility = 'private'`), gestores gerais
--      (manager, store_leader, coordinator) NÃO possuem bypass global;
--      apenas `super_admin` e `admin` globais ou membros nomeados do canal.
--    - `editor` no canal só atende `p_min_role = 'manager'`/`'editor'`. Para
--      operações com `p_min_role = 'admin'`, apenas `admin` do canal (ou
--      criador) qualifica como dono.
--
-- 3. Proteção em `add_channel_member` e `remove_channel_member`
--    - Promover a `admin` exige obrigatoriamente `can_manage_workspace(..., 'admin')`.
--      Um `editor` não pode autopromover nem promover terceiros a `admin`.
--    - Remover um `admin` exige permissão de `admin`.
-- ============================================================

-- ── 1. Comentários de Workflow ──────────────────────────────
DROP POLICY IF EXISTS "Participantes inserem comentarios respeitando solicitante" ON public.workflow_card_comments;
DROP POLICY IF EXISTS "Participantes inserem comentarios" ON public.workflow_card_comments;

CREATE POLICY "Participantes inserem comentarios"
  ON public.workflow_card_comments FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.workflow_cards wc
      JOIN public.channel_members cm ON cm.channel_id = wc.channel_id
      WHERE wc.id = workflow_card_comments.card_id
        AND cm.user_id = auth.uid()
    )
  );

-- ── 2. Governança de Workspaces e Canais Privados ────────────
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
  v_channel_role TEXT;
BEGIN
  IF auth.uid() IS NULL OR p_channel_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT role_level::TEXT, department_id
  INTO v_role, v_department_id
  FROM public.users
  WHERE id = auth.uid()
    AND COALESCE(is_active, TRUE) = TRUE;

  SELECT c.visibility, c.created_by
  INTO v_visibility, v_created_by
  FROM public.channels c
  WHERE c.id = p_channel_id;

  SELECT cm.role
  INTO v_channel_role
  FROM public.channel_members cm
  WHERE cm.channel_id = p_channel_id
    AND cm.user_id = auth.uid();

  -- Membro dono/admin do canal:
  -- Se p_min_role = 'admin', só o criador do canal ou quem tem role = 'admin' no canal qualifica.
  -- Se p_min_role = 'manager' ou 'editor', quem tem role IN ('admin', 'editor') qualifica.
  IF p_min_role = 'admin' THEN
    v_is_owner := (v_created_by = auth.uid() OR v_channel_role = 'admin');
  ELSE
    v_is_owner := (v_created_by = auth.uid() OR v_channel_role IN ('admin', 'editor'));
  END IF;

  -- Papel global:
  -- Se o canal for privado ('private'):
  -- APENAS super_admin e admin do sistema têm override global.
  -- Gestores gerais (manager, coordinator, store_leader) NÃO têm bypass em canais privados dos quais não são membros!
  IF v_visibility = 'private' THEN
    v_has_global_role := COALESCE(v_role IN ('super_admin', 'admin'), FALSE);
  ELSE
    -- Canal público:
    IF p_min_role = 'admin' THEN
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
  END IF;

  RETURN v_is_owner OR v_has_global_role;
END;
$$;

-- ── 3. add_channel_member e remove_channel_member ───────────
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
BEGIN
  IF v_role NOT IN ('admin', 'editor', 'viewer') THEN
    v_role := 'viewer';
  END IF;

  -- Se está promovendo a admin, o executor OBRIGATORIAMENTE precisa ter permissão de admin:
  IF v_role = 'admin' THEN
    IF NOT public.can_manage_workspace(p_channel_id, 'admin') THEN
      RAISE EXCEPTION 'Acesso Negado: apenas administradores podem nomear administradores.';
    END IF;
  ELSE
    IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
      RAISE EXCEPTION 'Acesso Negado: sem permissão para adicionar membros.';
    END IF;
  END IF;

  INSERT INTO public.channel_members (channel_id, user_id, role)
  VALUES (p_channel_id, p_user_id, v_role)
  ON CONFLICT ON CONSTRAINT channel_members_pkey DO UPDATE SET role = EXCLUDED.role;
END;
$$;

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

  -- Se o membro a ser removido for admin, exige que o executor seja admin:
  IF v_target_role = 'admin' THEN
    IF NOT public.can_manage_workspace(p_channel_id, 'admin') THEN
      RAISE EXCEPTION 'Acesso Negado: apenas administradores podem remover outros administradores.';
    END IF;
  ELSE
    IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
      RAISE EXCEPTION 'Acesso Negado: sem permissão para remover membros.';
    END IF;
  END IF;

  DELETE FROM public.channel_members
  WHERE channel_id = p_channel_id
    AND user_id = p_user_id;
END;
$$;
