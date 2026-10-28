-- ============================================================
-- RH-9 / Fase 4 — Catálogo Áreas / Cargos / Competências
-- (PLANO-RH-COMPLETO.md, Onda 2).
--
-- Estrutura dinâmica por organização que destrava filtros
-- consistentes, Vagas (RH-10) e Avaliação Técnica (Fase 3).
-- Migração suave: os campos texto do candidato permanecem;
-- entram FKs opcionais + seed best-effort a partir dos textos
-- já digitados (nada é sobrescrito).
--
-- Multi-tenant: organization_id + trg_force_org (anti-spoofing) +
-- tenant_isolation RESTRICTIVE + module_entitlement (rh_banco_talentos).
-- ============================================================

-- ── 1. Tabelas do catálogo ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rh_area (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  nome            TEXT NOT NULL CHECK (char_length(trim(nome)) BETWEEN 2 AND 80),
  ativo           BOOLEAN NOT NULL DEFAULT true,
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_rh_area_org_nome
  ON public.rh_area(organization_id, lower(trim(nome)));

CREATE TABLE IF NOT EXISTS public.rh_cargo (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  area_id         UUID REFERENCES public.rh_area(id),
  nome            TEXT NOT NULL CHECK (char_length(trim(nome)) BETWEEN 2 AND 80),
  nivel_sugerido  TEXT,
  ativo           BOOLEAN NOT NULL DEFAULT true,
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_rh_cargo_org_nome
  ON public.rh_cargo(organization_id, lower(trim(nome)));
CREATE INDEX IF NOT EXISTS idx_rh_cargo_org_area
  ON public.rh_cargo(organization_id, area_id);

-- Competências entram já no schema (usadas na Fase 3 — avaliação
-- técnica); a UI de gestão chega junto com aquele módulo.
CREATE TABLE IF NOT EXISTS public.rh_competencia (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  nome            TEXT NOT NULL CHECK (char_length(trim(nome)) BETWEEN 2 AND 80),
  ativo           BOOLEAN NOT NULL DEFAULT true,
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_rh_competencia_org_nome
  ON public.rh_competencia(organization_id, lower(trim(nome)));

CREATE TABLE IF NOT EXISTS public.cargo_competencia (
  cargo_id        UUID NOT NULL REFERENCES public.rh_cargo(id) ON DELETE CASCADE,
  competencia_id  UUID NOT NULL REFERENCES public.rh_competencia(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  PRIMARY KEY (cargo_id, competencia_id)
);
CREATE INDEX IF NOT EXISTS idx_cargo_competencia_org
  ON public.cargo_competencia(organization_id);

-- ── 2. FKs opcionais no candidato (migração suave) ───────────
ALTER TABLE public.candidato
  ADD COLUMN IF NOT EXISTS area_id  UUID REFERENCES public.rh_area(id),
  ADD COLUMN IF NOT EXISTS cargo_id UUID REFERENCES public.rh_cargo(id);

-- ── 3. RLS ───────────────────────────────────────────────────
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['rh_area', 'rh_cargo', 'rh_competencia',
                           'cargo_competencia'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);

    -- Org inteira lê (dropdowns de formulários); só RH escreve.
    EXECUTE format('DROP POLICY IF EXISTS "Org lê catálogo" ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY "Org lê catálogo" ON public.%I FOR SELECT '
      'USING (organization_id = public.fn_current_org())', t);
    EXECUTE format('DROP POLICY IF EXISTS "RH gerencia catálogo" ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY "RH gerencia catálogo" ON public.%I FOR ALL '
      'USING (public.fn_is_rh() AND organization_id = public.fn_current_org()) '
      'WITH CHECK (public.fn_is_rh() AND organization_id = public.fn_current_org())',
      t);

    -- Carimbo de org no INSERT (anti-spoofing)
    EXECUTE format('DROP TRIGGER IF EXISTS trg_force_org ON public.%I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_force_org BEFORE INSERT ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org()', t);

    -- Isolamento por org + entitlement do módulo (RESTRICTIVE)
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON public.%I AS RESTRICTIVE FOR ALL '
      'USING (organization_id = public.fn_current_org()) '
      'WITH CHECK (organization_id = public.fn_current_org())', t);
    EXECUTE format('DROP POLICY IF EXISTS module_entitlement ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY module_entitlement ON public.%I AS RESTRICTIVE FOR ALL '
      'USING (public.fn_org_has_module(%L)) '
      'WITH CHECK (public.fn_org_has_module(%L))',
      t, 'rh_banco_talentos', 'rh_banco_talentos');
  END LOOP;
END $$;

-- ── 4. Seed + normalização best-effort ───────────────────────
-- Popula o catálogo com os textos livres já digitados nos
-- candidatos e liga as FKs por igualdade (case-insensitive).
-- Idempotente: ON CONFLICT ignora e os UPDATEs só preenchem NULLs.
INSERT INTO public.rh_area (organization_id, nome)
SELECT DISTINCT c.organization_id, trim(c.area_interesse)
FROM public.candidato c
WHERE c.deleted_at IS NULL
  AND char_length(trim(coalesce(c.area_interesse, ''))) BETWEEN 2 AND 80
ON CONFLICT DO NOTHING;

INSERT INTO public.rh_cargo (organization_id, nome)
SELECT DISTINCT c.organization_id, trim(c.cargo_pretendido)
FROM public.candidato c
WHERE c.deleted_at IS NULL
  AND char_length(trim(coalesce(c.cargo_pretendido, ''))) BETWEEN 2 AND 80
ON CONFLICT DO NOTHING;

UPDATE public.candidato c
SET area_id = a.id
FROM public.rh_area a
WHERE c.area_id IS NULL
  AND a.organization_id = c.organization_id
  AND lower(trim(coalesce(c.area_interesse, ''))) = lower(trim(a.nome));

UPDATE public.candidato c
SET cargo_id = g.id
FROM public.rh_cargo g
WHERE c.cargo_id IS NULL
  AND g.organization_id = c.organization_id
  AND lower(trim(coalesce(c.cargo_pretendido, ''))) = lower(trim(g.nome));
