-- Migration: rh17_ausencias
-- Tabela de ausências e solicitações de férias para funcionários

CREATE TABLE IF NOT EXISTS public.rh_ausencia (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    funcionario_id UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
    tipo TEXT NOT NULL, -- 'ferias', 'licenca_medica', 'folga', 'outro'
    data_inicio DATE NOT NULL,
    data_fim DATE NOT NULL,
    justificativa TEXT,
    anexo_url TEXT,
    status TEXT NOT NULL DEFAULT 'pendente', -- 'pendente', 'aprovado', 'rejeitado'
    aprovador_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_data_fim_maior_inicio CHECK (data_fim >= data_inicio)
);

-- Triggers de timestamp
CREATE TRIGGER set_rh_ausencia_updated_at
    BEFORE UPDATE ON public.rh_ausencia
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

-- Policies de RLS (Multi-tenant)
ALTER TABLE public.rh_ausencia ENABLE ROW LEVEL SECURITY;

-- 1. Qualquer pessoa vinculada à organization pode ver (read-only geral? Não, melhor restringir)
-- Funcionário vê apenas as dele. RH vê todas da organização.
CREATE POLICY "rh_ausencia_select_rh"
    ON public.rh_ausencia
    FOR SELECT
    USING (
        organization_id = (SELECT organization_id FROM public.users WHERE id = auth.uid())
        AND public.fn_is_rh()
    );

CREATE POLICY "rh_ausencia_select_self"
    ON public.rh_ausencia
    FOR SELECT
    USING (
        funcionario_id IN (SELECT id FROM public.funcionario WHERE user_id = auth.uid())
    );

-- 2. Inserção (Apenas o próprio funcionário, ou RH)
CREATE POLICY "rh_ausencia_insert_self"
    ON public.rh_ausencia
    FOR INSERT
    WITH CHECK (
        organization_id = (SELECT organization_id FROM public.users WHERE id = auth.uid())
        AND (
            funcionario_id IN (SELECT id FROM public.funcionario WHERE user_id = auth.uid())
            OR public.fn_is_rh()
        )
    );

-- 3. Atualização (Funcionário edita apenas pendentes, RH edita todas)
CREATE POLICY "rh_ausencia_update_self_or_rh"
    ON public.rh_ausencia
    FOR UPDATE
    USING (
        organization_id = (SELECT organization_id FROM public.users WHERE id = auth.uid())
        AND (
            (funcionario_id IN (SELECT id FROM public.funcionario WHERE user_id = auth.uid()) AND status = 'pendente')
            OR public.fn_is_rh()
        )
    );

-- 4. Exclusão (Funcionário apaga apenas pendentes, RH apaga qualquer uma)
CREATE POLICY "rh_ausencia_delete_self_or_rh"
    ON public.rh_ausencia
    FOR DELETE
    USING (
        organization_id = (SELECT organization_id FROM public.users WHERE id = auth.uid())
        AND (
            (funcionario_id IN (SELECT id FROM public.funcionario WHERE user_id = auth.uid()) AND status = 'pendente')
            OR public.fn_is_rh()
        )
    );

-- Seed de trigger multi-tenant org_id
CREATE TRIGGER set_rh_ausencia_org
    BEFORE INSERT ON public.rh_ausencia
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_tg_force_current_org();
