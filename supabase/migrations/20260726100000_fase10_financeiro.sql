-- ============================================================
-- Módulo Fase 10 — Core Financeiro (Estrutura Inicial)
-- ============================================================

-- ── 1. Conta Bancária / Caixa ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.fin_conta_bancaria (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  nome            TEXT NOT NULL,
  saldo_inicial   NUMERIC(15,2) NOT NULL DEFAULT 0.00,
  data_saldo_inicial DATE NOT NULL DEFAULT CURRENT_DATE,
  ativa           BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by      UUID REFERENCES public.users(id)
);
CREATE INDEX IF NOT EXISTS idx_fin_conta_org ON public.fin_conta_bancaria(organization_id);
ALTER TABLE public.fin_conta_bancaria ENABLE ROW LEVEL SECURITY;

-- ── 2. Plano de Contas (Categorias) ──────────────────────────
CREATE TABLE IF NOT EXISTS public.fin_categoria (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  nome            TEXT NOT NULL,
  tipo            TEXT NOT NULL CHECK (tipo IN ('receita', 'despesa')),
  parent_id       UUID REFERENCES public.fin_categoria(id) ON DELETE CASCADE,
  ativa           BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fin_categoria_org ON public.fin_categoria(organization_id);
ALTER TABLE public.fin_categoria ENABLE ROW LEVEL SECURITY;

-- ── 3. Parceiros (Fornecedores / Clientes) ───────────────────
CREATE TABLE IF NOT EXISTS public.fin_parceiro (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  nome            TEXT NOT NULL,
  documento       TEXT, -- CPF ou CNPJ
  tipo            TEXT NOT NULL DEFAULT 'ambos', -- fornecedor, cliente, ambos
  telefone        TEXT,
  email           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fin_parceiro_org ON public.fin_parceiro(organization_id);
ALTER TABLE public.fin_parceiro ENABLE ROW LEVEL SECURITY;

-- ── 4. Lançamento Financeiro (Pagar / Receber / Caixa) ───────
CREATE TABLE IF NOT EXISTS public.fin_lancamento (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  tipo            TEXT NOT NULL CHECK (tipo IN ('pagar', 'receber', 'transferencia')),
  conta_bancaria_id UUID NOT NULL REFERENCES public.fin_conta_bancaria(id),
  categoria_id    UUID REFERENCES public.fin_categoria(id),
  parceiro_id     UUID REFERENCES public.fin_parceiro(id),
  descricao       TEXT NOT NULL,
  valor           NUMERIC(15,2) NOT NULL CHECK (valor > 0),
  data_vencimento DATE NOT NULL,
  data_pagamento  DATE, -- Se preenchido, significa que está liquidado (Pago/Recebido)
  status          TEXT NOT NULL DEFAULT 'pendente', -- pendente, pago, atrasado, cancelado
  anexo_url       TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by      UUID REFERENCES public.users(id),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fin_lancamento_org ON public.fin_lancamento(organization_id);
CREATE INDEX IF NOT EXISTS idx_fin_lancamento_data ON public.fin_lancamento(data_vencimento);
ALTER TABLE public.fin_lancamento ENABLE ROW LEVEL SECURITY;

-- ── 5. RLS (Row Level Security) ──────────────────────────────
-- Permissões básicas: Administradores e usuários com perfil financeiro acessam.
-- Por enquanto, usaremos uma validação básica (apenas Admin pode ver/editar, para garantir segurança até a implementação completa do RBAC financeiro).

CREATE OR REPLACE FUNCTION public.fn_is_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() 
      AND organization_id = public.fn_current_org() 
      AND role_level IN ('super_admin', 'admin')
  );
$$;

CREATE POLICY "Admin acessa fin_conta_bancaria" ON public.fin_conta_bancaria FOR ALL
USING (public.fn_is_admin() AND organization_id = public.fn_current_org());

CREATE POLICY "Admin acessa fin_categoria" ON public.fin_categoria FOR ALL
USING (public.fn_is_admin() AND organization_id = public.fn_current_org());

CREATE POLICY "Admin acessa fin_parceiro" ON public.fin_parceiro FOR ALL
USING (public.fn_is_admin() AND organization_id = public.fn_current_org());

CREATE POLICY "Admin acessa fin_lancamento" ON public.fin_lancamento FOR ALL
USING (public.fn_is_admin() AND organization_id = public.fn_current_org());
