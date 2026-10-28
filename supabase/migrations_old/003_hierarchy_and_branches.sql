-- ============================================================
-- Migração 003: Hierarquia Corporativa e Filiais (RBAC)
-- ============================================================

-- ── 1. Helper: atualização automática de updated_at para a nova tabela
-- (Reaproveita a função set_updated_at() já criada no schema 001)

-- ── 2. Tabela de Filiais (branches) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branches (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name            TEXT NOT NULL,
  is_headquarters BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS branches_updated_at ON public.branches;
CREATE TRIGGER branches_updated_at
  BEFORE UPDATE ON public.branches
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- RLS: Qualquer usuário autenticado pode ler as filiais
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Leitura de filiais para autenticados"
  ON public.branches FOR SELECT
  USING (auth.role() = 'authenticated');

-- Insere filiais iniciais de exemplo se a tabela estiver vazia
INSERT INTO public.branches (name, is_headquarters) 
SELECT 'Matriz Corporativa', true
WHERE NOT EXISTS (SELECT 1 FROM public.branches);

-- ── 3. ENUM: Nível de Acesso Hierárquico ──────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role_level') THEN
    CREATE TYPE user_role_level AS ENUM ('ti_admin', 'director', 'manager', 'coordinator', 'staff');
  END IF;
END $$;

-- ── 4. Atualização da Tabela users ────────────────────────────────────
ALTER TABLE public.users 
  ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS role_level user_role_level NOT NULL DEFAULT 'staff',
  ADD COLUMN IF NOT EXISTS job_function TEXT;

CREATE INDEX IF NOT EXISTS idx_users_branch ON public.users(branch_id);
CREATE INDEX IF NOT EXISTS idx_users_role   ON public.users(role_level);

-- ── 5. Atualização do Trigger de Criação de Usuário (Admin Master) ────
-- Atualizamos a função para definir o ti@alinhaja.com.br como ti_admin 
-- logo no momento do cadastro.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_role user_role_level := 'staff';
BEGIN
  INSERT INTO public.users (
    id, full_name, avatar_url, role_level
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
    v_role
  )
  ON CONFLICT (id) DO NOTHING;
  
  RETURN NEW;
END;
$$;

-- Aplica retroativamente o cargo de TI para contas já criadas com este email
DO $$
DECLARE
  v_ti_id UUID;
BEGIN
  SELECT id INTO v_ti_id FROM auth.users WHERE email = 'ti@alinhaja.com.br';
  IF v_ti_id IS NOT NULL THEN
    UPDATE public.users SET role_level = 'ti_admin' WHERE id = v_ti_id;
  END IF;
END $$;
