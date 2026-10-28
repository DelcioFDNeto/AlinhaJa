-- ============================================================
-- Migration 013: Reorganização de Acessos, Departamentos e Funções
-- ============================================================
-- Cria tabelas departments e job_positions, migra ENUM user_role_level
-- de 6 valores para 4, e vincula users às novas tabelas.
-- ============================================================

-- ── 1. Tabela de Departamentos ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.departments (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL UNIQUE,
  icon       TEXT NOT NULL DEFAULT 'workspaces',
  is_active  BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Leitura de departamentos" ON public.departments;
CREATE POLICY "Leitura de departamentos"
  ON public.departments FOR SELECT
  USING (auth.role() = 'authenticated');

-- Seed de departamentos
INSERT INTO public.departments (id, name, icon) VALUES
  ('ti',              'Tecnologia da Informação', 'settings'),
  ('financeiro',      'Financeiro',               'payments_outlined'),
  ('rh',              'Recursos Humanos',         'people_outline'),
  ('comercial',       'Comercial / Vendas',       'storefront'),
  ('pos_venda',       'Pós-Venda',                'build_outlined'),
  ('oficina',         'Oficina',                  'handyman'),
  ('administrativo',  'Administrativo',           'business_center'),
  ('logistica',       'Logística / Expedição',    'local_shipping_outlined'),
  ('diretoria',       'Diretoria',                'corporate_fare')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  icon = EXCLUDED.icon;

-- ── 2. Tabela de Cargos / Funções ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.job_positions (
  id             TEXT PRIMARY KEY,
  name           TEXT NOT NULL UNIQUE,
  department_ids TEXT[] NOT NULL DEFAULT '{}',
  is_active      BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.job_positions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Leitura de cargos" ON public.job_positions;
CREATE POLICY "Leitura de cargos"
  ON public.job_positions FOR SELECT
  USING (auth.role() = 'authenticated');

-- Seed de cargos
INSERT INTO public.job_positions (id, name, department_ids) VALUES
  ('diretor',        'Diretor(a)',        ARRAY['diretoria']),
  ('gerente_geral',  'Gerente Geral',     ARRAY['ti','financeiro','rh','comercial','pos_venda','oficina','administrativo','logistica','diretoria']),
  ('gerente_loja',   'Gerente de Loja',   ARRAY['comercial','pos_venda']),
  ('coordenador',    'Coordenador(a)',    ARRAY['ti','financeiro','rh','comercial','pos_venda','oficina','administrativo','logistica']),
  ('lider_loja',     'Líder de Loja',     ARRAY['comercial']),
  ('supervisor',     'Supervisor(a)',     ARRAY['pos_venda','oficina','logistica']),
  ('analista',       'Analista',          ARRAY['ti','financeiro','rh','administrativo']),
  ('assistente',     'Assistente',        ARRAY['ti','financeiro','rh','comercial','pos_venda','oficina','administrativo','logistica']),
  ('vendedor',       'Vendedor(a)',       ARRAY['comercial']),
  ('mecanico',       'Mecânico(a)',       ARRAY['oficina','pos_venda']),
  ('tecnico',        'Técnico(a)',        ARRAY['ti','oficina','pos_venda']),
  ('auxiliar',       'Auxiliar',          ARRAY['ti','financeiro','rh','comercial','pos_venda','oficina','administrativo','logistica']),
  ('recepcionista',  'Recepcionista',     ARRAY['comercial','administrativo']),
  ('estoquista',     'Estoquista',        ARRAY['logistica']),
  ('faturista',      'Faturista',         ARRAY['financeiro']),
  ('motorista',      'Motorista',         ARRAY['logistica'])
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  department_ids = EXCLUDED.department_ids;

-- ── 3. Migrar ENUM user_role_level para novos valores ─────────
-- O PostgreSQL não permite renomear valores de ENUM facilmente.
-- Adicionamos os novos valores ao ENUM existente.
ALTER TYPE public.user_role_level ADD VALUE IF NOT EXISTS 'super_admin' BEFORE 'ti_admin';
ALTER TYPE public.user_role_level ADD VALUE IF NOT EXISTS 'admin' AFTER 'super_admin';
ALTER TYPE public.user_role_level ADD VALUE IF NOT EXISTS 'member' AFTER 'staff';

-- ── 4. Adicionar colunas FK na tabela users ───────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS department_id TEXT REFERENCES public.departments(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS job_position_id TEXT REFERENCES public.job_positions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_users_department ON public.users(department_id);
CREATE INDEX IF NOT EXISTS idx_users_job_position ON public.users(job_position_id);

-- Migrar dados existentes da coluna 'department' (texto livre) para department_id
UPDATE public.users SET department_id = 'ti'              WHERE department ILIKE '%TI%' AND department_id IS NULL;
UPDATE public.users SET department_id = 'financeiro'      WHERE department ILIKE '%Financeiro%' AND department_id IS NULL;
UPDATE public.users SET department_id = 'rh'              WHERE (department ILIKE '%RH%' OR department ILIKE '%Recursos%') AND department_id IS NULL;
UPDATE public.users SET department_id = 'comercial'       WHERE department ILIKE '%Comercial%' AND department_id IS NULL;
UPDATE public.users SET department_id = 'pos_venda'       WHERE department ILIKE '%Pós%Venda%' AND department_id IS NULL;
UPDATE public.users SET department_id = 'oficina'         WHERE department ILIKE '%Oficina%' AND department_id IS NULL;
UPDATE public.users SET department_id = 'administrativo'  WHERE department ILIKE '%Outros%' AND department_id IS NULL;
UPDATE public.users SET department_id = 'logistica'       WHERE department ILIKE '%Logís%' AND department_id IS NULL;

-- ── 10. GRANT para as novas tabelas ───────────────────────────
GRANT SELECT ON public.departments TO authenticated;
GRANT SELECT ON public.job_positions TO authenticated;
