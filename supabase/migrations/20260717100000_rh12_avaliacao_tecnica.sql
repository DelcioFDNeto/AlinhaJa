-- ============================================================
-- RH-12 / Fase 3 — Avaliação Técnica + IA generativa de questões
-- (PLANO-RH-COMPLETO.md, Onda 4).
--
-- Banco de questões por cargo/nível (manuais ou geradas por IA) e
-- prova objetiva do candidato com correção SEMPRE server-side
-- (a Edge Function nunca envia correta_idx ao cliente).
--
-- Multi-tenant: organization_id + tenant_isolation RESTRICTIVE +
-- module_entitlement (rh_banco_talentos). `questao` recebe o
-- carimbo de org por trigger (RH insere); `avaliacao`/respostas são
-- gravadas pela Edge Function (service_role, org explícita).
-- ============================================================

-- ── 1. Banco de questões ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.questao (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  cargo_id        UUID REFERENCES public.rh_cargo(id),
  area_id         UUID REFERENCES public.rh_area(id),
  nivel           TEXT,
  enunciado       TEXT NOT NULL CHECK (char_length(trim(enunciado)) BETWEEN 5 AND 1000),
  -- opcoes: array JSON de strings (2 a 6 alternativas); correta_idx
  -- aponta uma posição válida do array. A correta NUNCA vai ao cliente.
  opcoes          JSONB NOT NULL,
  correta_idx     SMALLINT NOT NULL,
  origem          TEXT NOT NULL DEFAULT 'manual' CHECK (origem IN ('manual', 'ia')),
  ativa           BOOLEAN NOT NULL DEFAULT true,
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ,
  CONSTRAINT questao_opcoes_validas CHECK (
    jsonb_typeof(opcoes) = 'array'
    AND jsonb_array_length(opcoes) BETWEEN 2 AND 6
    AND correta_idx >= 0
    AND correta_idx < jsonb_array_length(opcoes)
  )
);
CREATE INDEX IF NOT EXISTS idx_questao_org_cargo
  ON public.questao(organization_id, cargo_id)
  WHERE deleted_at IS NULL AND ativa = true;
CREATE INDEX IF NOT EXISTS idx_questao_org_nivel
  ON public.questao(organization_id, nivel)
  WHERE deleted_at IS NULL AND ativa = true;

-- ── 2. Avaliação (prova respondida por um candidato) ─────────
CREATE TABLE IF NOT EXISTS public.avaliacao (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  candidato_id    UUID NOT NULL REFERENCES public.candidato(id) ON DELETE CASCADE,
  vaga_id         UUID REFERENCES public.vaga(id),
  nivel           TEXT,
  total_questoes  SMALLINT NOT NULL DEFAULT 0,
  acertos         SMALLINT,
  nota            SMALLINT CHECK (nota IS NULL OR nota BETWEEN 0 AND 100),
  status          TEXT NOT NULL DEFAULT 'iniciada'
                    CHECK (status IN ('iniciada', 'finalizada', 'expirada')),
  iniciada_em     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finalizada_em   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_avaliacao_candidato
  ON public.avaliacao(candidato_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_avaliacao_org_vaga
  ON public.avaliacao(organization_id, vaga_id);

-- ── 3. Respostas da avaliação ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.avaliacao_resposta (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  avaliacao_id    UUID NOT NULL REFERENCES public.avaliacao(id) ON DELETE CASCADE,
  questao_id      UUID NOT NULL REFERENCES public.questao(id),
  resposta_idx    SMALLINT,
  correta         BOOLEAN,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_avaliacao_resposta_aval
  ON public.avaliacao_resposta(avaliacao_id);

-- ── 4. RLS ───────────────────────────────────────────────────
-- questao: org inteira lê (dropdowns/preview); só RH escreve. As
-- provas são gravadas pela Edge Function (service_role bypassa RLS).
ALTER TABLE public.questao            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.avaliacao          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.avaliacao_resposta ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "RH gerencia questoes" ON public.questao;
CREATE POLICY "RH gerencia questoes" ON public.questao FOR ALL
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org()
         AND deleted_at IS NULL)
  WITH CHECK (public.fn_is_rh() AND organization_id = public.fn_current_org());

DROP TRIGGER IF EXISTS trg_force_org ON public.questao;
CREATE TRIGGER trg_force_org BEFORE INSERT ON public.questao
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org();

-- avaliacao / respostas: RH lê a própria org (resultados). Escrita é
-- exclusiva do service_role (Edge Function), então nenhuma policy de
-- INSERT para authenticated.
DROP POLICY IF EXISTS "RH lê avaliacoes" ON public.avaliacao;
CREATE POLICY "RH lê avaliacoes" ON public.avaliacao FOR SELECT
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "RH lê respostas" ON public.avaliacao_resposta;
CREATE POLICY "RH lê respostas" ON public.avaliacao_resposta FOR SELECT
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org());

-- Isolamento por org + entitlement do módulo (RESTRICTIVE) nas 3.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['questao', 'avaliacao', 'avaliacao_resposta'] LOOP
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

-- ── 5. View de resultados para o RH ──────────────────────────
-- Uma linha por avaliação finalizada, com nome do candidato e vaga.
-- security_invoker: herda a RLS de avaliacao/candidato (org).
CREATE OR REPLACE VIEW public.avaliacao_resumo
WITH (security_invoker = true) AS
SELECT
  a.id,
  a.organization_id,
  a.candidato_id,
  c.nome        AS candidato_nome,
  a.vaga_id,
  v.titulo      AS vaga_titulo,
  a.nivel,
  a.total_questoes,
  a.acertos,
  a.nota,
  a.status,
  a.iniciada_em,
  a.finalizada_em
FROM public.avaliacao a
JOIN public.candidato c ON c.id = a.candidato_id
LEFT JOIN public.vaga v ON v.id = a.vaga_id;

-- ── 6. Contadores do banco de questões por cargo (Central) ───
CREATE OR REPLACE VIEW public.questao_contagem_cargo
WITH (security_invoker = true) AS
SELECT
  organization_id,
  cargo_id,
  count(*) AS total,
  count(*) FILTER (WHERE origem = 'ia') AS por_ia
FROM public.questao
WHERE deleted_at IS NULL AND ativa = true
GROUP BY organization_id, cargo_id;
