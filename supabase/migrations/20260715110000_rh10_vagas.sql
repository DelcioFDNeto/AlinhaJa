-- ============================================================
-- RH-10 / Fase 2 — Vagas publicáveis (Job Openings)
-- (PLANO-RH-COMPLETO.md, Onda 2).
--
-- O portal deixa de ser só "trabalhe conosco": vagas com status
-- rascunho|aberta|pausada|fechada aparecem em /carreiras/:slug e
-- cada candidatura pode nascer vinculada a uma vaga
-- (candidato.vaga_id opcional — a espontânea continua NULL).
--
-- Leitura pública SOMENTE via Edge Function rh-candidatura
-- (service_role); no app, escrita e leitura são do RH.
-- ============================================================

-- ── 1. Enum + tabela ─────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE public.vaga_status AS ENUM
    ('rascunho', 'aberta', 'pausada', 'fechada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.vaga (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  titulo          TEXT NOT NULL CHECK (char_length(trim(titulo)) BETWEEN 3 AND 120),
  area_id         UUID REFERENCES public.rh_area(id),
  cargo_id        UUID REFERENCES public.rh_cargo(id),
  nivel           TEXT,
  tipo_contrato   TEXT,
  localidade      TEXT,
  remoto          BOOLEAN NOT NULL DEFAULT false,
  faixa_salarial  TEXT,
  descricao       TEXT,
  requisitos      TEXT,
  status          public.vaga_status NOT NULL DEFAULT 'rascunho',
  vagas_qtd       SMALLINT CHECK (vagas_qtd IS NULL OR vagas_qtd > 0),
  publicada_em    TIMESTAMPTZ,
  expira_em       DATE,
  created_by      UUID REFERENCES public.users(id),
  updated_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ,
  deleted_by      UUID REFERENCES public.users(id)
);

CREATE INDEX IF NOT EXISTS idx_vaga_org_status
  ON public.vaga(organization_id, status) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS vaga_updated_at ON public.vaga;
CREATE TRIGGER vaga_updated_at
  BEFORE UPDATE ON public.vaga
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Carimbo automático da primeira publicação (rascunho → aberta).
CREATE OR REPLACE FUNCTION public.fn_tg_vaga_publicada()
RETURNS trigger LANGUAGE plpgsql
SET search_path = '' AS $$
BEGIN
  IF NEW.status = 'aberta' AND NEW.publicada_em IS NULL THEN
    NEW.publicada_em := NOW();
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS vaga_publicada ON public.vaga;
CREATE TRIGGER vaga_publicada
  BEFORE INSERT OR UPDATE OF status ON public.vaga
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_vaga_publicada();

-- ── 2. Vínculo opcional na candidatura ───────────────────────
ALTER TABLE public.candidato
  ADD COLUMN IF NOT EXISTS vaga_id UUID REFERENCES public.vaga(id);
CREATE INDEX IF NOT EXISTS idx_candidato_vaga
  ON public.candidato(vaga_id) WHERE vaga_id IS NOT NULL AND deleted_at IS NULL;

-- ── 3. RLS ───────────────────────────────────────────────────
ALTER TABLE public.vaga ENABLE ROW LEVEL SECURITY;

-- RH lê e escreve na própria org (padrão de `vinculo`); nenhuma
-- policy anon — o portal passa pela Edge Function (service_role).
DROP POLICY IF EXISTS "RH gerencia vagas" ON public.vaga;
CREATE POLICY "RH gerencia vagas"
  ON public.vaga FOR ALL
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org()
         AND deleted_at IS NULL)
  WITH CHECK (public.fn_is_rh() AND organization_id = public.fn_current_org());

DROP TRIGGER IF EXISTS trg_force_org ON public.vaga;
CREATE TRIGGER trg_force_org BEFORE INSERT ON public.vaga
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org();

DROP POLICY IF EXISTS tenant_isolation ON public.vaga;
CREATE POLICY tenant_isolation ON public.vaga AS RESTRICTIVE FOR ALL
  USING (organization_id = public.fn_current_org())
  WITH CHECK (organization_id = public.fn_current_org());

DROP POLICY IF EXISTS module_entitlement ON public.vaga;
CREATE POLICY module_entitlement ON public.vaga AS RESTRICTIVE FOR ALL
  USING (public.fn_org_has_module('rh_banco_talentos'))
  WITH CHECK (public.fn_org_has_module('rh_banco_talentos'));

-- ── 4. View de listagem com contadores ───────────────────────
CREATE OR REPLACE VIEW public.vaga_resumo
WITH (security_invoker = true) AS
SELECT
  v.*,
  a.nome AS area_nome,
  g.nome AS cargo_nome,
  (SELECT count(*) FROM public.candidato cd
    WHERE cd.vaga_id = v.id AND cd.deleted_at IS NULL) AS candidatos_total,
  (SELECT count(*) FROM public.candidato cd
    WHERE cd.vaga_id = v.id AND cd.deleted_at IS NULL
      AND cd.status NOT IN ('descartado', 'contratado')) AS candidatos_em_processo
FROM public.vaga v
LEFT JOIN public.rh_area  a ON a.id = v.area_id
LEFT JOIN public.rh_cargo g ON g.id = v.cargo_id
WHERE v.deleted_at IS NULL;
