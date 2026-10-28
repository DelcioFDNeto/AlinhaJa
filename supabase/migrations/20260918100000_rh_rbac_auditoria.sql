-- =============================================================
-- Auditoria RH + RBAC (2026-09-18)
-- =============================================================
-- 1. RPCs administrativas: admin comum não age sobre super_admin.
-- 2. Ponto: a batida do próprio colaborador usa a hora do servidor.
-- 3. Holerite: o colaborador só registra a visualização.
-- 4. rh_soft_delete_candidato: o app chamava uma RPC inexistente.
-- 5. RBAC: troca de permissões de perfil atômica e escrita em
--    rbac_user_roles restrita à própria organização.
-- =============================================================

-- ── 1. Hierarquia nas RPCs administrativas ───────────────────
-- fn_assert_same_org é chamada por TODAS as RPCs que um admin executa
-- sobre outro usuário (editar, trocar nível, redefinir senha, ativar/
-- desativar, recusar). Nenhuma olhava o nível do ALVO: um admin comum
-- redefinia a senha de um super_admin e entrava na conta dele, ou o
-- rebaixava. A guarda passa a cobrir também a hierarquia.
CREATE OR REPLACE FUNCTION public.fn_assert_same_org(p_target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- O dono da plataforma administra todas as organizações pelo console.
  IF public.fn_is_platform_owner() THEN
    RETURN;
  END IF;

  -- `users.organization_id` é NOT NULL e fn_current_org() vem da sessão.
  -- Alvo inexistente e alvo de outra organização caem no mesmo erro, sem
  -- revelar qual dos dois é o caso.
  IF NOT EXISTS (
    SELECT 1 FROM public.users t
    WHERE t.id = p_target_user_id
      AND t.organization_id = public.fn_current_org()
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não pertence à sua organização.';
  END IF;

  -- Só um super_admin age sobre outro super_admin.
  IF EXISTS (
    SELECT 1 FROM public.users t
    WHERE t.id = p_target_user_id AND t.role_level = 'super_admin'
  ) AND NOT EXISTS (
    SELECT 1 FROM public.users c
    WHERE c.id = auth.uid() AND c.role_level = 'super_admin'
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: apenas o Super Admin pode alterar outro Super Admin.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_assert_same_org(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_assert_same_org(UUID) TO authenticated;

-- ── 2. Ponto com a hora do servidor ──────────────────────────
-- O app gravava DateTime.now() do aparelho: bastava mudar o relógio do
-- celular (ou chamar a API) para registrar batida em horário forjado.
-- Ajuste manual com hora informada continua sendo do RH — mas não no
-- próprio ponto. A organização também vem do funcionário, não do cliente.
CREATE OR REPLACE FUNCTION public.fn_tg_rh_ponto_hora_servidor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.fn_is_rh()
     OR public.fn_is_own_funcionario(NEW.funcionario_id) THEN
    NEW.data_hora := now();
    SELECT f.organization_id INTO NEW.organization_id
      FROM public.funcionario f
     WHERE f.id = NEW.funcionario_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_rh_ponto_hora_servidor ON public.rh_ponto_registro;
CREATE TRIGGER tg_rh_ponto_hora_servidor
  BEFORE INSERT ON public.rh_ponto_registro
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_rh_ponto_hora_servidor();

-- ── 3. Holerite: colaborador só registra a visualização ──────
-- A política "Funcionário atualiza visualizacao" não restringe colunas:
-- o colaborador alterava proventos/descontos (dados_gerados), o PDF e a
-- competência do próprio holerite — e o RH lê a mesma linha.
CREATE OR REPLACE FUNCTION public.fn_tg_rh_holerite_somente_visualizacao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_esperado public.rh_holerite;
BEGIN
  IF public.fn_is_rh() THEN
    RETURN NEW;
  END IF;

  v_esperado := OLD;
  v_esperado.data_visualizacao := NEW.data_visualizacao;
  IF NEW IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'O colaborador só pode registrar a visualização do holerite.'
      USING ERRCODE = '42501';
  END IF;

  -- Uma vez, com a hora do servidor.
  NEW.data_visualizacao := COALESCE(OLD.data_visualizacao, now());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_rh_holerite_somente_visualizacao ON public.rh_holerite;
CREATE TRIGGER tg_rh_holerite_somente_visualizacao
  BEFORE UPDATE ON public.rh_holerite
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_rh_holerite_somente_visualizacao();

-- ── 4. Exclusão (soft delete) de candidato ───────────────────
-- A tela "Excluir candidato" chamava esta RPC, que nunca foi criada.
-- DROP antes: se existir no banco com outro retorno, o REPLACE falharia.
DROP FUNCTION IF EXISTS public.rh_soft_delete_candidato(uuid);
CREATE FUNCTION public.rh_soft_delete_candidato(p_candidato_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Apenas o RH pode excluir candidatos.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.candidato
     SET deleted_at = now(),
         deleted_by = auth.uid()
   WHERE id = p_candidato_id
     AND organization_id = public.fn_current_org()
     AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidato não encontrado.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.rh_soft_delete_candidato(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_soft_delete_candidato(uuid) TO authenticated;

-- ── 5a. Permissões de perfil trocadas numa transação ─────────
-- O app apagava as permissões do perfil e inseria as novas em duas
-- requisições: se a segunda falhasse, o perfil ficava sem permissão
-- nenhuma — e todos os usuários dele perdiam o acesso.
CREATE OR REPLACE FUNCTION public.rbac_set_role_permissions(
  p_role_id uuid, p_permission_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.fn_is_admin() THEN
    RAISE EXCEPTION 'Apenas administradores podem alterar perfis';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.rbac_roles
                 WHERE id = p_role_id
                   AND organization_id = public.fn_current_org()) THEN
    RAISE EXCEPTION 'Perfil não encontrado';
  END IF;

  DELETE FROM public.rbac_role_permissions WHERE role_id = p_role_id;

  INSERT INTO public.rbac_role_permissions (role_id, permission_id)
  SELECT p_role_id, p.id
  FROM public.rbac_permissions p
  WHERE p.id = ANY (COALESCE(p_permission_ids, '{}'::uuid[]))
  ON CONFLICT DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.rbac_set_role_permissions(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rbac_set_role_permissions(uuid, uuid[]) TO authenticated;

-- ── 5b. rbac_user_roles só na própria organização ────────────
-- A política de escrita exigia apenas fn_is_admin(): um admin gravava
-- perfis em usuários de OUTRA organização, inclusive perfis de lá.
DROP POLICY IF EXISTS "Gestão de user_roles por admin" ON public.rbac_user_roles;
CREATE POLICY "Gestão de user_roles por admin"
  ON public.rbac_user_roles FOR ALL
  USING (
    public.fn_is_admin()
    AND user_id IN (SELECT id FROM public.users
                    WHERE organization_id = public.fn_current_org())
  )
  WITH CHECK (
    public.fn_is_admin()
    AND user_id IN (SELECT id FROM public.users
                    WHERE organization_id = public.fn_current_org())
    AND role_id IN (SELECT id FROM public.rbac_roles
                    WHERE organization_id = public.fn_current_org())
  );
