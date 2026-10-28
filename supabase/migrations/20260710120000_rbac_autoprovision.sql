-- ============================================================
-- RBAC — Auto-provisionamento (fecha a lacuna crítica)
-- Antes: fn_setup_default_roles existia mas nunca era chamada, o
-- perfil "Colaborador" nascia SEM permissões e nenhum usuário era
-- vinculado a um perfil → a sidebar (que lê myPermissionsProvider)
-- ficava vazia para todos, inclusive super_admin.
--
-- Agora:
--   • 4 perfis-padrão por org com permissões coerentes
--   • unicidade (organization_id, name) → idempotência real
--   • atribuição automática de perfil por role_level/hr_role
--   • backfill de orgs e usuários existentes
--   • triggers para novas orgs e novos usuários
-- ============================================================

-- ── 0. Idempotência: nome de perfil único por org ────────────
-- Remove eventuais duplicatas antes de criar a constraint.
DELETE FROM public.rbac_roles a
USING public.rbac_roles b
WHERE a.ctid < b.ctid
  AND a.organization_id = b.organization_id
  AND a.name = b.name;

ALTER TABLE public.rbac_roles
  DROP CONSTRAINT IF EXISTS uq_rbac_roles_org_name;
ALTER TABLE public.rbac_roles
  ADD CONSTRAINT uq_rbac_roles_org_name UNIQUE (organization_id, name);

-- ── 1. Helpers ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_ensure_role(
  p_org uuid, p_name text, p_desc text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.rbac_roles (organization_id, name, description, is_system)
  VALUES (p_org, p_name, p_desc, true)
  ON CONFLICT (organization_id, name) DO UPDATE SET description = EXCLUDED.description
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Concede um conjunto de permissões (['module:action', ...]) a um perfil
CREATE OR REPLACE FUNCTION public.fn_grant_perms(p_role uuid, p_perms text[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  INSERT INTO public.rbac_role_permissions (role_id, permission_id)
  SELECT p_role, pm.id
  FROM public.rbac_permissions pm
  WHERE (pm.module || ':' || pm.action) = ANY (p_perms)
  ON CONFLICT DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_ensure_role(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_grant_perms(uuid, text[]) FROM PUBLIC, anon, authenticated;

-- ── 2. fn_setup_default_roles: 4 perfis com permissões ───────
CREATE OR REPLACE FUNCTION public.fn_setup_default_roles(p_org_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_super  uuid;
  v_rh     uuid;
  v_gestor uuid;
  v_colab  uuid;
BEGIN
  v_super  := public.fn_ensure_role(p_org_id, 'Super Admin',
                'Acesso total ao sistema, painel e módulos sensíveis');
  v_rh     := public.fn_ensure_role(p_org_id, 'RH',
                'Gestão completa de Recursos Humanos');
  v_gestor := public.fn_ensure_role(p_org_id, 'Gestor',
                'Gestão de equipe com visão de RH limitada');
  v_colab  := public.fn_ensure_role(p_org_id, 'Colaborador',
                'Acesso padrão de funcionário');

  -- Super Admin: todas as permissões existentes
  INSERT INTO public.rbac_role_permissions (role_id, permission_id)
  SELECT v_super, id FROM public.rbac_permissions
  ON CONFLICT DO NOTHING;

  -- Colaborador: comunicação básica
  PERFORM public.fn_grant_perms(v_colab, ARRAY[
    'comunicacao_canais:view', 'comunicacao_conversas:view',
    'comunicacao_chamadas:view']);

  -- Gestor: comunicação + visão de RH + abrir chamados
  PERFORM public.fn_grant_perms(v_gestor, ARRAY[
    'comunicacao_canais:view', 'comunicacao_conversas:view',
    'comunicacao_chamadas:view',
    'rh_funcionarios:view', 'rh_documentos:view', 'rh_alertas:view',
    'helpdesk:view']);

  -- RH: todo o módulo de RH + comunicação + helpdesk
  PERFORM public.fn_grant_perms(v_rh, ARRAY[
    'comunicacao_canais:view', 'comunicacao_conversas:view',
    'comunicacao_chamadas:view',
    'rh_banco_talentos:view', 'rh_banco_talentos:manage',
    'rh_funcionarios:view', 'rh_funcionarios:manage',
    'rh_documentos:view', 'rh_documentos:manage',
    'rh_onboarding:view', 'rh_onboarding:manage',
    'rh_alertas:view',
    'helpdesk:view', 'helpdesk:manage']);
END;
$$;
REVOKE ALL ON FUNCTION public.fn_setup_default_roles(uuid) FROM PUBLIC, anon, authenticated;

-- ── 3. Atribuição de perfil-padrão por usuário ───────────────
-- Mapeia role_level/hr_role → perfil dinâmico. Só atribui se o
-- usuário ainda não tiver nenhum perfil (não sobrescreve ajustes
-- manuais feitos no Painel Admin).
CREATE OR REPLACE FUNCTION public.fn_assign_default_rbac_role(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_org uuid; v_level text; v_hr public.hr_role;
  v_role_name text; v_role_id uuid;
BEGIN
  SELECT organization_id, role_level, hr_role
    INTO v_org, v_level, v_hr
  FROM public.users WHERE id = p_user_id;
  IF v_org IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM public.rbac_user_roles WHERE user_id = p_user_id) THEN
    RETURN;  -- já tem perfil; respeita o que o admin definiu
  END IF;

  PERFORM public.fn_setup_default_roles(v_org);

  v_role_name := CASE
    WHEN v_level IN ('super_admin', 'admin')      THEN 'Super Admin'
    WHEN v_hr IN ('rh_admin', 'rh_operador')      THEN 'RH'
    WHEN v_level = 'manager'                       THEN 'Gestor'
    ELSE 'Colaborador'
  END;

  SELECT id INTO v_role_id FROM public.rbac_roles
   WHERE organization_id = v_org AND name = v_role_name;

  IF v_role_id IS NOT NULL THEN
    INSERT INTO public.rbac_user_roles (user_id, role_id)
    VALUES (p_user_id, v_role_id)
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_assign_default_rbac_role(uuid) FROM PUBLIC, anon, authenticated;

-- ── 4. Backfill de orgs e usuários existentes ────────────────
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.organizations LOOP
    PERFORM public.fn_setup_default_roles(r.id);
  END LOOP;

  FOR r IN SELECT id FROM public.users LOOP
    PERFORM public.fn_assign_default_rbac_role(r.id);
  END LOOP;
END $$;

-- ── 5. Triggers para novos registros ─────────────────────────
-- Nova organização → cria os 4 perfis-padrão
CREATE OR REPLACE FUNCTION public.trg_org_setup_roles()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  -- Nunca bloquear a criação da organização por falha no RBAC
  BEGIN
    PERFORM public.fn_setup_default_roles(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_setup_default_roles falhou para org %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS org_setup_default_roles ON public.organizations;
CREATE TRIGGER org_setup_default_roles
  AFTER INSERT ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.trg_org_setup_roles();

-- Novo usuário → atribui perfil-padrão
CREATE OR REPLACE FUNCTION public.trg_user_assign_role()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  -- Nunca bloquear o cadastro do usuário por falha no RBAC
  BEGIN
    PERFORM public.fn_assign_default_rbac_role(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_assign_default_rbac_role falhou para user %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_assign_default_role ON public.users;
CREATE TRIGGER user_assign_default_role
  AFTER INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.trg_user_assign_role();
