-- ==============================================================================
-- Migration: 20260713140000_helpdesk_colaborador_view.sql
-- Description: Concede `helpdesk:view` ao perfil-padrão "Colaborador".
--
-- Contexto: a sidebar passou a expor DOIS itens de Helpdesk sobre a mesma
-- licença/permissão `helpdesk` (ver `lib/core/modules/module_registry.dart`):
--   • "Central de Ajuda" (helpdesk:view)  → FAQ + Meus Chamados + Abrir chamado.
--   • "Helpdesk TI"      (helpdesk:manage) → fila de atendimento (resolver).
-- Para que QUALQUER colaborador consiga abrir/acompanhar chamados, o perfil
-- Colaborador precisa de `helpdesk:view`. `helpdesk:manage` (resolver) segue
-- restrito a RH/Super Admin.
--
-- CREATE OR REPLACE idempotente de fn_setup_default_roles: preserva todos os
-- grants anteriores (auto-provisionamento 20260710120000 + abas do painel
-- 20260710150000) e apenas ADICIONA `helpdesk:view` ao Colaborador. Ao final,
-- reaplica em todas as orgs existentes (backfill).
-- ==============================================================================

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

  -- Colaborador: comunicação básica + abrir/acompanhar chamados de TI
  PERFORM public.fn_grant_perms(v_colab, ARRAY[
    'comunicacao_canais:view', 'comunicacao_conversas:view',
    'comunicacao_chamadas:view',
    'helpdesk:view']);

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

-- ── Backfill: reaplica os perfis-padrão em todas as orgs existentes ──────────
-- Idempotente (fn_grant_perms usa ON CONFLICT DO NOTHING). Garante que os
-- Colaboradores já existentes ganhem `helpdesk:view` sem esperar novo cadastro.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.organizations LOOP
    PERFORM public.fn_setup_default_roles(r.id);
  END LOOP;
END $$;
