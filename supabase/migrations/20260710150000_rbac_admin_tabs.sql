-- ==============================================================================
-- Migration: 20260710150000_rbac_admin_tabs.sql
-- Description: Fatia o Dashboard Administrativo em abas gated por RBAC. Cada aba
--              do painel passa a exigir uma permissão `view` própria; se o
--              usuário não a tiver, a aba nem aparece.
--
-- Contexto: espelha `lib/features/admin/admin_tab_registry.dart`. As abas
-- Helpdesk e Localização reusam os módulos RBAC já existentes (`helpdesk`,
-- `location`); as demais ganham chaves `admin_*` novas. Além disso, o gate de
-- ENTRADA do painel deixou de ser por role_level e passou a exigir
-- `admin_panel:view` (com bypass de super_admin/admin), permitindo conceder
-- abas específicas a perfis não-admin (RH, Gestor).
-- ==============================================================================

-- ── 1. Semeia as permissões das novas abas ───────────────────────────────────
INSERT INTO public.rbac_permissions (module, action, description) VALUES
  ('admin_users',      'view', 'Pode acessar a Gestão de Usuários'),
  ('admin_cadastro',   'view', 'Pode acessar o cadastro de novos usuários'),
  ('admin_acessos',    'view', 'Pode acessar o Gerenciamento de Acessos (perfis e permissões)'),
  ('admin_auditoria',  'view', 'Pode acessar os logs de Auditoria'),
  ('admin_moderacao',  'view', 'Pode acessar a Moderação de conteúdo'),
  ('admin_relatorios', 'view', 'Pode acessar os Relatórios de uso'),
  ('admin_ai_keys',    'view', 'Pode acessar a gestão das Chaves de IA'),
  ('admin_backup',     'view', 'Pode acessar a gestão de Backup')
ON CONFLICT (module, action) DO NOTHING;

-- ── 2. Atualiza os perfis-padrão para incluir as abas do painel ──────────────
-- CREATE OR REPLACE idempotente: preserva os grants da migração de
-- auto-provisionamento (20260710120000) e ADICIONA os grants de abas do painel:
--   • RH    → entra no painel + Gestão de Usuários + Novo Cadastro
--   • Gestor→ entra no painel + Gestão de Usuários
-- Super Admin continua recebendo TODAS as permissões (inclui as novas abas).
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

  -- Gestor: comunicação + visão de RH + abrir chamados + painel (Usuários)
  PERFORM public.fn_grant_perms(v_gestor, ARRAY[
    'comunicacao_canais:view', 'comunicacao_conversas:view',
    'comunicacao_chamadas:view',
    'rh_funcionarios:view', 'rh_documentos:view', 'rh_alertas:view',
    'helpdesk:view',
    'admin_panel:view', 'admin_users:view']);

  -- RH: todo o módulo de RH + comunicação + helpdesk + painel (Usuários/Cadastro)
  PERFORM public.fn_grant_perms(v_rh, ARRAY[
    'comunicacao_canais:view', 'comunicacao_conversas:view',
    'comunicacao_chamadas:view',
    'rh_banco_talentos:view', 'rh_banco_talentos:manage',
    'rh_funcionarios:view', 'rh_funcionarios:manage',
    'rh_documentos:view', 'rh_documentos:manage',
    'rh_onboarding:view', 'rh_onboarding:manage',
    'rh_alertas:view',
    'helpdesk:view', 'helpdesk:manage',
    'admin_panel:view', 'admin_users:view', 'admin_cadastro:view']);
END;
$$;
REVOKE ALL ON FUNCTION public.fn_setup_default_roles(uuid) FROM PUBLIC, anon, authenticated;

-- ── 3. Backfill: reaplica os perfis-padrão em todas as orgs existentes ───────
-- Idempotente (todos os INSERTs usam ON CONFLICT DO NOTHING). Garante que
-- Super Admins já existentes recebam as novas abas e que RH/Gestor ganhem os
-- grants do painel sem esperar um novo cadastro.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.organizations LOOP
    PERFORM public.fn_setup_default_roles(r.id);
  END LOOP;
END $$;
