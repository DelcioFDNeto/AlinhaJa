-- ============================================================
-- Fase 0 (Módulo RH / rumo SaaS): fundação multi-tenant
-- Cria organizations, adiciona organization_id às tabelas de
-- estrutura (users, branches, departments, job_positions),
-- papéis de RH e helpers de RLS.
-- Ref: docs/PLANO-IMPLEMENTACAO-RH.md, escopo S001/S016.
-- ============================================================

-- ── 1. Tabela de organizações (tenants) ─────────────────────
CREATE TABLE IF NOT EXISTS public.organizations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT NOT NULL UNIQUE
              CHECK (slug ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'),
  legal_name  TEXT,
  cnpj        TEXT,
  logo_url    TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  -- Módulos habilitados por tenant e demais configurações (SaaS)
  settings    JSONB NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS organizations_updated_at ON public.organizations;
CREATE TRIGGER organizations_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Tenant inicial: DuBairro (id fixo para permitir DEFAULT determinístico)
INSERT INTO public.organizations (id, name, slug, legal_name, cnpj)
VALUES (
  'a0000000-0000-4000-8000-000000000001',
  'DuBairro Supermercados',
  'dubairro',
  'INOVAR SERVIÇOS LTDA',
  '47.314.239/0001-08'
)
ON CONFLICT (slug) DO NOTHING;

-- ── 2. organization_id nas tabelas de estrutura ─────────────
-- DEFAULT fixo mantém o app atual (single-tenant) funcionando sem
-- alterações; o DEFAULT será removido na fase de signup self-service.
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS organization_id UUID NOT NULL
    DEFAULT 'a0000000-0000-4000-8000-000000000001'
    REFERENCES public.organizations(id);

ALTER TABLE public.branches
  ADD COLUMN IF NOT EXISTS organization_id UUID NOT NULL
    DEFAULT 'a0000000-0000-4000-8000-000000000001'
    REFERENCES public.organizations(id);

ALTER TABLE public.departments
  ADD COLUMN IF NOT EXISTS organization_id UUID NOT NULL
    DEFAULT 'a0000000-0000-4000-8000-000000000001'
    REFERENCES public.organizations(id);

ALTER TABLE public.job_positions
  ADD COLUMN IF NOT EXISTS organization_id UUID NOT NULL
    DEFAULT 'a0000000-0000-4000-8000-000000000001'
    REFERENCES public.organizations(id);

CREATE INDEX IF NOT EXISTS idx_users_organization        ON public.users(organization_id);
CREATE INDEX IF NOT EXISTS idx_branches_organization     ON public.branches(organization_id);
CREATE INDEX IF NOT EXISTS idx_departments_organization  ON public.departments(organization_id);
CREATE INDEX IF NOT EXISTS idx_job_positions_organization ON public.job_positions(organization_id);

-- Unicidade de nomes passa a ser por organização (antes era global)
ALTER TABLE public.departments   DROP CONSTRAINT IF EXISTS departments_name_key;
ALTER TABLE public.job_positions DROP CONSTRAINT IF EXISTS job_positions_name_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_departments_org_name
  ON public.departments(organization_id, name);
CREATE UNIQUE INDEX IF NOT EXISTS uq_job_positions_org_name
  ON public.job_positions(organization_id, name);

-- ── 3. Papéis do módulo RH (S016) ────────────────────────────
-- Complementa role_level (super_admin/admin/manager/member) sem tocá-lo.
DO $$ BEGIN
  CREATE TYPE public.hr_role AS ENUM
    ('rh_admin', 'rh_operador', 'gestor_filial', 'gestor_setor');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS hr_role public.hr_role;

-- ── 4. Helpers de RLS (SECURITY DEFINER bypassa RLS de users) ─
CREATE OR REPLACE FUNCTION public.fn_current_org()
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT organization_id FROM public.users WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.fn_is_rh()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid()
      AND (role_level IN ('super_admin', 'admin')
           OR hr_role IN ('rh_admin', 'rh_operador'))
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_is_rh_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid()
      AND (role_level IN ('super_admin', 'admin') OR hr_role = 'rh_admin')
  );
$$;

REVOKE EXECUTE ON FUNCTION public.fn_current_org()  FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_is_rh()        FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_is_rh_admin()  FROM anon;

-- ── 5. RLS por organização nas tabelas de estrutura ─────────
-- organizations: usuário lê apenas a própria org
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Usuário lê a própria organização" ON public.organizations;
CREATE POLICY "Usuário lê a própria organização"
  ON public.organizations FOR SELECT
  USING (id = public.fn_current_org());

-- Leituras existentes ganham filtro de org (hoje há uma única org,
-- portanto sem mudança de comportamento para o app atual)
DROP POLICY IF EXISTS "Usuário lê qualquer perfil" ON public.users;
CREATE POLICY "Usuário lê qualquer perfil"
  ON public.users FOR SELECT
  USING (auth.role() = 'authenticated'
         AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "Leitura de filiais para autenticados" ON public.branches;
CREATE POLICY "Leitura de filiais para autenticados"
  ON public.branches FOR SELECT
  USING (auth.role() = 'authenticated'
         AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "Leitura de departamentos" ON public.departments;
CREATE POLICY "Leitura de departamentos"
  ON public.departments FOR SELECT
  USING (auth.role() = 'authenticated'
         AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "Leitura de cargos" ON public.job_positions;
CREATE POLICY "Leitura de cargos"
  ON public.job_positions FOR SELECT
  USING (auth.role() = 'authenticated'
         AND organization_id = public.fn_current_org());
