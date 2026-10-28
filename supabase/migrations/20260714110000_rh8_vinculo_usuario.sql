-- ============================================================
-- RH-8 / F1.2 — Vínculo Funcionário ↔ Usuário do app
-- (PLANO-RH-COMPLETO.md, Onda 1).
--
-- funcionario.user_id já existe desde 20260709100000; aqui entram
-- a garantia de unicidade 1:1, as RPCs auditadas de vincular /
-- desvincular (rh_admin) e a view que alimenta a busca de usuários
-- vinculáveis na ficha do funcionário.
-- ============================================================

-- ── 1. Unicidade 1:1 (um usuário ↔ um funcionário ativo) ─────
CREATE UNIQUE INDEX IF NOT EXISTS uq_funcionario_user
  ON public.funcionario(user_id)
  WHERE user_id IS NOT NULL AND deleted_at IS NULL;

-- ── 2. View de suporte à busca (usuários da org + flag) ──────
-- security_invoker: herda a RLS de users (org lê a própria org) e
-- de funcionario (org lê a própria org), sem vazar cross-tenant.
CREATE OR REPLACE VIEW public.org_users_vinculaveis
WITH (security_invoker = true) AS
SELECT
  u.id,
  u.organization_id,
  u.full_name,
  u.email,
  u.avatar_url,
  f.id AS funcionario_id,
  (f.id IS NOT NULL) AS ja_vinculado
FROM public.users u
LEFT JOIN public.funcionario f
  ON f.user_id = u.id AND f.deleted_at IS NULL
WHERE u.is_active = true;

-- ── 3. RPC: vincular usuário à ficha do funcionário ──────────
CREATE OR REPLACE FUNCTION public.rh_vincular_usuario(
  p_funcionario_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_atual uuid;
BEGIN
  IF NOT public.fn_is_rh_admin() THEN
    RAISE EXCEPTION 'Apenas administradores do RH podem vincular usuários';
  END IF;

  SELECT f.user_id INTO v_atual
  FROM public.funcionario f
  WHERE f.id = p_funcionario_id
    AND f.organization_id = v_org
    AND f.deleted_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado';
  END IF;
  IF v_atual IS NOT NULL THEN
    RAISE EXCEPTION 'Este funcionário já está vinculado a um usuário — desvincule primeiro';
  END IF;

  -- Usuário precisa ser da MESMA organização e estar ativo
  IF NOT EXISTS (SELECT 1 FROM public.users u
                 WHERE u.id = p_user_id
                   AND u.organization_id = v_org
                   AND u.is_active = true) THEN
    RAISE EXCEPTION 'Usuário não encontrado na organização';
  END IF;

  -- Unicidade 1:1 (o índice uq_funcionario_user é a defesa final)
  IF EXISTS (SELECT 1 FROM public.funcionario f
             WHERE f.user_id = p_user_id AND f.deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Este usuário já está vinculado a outro funcionário';
  END IF;

  UPDATE public.funcionario
     SET user_id = p_user_id, updated_by = auth.uid()
   WHERE id = p_funcionario_id;

  INSERT INTO public.rh_access_log
    (organization_id, funcionario_id, usuario_id, acao, detalhes)
  VALUES (v_org, p_funcionario_id, auth.uid(), 'vinculou_usuario',
          jsonb_build_object('user_id', p_user_id));
END;
$$;
REVOKE ALL ON FUNCTION public.rh_vincular_usuario(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_vincular_usuario(uuid, uuid) TO authenticated;

-- ── 4. RPC: desvincular ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rh_desvincular_usuario(p_funcionario_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_atual uuid;
BEGIN
  IF NOT public.fn_is_rh_admin() THEN
    RAISE EXCEPTION 'Apenas administradores do RH podem desvincular usuários';
  END IF;

  SELECT f.user_id INTO v_atual
  FROM public.funcionario f
  WHERE f.id = p_funcionario_id
    AND f.organization_id = v_org
    AND f.deleted_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado';
  END IF;
  IF v_atual IS NULL THEN
    RETURN; -- já está desvinculado, nada a fazer
  END IF;

  UPDATE public.funcionario
     SET user_id = NULL, updated_by = auth.uid()
   WHERE id = p_funcionario_id;

  INSERT INTO public.rh_access_log
    (organization_id, funcionario_id, usuario_id, acao, detalhes)
  VALUES (v_org, p_funcionario_id, auth.uid(), 'desvinculou_usuario',
          jsonb_build_object('user_id', v_atual));
END;
$$;
REVOKE ALL ON FUNCTION public.rh_desvincular_usuario(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_desvincular_usuario(uuid) TO authenticated;
