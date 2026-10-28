-- ==============================================================================
-- Migration: 20260709200000_rbac_permissions.sql
-- Description: Criação das tabelas do Controle Dinâmico de Permissões (RBAC)
-- ==============================================================================

-- 1. rbac_roles (Perfis de Acesso)
CREATE TABLE IF NOT EXISTS public.rbac_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  is_system BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rbac_roles_org ON public.rbac_roles(organization_id);

-- ==========================================
-- Funções Auxiliares
-- ==========================================
CREATE OR REPLACE FUNCTION public.fn_is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid()
      AND role_level IN ('super_admin', 'admin')
  );
$$;

REVOKE EXECUTE ON FUNCTION public.fn_is_admin() FROM anon;

-- 2. rbac_permissions (Mapeamento de Permissões)
CREATE TABLE IF NOT EXISTS public.rbac_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  module TEXT NOT NULL,
  action TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(module, action)
);

-- 3. rbac_role_permissions (Associação Perfil <-> Permissão)
CREATE TABLE IF NOT EXISTS public.rbac_role_permissions (
  role_id UUID NOT NULL REFERENCES public.rbac_roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES public.rbac_permissions(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (role_id, permission_id)
);

-- 4. rbac_user_roles (Associação Usuário <-> Perfil)
CREATE TABLE IF NOT EXISTS public.rbac_user_roles (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id UUID NOT NULL REFERENCES public.rbac_roles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, role_id)
);

-- ==========================================
-- Triggers de Updated At
-- ==========================================
CREATE TRIGGER trg_rbac_roles_updated_at
BEFORE UPDATE ON public.rbac_roles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ==========================================
-- RLS (Row-Level Security)
-- ==========================================
ALTER TABLE public.rbac_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rbac_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rbac_role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rbac_user_roles ENABLE ROW LEVEL SECURITY;

-- rbac_permissions: Todos logados podem ler (necessário para UI). Ninguém altera (fixo).
CREATE POLICY "Leitura geral de permissoes"
  ON public.rbac_permissions FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- rbac_roles: Usuário lê roles da sua org
CREATE POLICY "Leitura de roles da org"
  ON public.rbac_roles FOR SELECT
  USING (organization_id = public.fn_current_org());

-- rbac_role_permissions: Usuário lê links de roles da sua org
CREATE POLICY "Leitura de role_permissions da org"
  ON public.rbac_role_permissions FOR SELECT
  USING (
    role_id IN (SELECT id FROM public.rbac_roles WHERE organization_id = public.fn_current_org())
  );

-- rbac_user_roles: Usuário lê as próprias roles OU se for RH/Admin
CREATE POLICY "Leitura de user_roles"
  ON public.rbac_user_roles FOR SELECT
  USING (
    user_id = auth.uid() OR public.fn_is_rh() OR public.fn_is_admin()
  );

-- Para escrita (Insert/Update/Delete) nessas tabelas, será validado via RPCs 
-- ou via RLS caso o usuário tenha a permissão `admin_panel:manage`.
-- Para simplificar, permitiremos que Admins atuais possam gerenciar:
CREATE POLICY "Gestão de roles por admin"
  ON public.rbac_roles FOR ALL
  USING (public.fn_is_admin() AND organization_id = public.fn_current_org());

CREATE POLICY "Gestão de role_permissions por admin"
  ON public.rbac_role_permissions FOR ALL
  USING (
    public.fn_is_admin() AND 
    role_id IN (SELECT id FROM public.rbac_roles WHERE organization_id = public.fn_current_org())
  );

CREATE POLICY "Gestão de user_roles por admin"
  ON public.rbac_user_roles FOR ALL
  USING (public.fn_is_admin());

-- ==========================================
-- Semeando Permissões (Seeds Iniciais)
-- ==========================================
INSERT INTO public.rbac_permissions (module, action, description) VALUES
  ('admin_panel', 'view', 'Pode acessar o painel de administração'),
  ('admin_panel', 'manage', 'Pode alterar configurações, permissões e perfis'),
  
  ('comunicacao_canais', 'view', 'Pode visualizar e participar de canais'),
  ('comunicacao_conversas', 'view', 'Pode visualizar e iniciar conversas diretas'),
  ('comunicacao_chamadas', 'view', 'Pode realizar e receber chamadas de vídeo'),
  
  ('rh_banco_talentos', 'view', 'Pode visualizar o banco de talentos'),
  ('rh_banco_talentos', 'manage', 'Pode gerenciar candidatos, etapas e notas'),
  
  ('rh_funcionarios', 'view', 'Pode visualizar a lista de funcionários'),
  ('rh_funcionarios', 'manage', 'Pode adicionar, editar e desligar funcionários'),
  
  ('rh_documentos', 'view', 'Pode visualizar documentos organizacionais e de funcionários'),
  ('rh_documentos', 'manage', 'Pode gerenciar aprovação de documentos'),
  
  ('rh_onboarding', 'view', 'Pode visualizar jornadas de onboarding'),
  ('rh_onboarding', 'manage', 'Pode gerenciar checklists e templates de onboarding'),
  
  ('rh_alertas', 'view', 'Pode visualizar alertas do RH (vencimentos, etc)'),
  
  ('helpdesk', 'view', 'Pode visualizar tickets abertos na empresa'),
  ('helpdesk', 'manage', 'Pode responder, fechar e gerenciar categorias de tickets')
ON CONFLICT (module, action) DO NOTHING;

-- Função auxiliar para garantir que uma Org tenha os perfis básicos
CREATE OR REPLACE FUNCTION public.fn_setup_default_roles(p_org_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_admin_role_id UUID;
  v_user_role_id UUID;
BEGIN
  -- Criar Perfil Admin (se não existir)
  INSERT INTO public.rbac_roles (organization_id, name, description, is_system)
  VALUES (p_org_id, 'Super Admin', 'Acesso total ao sistema, painel e módulos sensíveis', true)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_admin_role_id;

  -- Se já existia, buscar o ID
  IF v_admin_role_id IS NULL THEN
    SELECT id INTO v_admin_role_id FROM public.rbac_roles WHERE organization_id = p_org_id AND name = 'Super Admin' LIMIT 1;
  END IF;

  -- Criar Perfil Usuário Comum
  INSERT INTO public.rbac_roles (organization_id, name, description, is_system)
  VALUES (p_org_id, 'Colaborador', 'Acesso padrão de funcionário', true)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_user_role_id;

  IF v_user_role_id IS NULL THEN
    SELECT id INTO v_user_role_id FROM public.rbac_roles WHERE organization_id = p_org_id AND name = 'Colaborador' LIMIT 1;
  END IF;

  -- Vincular todas as permissões ao Super Admin
  INSERT INTO public.rbac_role_permissions (role_id, permission_id)
  SELECT v_admin_role_id, id FROM public.rbac_permissions
  ON CONFLICT DO NOTHING;

END;
$$;
