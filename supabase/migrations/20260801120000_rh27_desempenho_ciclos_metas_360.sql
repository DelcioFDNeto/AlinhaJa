-- ============================================================
-- RH-27 / Fase 8 — Desempenho: ciclos, metas e avaliação 360
-- (PLANO-RH-COMPLETO.md, seção 11: "Avaliação de desempenho: ciclos,
-- metas, feedback 360").
--
-- O que existia (rh21): rh_avaliacao_desempenho — uma nota solta por
-- funcionário. Continua valendo para 1:1 e avaliação de experiência.
-- O que entra agora:
--   • rh_ciclo_avaliacao  — a janela (ex.: "Avaliação Anual 2026")
--   • rh_meta             — metas do funcionário no ciclo, com peso
--   • rh_avaliacao_360    — um convite por (avaliado, avaliador, origem)
--
-- ANONIMATO — decisão de projeto: o avaliado NÃO tem SELECT em
-- rh_avaliacao_360. Se tivesse, leria quem escreveu cada crítica e o
-- 360 viraria teatro. Ele enxerga o próprio resultado por uma função
-- SECURITY DEFINER que só devolve agregados, e a média de PARES exige
-- um mínimo de respostas (k-anonimato) para não denunciar o autor.
--
-- Migration 100% aditiva.
-- ============================================================

-- ── 1. Ciclo de avaliação ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rh_ciclo_avaliacao (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  nome            TEXT NOT NULL CHECK (char_length(trim(nome)) BETWEEN 3 AND 120),
  descricao       TEXT,
  periodo_inicio  DATE NOT NULL,
  periodo_fim     DATE NOT NULL,
  -- Prazo para os avaliadores responderem.
  prazo_resposta  DATE,
  status          TEXT NOT NULL DEFAULT 'rascunho'
                    CHECK (status IN ('rascunho', 'aberto', 'encerrado')),
  -- Quais origens de feedback este ciclo coleta.
  usa_auto        BOOLEAN NOT NULL DEFAULT true,
  usa_gestor      BOOLEAN NOT NULL DEFAULT true,
  usa_pares       BOOLEAN NOT NULL DEFAULT true,
  usa_subordinado BOOLEAN NOT NULL DEFAULT false,
  -- Mínimo de respostas de pares para revelar a média ao avaliado.
  min_pares_anonimato SMALLINT NOT NULL DEFAULT 3
                    CHECK (min_pares_anonimato BETWEEN 1 AND 10),
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ,
  CONSTRAINT chk_ciclo_periodo CHECK (periodo_fim >= periodo_inicio)
);
CREATE INDEX IF NOT EXISTS idx_ciclo_org_status
  ON public.rh_ciclo_avaliacao(organization_id, status)
  WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS set_rh_ciclo_updated_at ON public.rh_ciclo_avaliacao;
CREATE TRIGGER set_rh_ciclo_updated_at
  BEFORE UPDATE ON public.rh_ciclo_avaliacao
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 2. Metas ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rh_meta (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  ciclo_id        UUID NOT NULL REFERENCES public.rh_ciclo_avaliacao(id) ON DELETE CASCADE,
  funcionario_id  UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  titulo          TEXT NOT NULL CHECK (char_length(trim(titulo)) BETWEEN 3 AND 200),
  descricao       TEXT,
  -- Como a meta é medida (texto livre: "R$", "% de churn", "NPS"...).
  metrica         TEXT,
  alvo            TEXT,
  resultado       TEXT,
  peso            SMALLINT NOT NULL DEFAULT 1 CHECK (peso BETWEEN 1 AND 10),
  progresso       SMALLINT NOT NULL DEFAULT 0 CHECK (progresso BETWEEN 0 AND 100),
  status          TEXT NOT NULL DEFAULT 'em_andamento'
                    CHECK (status IN ('em_andamento', 'atingida', 'nao_atingida', 'cancelada')),
  prazo           DATE,
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_meta_ciclo_func
  ON public.rh_meta(ciclo_id, funcionario_id);
CREATE INDEX IF NOT EXISTS idx_meta_org_func
  ON public.rh_meta(organization_id, funcionario_id);

DROP TRIGGER IF EXISTS set_rh_meta_updated_at ON public.rh_meta;
CREATE TRIGGER set_rh_meta_updated_at
  BEFORE UPDATE ON public.rh_meta
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 3. Avaliação 360 ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rh_avaliacao_360 (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  ciclo_id        UUID NOT NULL REFERENCES public.rh_ciclo_avaliacao(id) ON DELETE CASCADE,
  avaliado_id     UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  -- Quem responde precisa ter login: é um usuário, não uma ficha.
  avaliador_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  origem          TEXT NOT NULL
                    CHECK (origem IN ('auto', 'gestor', 'par', 'subordinado')),
  status          TEXT NOT NULL DEFAULT 'pendente'
                    CHECK (status IN ('pendente', 'respondida', 'dispensada')),
  nota            SMALLINT CHECK (nota IS NULL OR nota BETWEEN 0 AND 100),
  pontos_fortes   TEXT,
  pontos_melhoria TEXT,
  respondida_em   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Um convite por trio: ninguém avalia a mesma pessoa duas vezes na
-- mesma origem dentro do ciclo.
CREATE UNIQUE INDEX IF NOT EXISTS uq_360_ciclo_avaliado_avaliador_origem
  ON public.rh_avaliacao_360(ciclo_id, avaliado_id, avaliador_id, origem);
CREATE INDEX IF NOT EXISTS idx_360_avaliador_pendente
  ON public.rh_avaliacao_360(avaliador_id, status);
CREATE INDEX IF NOT EXISTS idx_360_ciclo_avaliado
  ON public.rh_avaliacao_360(ciclo_id, avaliado_id);

-- ── 4. RLS ───────────────────────────────────────────────────
ALTER TABLE public.rh_ciclo_avaliacao ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_meta            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_avaliacao_360   ENABLE ROW LEVEL SECURITY;

-- Ciclo: RH gerencia; qualquer um da org lê os ciclos abertos (precisa,
-- para responder convites e ver as próprias metas).
DROP POLICY IF EXISTS "RH gerencia ciclos" ON public.rh_ciclo_avaliacao;
CREATE POLICY "RH gerencia ciclos" ON public.rh_ciclo_avaliacao FOR ALL
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org()
         AND deleted_at IS NULL)
  WITH CHECK (public.fn_is_rh() AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "Org lê ciclos ativos" ON public.rh_ciclo_avaliacao;
CREATE POLICY "Org lê ciclos ativos" ON public.rh_ciclo_avaliacao FOR SELECT
  USING (organization_id = public.fn_current_org()
         AND deleted_at IS NULL
         AND status <> 'rascunho');

-- Meta: RH gerencia; o funcionário lê as próprias (atualiza via RPC).
DROP POLICY IF EXISTS "RH gerencia metas" ON public.rh_meta;
CREATE POLICY "RH gerencia metas" ON public.rh_meta FOR ALL
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org())
  WITH CHECK (public.fn_is_rh() AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "Funcionário lê próprias metas" ON public.rh_meta;
CREATE POLICY "Funcionário lê próprias metas" ON public.rh_meta FOR SELECT
  USING (public.fn_is_own_funcionario(funcionario_id));

-- 360: RH lê tudo (é quem consolida). O AVALIADOR vê e responde só as
-- linhas dele. O AVALIADO não tem SELECT aqui de propósito — o
-- resultado dele sai agregado por rh_meu_resultado_360.
DROP POLICY IF EXISTS "RH lê 360" ON public.rh_avaliacao_360;
CREATE POLICY "RH lê 360" ON public.rh_avaliacao_360 FOR SELECT
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "RH cria convites 360" ON public.rh_avaliacao_360;
CREATE POLICY "RH cria convites 360" ON public.rh_avaliacao_360 FOR INSERT
  WITH CHECK (public.fn_is_rh() AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "Avaliador lê próprios convites" ON public.rh_avaliacao_360;
CREATE POLICY "Avaliador lê próprios convites" ON public.rh_avaliacao_360 FOR SELECT
  USING (avaliador_id = auth.uid()
         AND organization_id = public.fn_current_org());

-- Isolamento por org + entitlement do módulo nas três tabelas.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['rh_ciclo_avaliacao', 'rh_meta', 'rh_avaliacao_360'] LOOP
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
      t, 'rh_desempenho', 'rh_desempenho');
    EXECUTE format('DROP TRIGGER IF EXISTS trg_force_org ON public.%I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_force_org BEFORE INSERT ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org()', t);
  END LOOP;
END $$;

-- ── 5. RH convida um avaliador ───────────────────────────────
CREATE OR REPLACE FUNCTION public.rh_360_convidar(
  p_ciclo_id     uuid,
  p_avaliado_id  uuid,
  p_avaliador_id uuid,
  p_origem       text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org   uuid := public.fn_current_org();
  v_ciclo public.rh_ciclo_avaliacao%ROWTYPE;
  v_id    uuid;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Apenas o RH pode convidar avaliadores';
  END IF;

  SELECT * INTO v_ciclo FROM public.rh_ciclo_avaliacao
   WHERE id = p_ciclo_id AND organization_id = v_org AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ciclo não encontrado';
  END IF;
  IF v_ciclo.status = 'encerrado' THEN
    RAISE EXCEPTION 'Ciclo encerrado: não aceita novos convites';
  END IF;

  -- Ambos os ids vêm do cliente e esta função é SECURITY DEFINER (a RLS
  -- não filtra aqui): sem estas checagens dava para convidar gente de
  -- outra empresa ou avaliar uma ficha de outro tenant.
  IF NOT EXISTS (SELECT 1 FROM public.funcionario
                  WHERE id = p_avaliado_id AND organization_id = v_org
                    AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Funcionário avaliado não encontrado nesta organização';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users
                  WHERE id = p_avaliador_id AND organization_id = v_org) THEN
    RAISE EXCEPTION 'Avaliador não encontrado nesta organização';
  END IF;

  -- A origem tem de estar habilitada no ciclo.
  IF (p_origem = 'auto'        AND NOT v_ciclo.usa_auto)
  OR (p_origem = 'gestor'      AND NOT v_ciclo.usa_gestor)
  OR (p_origem = 'par'         AND NOT v_ciclo.usa_pares)
  OR (p_origem = 'subordinado' AND NOT v_ciclo.usa_subordinado) THEN
    RAISE EXCEPTION 'Este ciclo não coleta feedback de origem "%"', p_origem;
  END IF;

  -- Autoavaliação: o avaliador precisa ser o próprio avaliado.
  IF p_origem = 'auto' AND NOT EXISTS (
       SELECT 1 FROM public.funcionario
        WHERE id = p_avaliado_id AND user_id = p_avaliador_id) THEN
    RAISE EXCEPTION 'Autoavaliação exige que o avaliador seja o próprio avaliado';
  END IF;
  -- Nas demais origens, avaliar a si mesmo seria autoavaliação disfarçada.
  IF p_origem <> 'auto' AND EXISTS (
       SELECT 1 FROM public.funcionario
        WHERE id = p_avaliado_id AND user_id = p_avaliador_id) THEN
    RAISE EXCEPTION 'Use a origem "auto" para autoavaliação';
  END IF;

  INSERT INTO public.rh_avaliacao_360
    (organization_id, ciclo_id, avaliado_id, avaliador_id, origem)
  VALUES (v_org, p_ciclo_id, p_avaliado_id, p_avaliador_id, p_origem)
  ON CONFLICT (ciclo_id, avaliado_id, avaliador_id, origem) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM public.rh_avaliacao_360
     WHERE ciclo_id = p_ciclo_id AND avaliado_id = p_avaliado_id
       AND avaliador_id = p_avaliador_id AND origem = p_origem;
  END IF;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_360_convidar(uuid, uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_360_convidar(uuid, uuid, uuid, text) TO authenticated;

-- ── 6. Avaliador responde ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rh_360_responder(
  p_avaliacao_id   uuid,
  p_nota           smallint,
  p_pontos_fortes  text DEFAULT NULL,
  p_pontos_melhoria text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_av    public.rh_avaliacao_360%ROWTYPE;
  v_ciclo public.rh_ciclo_avaliacao%ROWTYPE;
BEGIN
  SELECT * INTO v_av FROM public.rh_avaliacao_360 WHERE id = p_avaliacao_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Avaliação não encontrada';
  END IF;
  IF v_av.avaliador_id <> auth.uid() THEN
    RAISE EXCEPTION 'Esta avaliação não é sua';
  END IF;
  IF v_av.status = 'respondida' THEN
    RAISE EXCEPTION 'Você já respondeu esta avaliação';
  END IF;
  IF p_nota IS NULL OR p_nota NOT BETWEEN 0 AND 100 THEN
    RAISE EXCEPTION 'A nota deve ficar entre 0 e 100';
  END IF;

  SELECT * INTO v_ciclo FROM public.rh_ciclo_avaliacao WHERE id = v_av.ciclo_id;
  IF v_ciclo.status <> 'aberto' THEN
    RAISE EXCEPTION 'O ciclo não está aberto para respostas';
  END IF;

  UPDATE public.rh_avaliacao_360
     SET status          = 'respondida',
         nota            = p_nota,
         pontos_fortes   = NULLIF(trim(COALESCE(p_pontos_fortes, '')), ''),
         pontos_melhoria = NULLIF(trim(COALESCE(p_pontos_melhoria, '')), ''),
         respondida_em   = NOW()
   WHERE id = p_avaliacao_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_360_responder(uuid, smallint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_360_responder(uuid, smallint, text, text) TO authenticated;

-- ── 7. Progresso de meta ─────────────────────────────────────
-- RH mexe em qualquer meta da org; o funcionário só nas próprias.
CREATE OR REPLACE FUNCTION public.rh_meta_progresso(
  p_meta_id   uuid,
  p_progresso smallint,
  p_resultado text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_meta public.rh_meta%ROWTYPE;
BEGIN
  -- Filtro por org no próprio SELECT: fn_is_rh() só diz que a pessoa é RH
  -- na organização dela, não que a meta pertence a essa organização.
  SELECT * INTO v_meta FROM public.rh_meta
   WHERE id = p_meta_id AND organization_id = public.fn_current_org();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Meta não encontrada';
  END IF;
  IF NOT (public.fn_is_rh() OR public.fn_is_own_funcionario(v_meta.funcionario_id)) THEN
    RAISE EXCEPTION 'Sem permissão para atualizar esta meta';
  END IF;
  IF p_progresso NOT BETWEEN 0 AND 100 THEN
    RAISE EXCEPTION 'O progresso deve ficar entre 0 e 100';
  END IF;
  IF v_meta.status = 'cancelada' THEN
    RAISE EXCEPTION 'Meta cancelada não aceita atualização';
  END IF;

  UPDATE public.rh_meta
     SET progresso = p_progresso,
         resultado = COALESCE(NULLIF(trim(COALESCE(p_resultado, '')), ''), resultado),
         -- 100% fecha a meta; abaixo disso volta a "em andamento" para
         -- não travar quem corrigiu um lançamento errado.
         status    = CASE WHEN p_progresso = 100 THEN 'atingida'
                          WHEN status = 'atingida' THEN 'em_andamento'
                          ELSE status END
   WHERE id = p_meta_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_meta_progresso(uuid, smallint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_meta_progresso(uuid, smallint, text) TO authenticated;

-- ── 8. Consolidado do ciclo (RH) ─────────────────────────────
-- Uma linha por avaliado: média por origem, média geral e o andamento
-- das metas (ponderado pelo peso). security_invoker → só o RH lê, que
-- é quem tem SELECT em rh_avaliacao_360.
CREATE OR REPLACE VIEW public.rh_desempenho_consolidado
WITH (security_invoker = true) AS
SELECT
  a.ciclo_id,
  a.organization_id,
  a.avaliado_id,
  f.nome AS avaliado_nome,
  count(*)                                          AS convites,
  count(*) FILTER (WHERE a.status = 'respondida')   AS respondidas,
  round(avg(a.nota) FILTER (WHERE a.status = 'respondida'), 1) AS nota_geral,
  round(avg(a.nota) FILTER (WHERE a.status = 'respondida' AND a.origem = 'auto'), 1)        AS nota_auto,
  round(avg(a.nota) FILTER (WHERE a.status = 'respondida' AND a.origem = 'gestor'), 1)      AS nota_gestor,
  round(avg(a.nota) FILTER (WHERE a.status = 'respondida' AND a.origem = 'par'), 1)         AS nota_pares,
  round(avg(a.nota) FILTER (WHERE a.status = 'respondida' AND a.origem = 'subordinado'), 1) AS nota_subordinados,
  m.progresso_metas
FROM public.rh_avaliacao_360 a
JOIN public.funcionario f ON f.id = a.avaliado_id
LEFT JOIN LATERAL (
  SELECT round(
           sum(mt.progresso * mt.peso)::numeric / NULLIF(sum(mt.peso), 0), 1
         ) AS progresso_metas
  FROM public.rh_meta mt
  WHERE mt.ciclo_id = a.ciclo_id
    AND mt.funcionario_id = a.avaliado_id
    AND mt.status <> 'cancelada'
) m ON true
GROUP BY a.ciclo_id, a.organization_id, a.avaliado_id, f.nome, m.progresso_metas;

-- ── 9. Resultado do próprio avaliado (anonimizado) ───────────
-- Devolve só agregados. A média de pares fica NULL enquanto não houver
-- min_pares_anonimato respostas — com uma ou duas, o avaliado
-- identificaria o autor.
CREATE OR REPLACE FUNCTION public.rh_meu_resultado_360(p_ciclo_id uuid)
RETURNS TABLE (
  ciclo_id          uuid,
  respondidas       bigint,
  nota_geral        numeric,
  nota_auto         numeric,
  nota_gestor       numeric,
  nota_pares        numeric,
  pares_respondidas bigint,
  pares_anonimato_ok boolean,
  progresso_metas   numeric)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_func  uuid;
  v_min   smallint;
BEGIN
  SELECT id INTO v_func FROM public.funcionario
   WHERE user_id = auth.uid()
     AND organization_id = public.fn_current_org()
     AND deleted_at IS NULL;
  IF v_func IS NULL THEN
    RAISE EXCEPTION 'Você não está vinculado a uma ficha de funcionário';
  END IF;

  SELECT c.min_pares_anonimato INTO v_min
    FROM public.rh_ciclo_avaliacao c
   WHERE c.id = p_ciclo_id AND c.organization_id = public.fn_current_org();
  IF v_min IS NULL THEN
    RAISE EXCEPTION 'Ciclo não encontrado';
  END IF;

  RETURN QUERY
  WITH r AS (
    SELECT a.nota, a.origem
    FROM public.rh_avaliacao_360 a
    WHERE a.ciclo_id = p_ciclo_id
      AND a.avaliado_id = v_func
      AND a.status = 'respondida'
  ), pares AS (
    SELECT count(*) AS qtd, avg(nota) AS media FROM r WHERE origem = 'par'
  )
  SELECT
    p_ciclo_id,
    (SELECT count(*) FROM r),
    (SELECT round(avg(nota), 1) FROM r),
    (SELECT round(avg(nota), 1) FROM r WHERE origem = 'auto'),
    (SELECT round(avg(nota), 1) FROM r WHERE origem = 'gestor'),
    -- k-anonimato: abaixo do mínimo, não revela.
    CASE WHEN (SELECT qtd FROM pares) >= v_min
         THEN (SELECT round(media, 1) FROM pares) END,
    (SELECT qtd FROM pares),
    ((SELECT qtd FROM pares) >= v_min),
    (SELECT round(sum(mt.progresso * mt.peso)::numeric / NULLIF(sum(mt.peso), 0), 1)
       FROM public.rh_meta mt
      WHERE mt.ciclo_id = p_ciclo_id AND mt.funcionario_id = v_func
        AND mt.status <> 'cancelada');
END;
$$;
REVOKE ALL ON FUNCTION public.rh_meu_resultado_360(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_meu_resultado_360(uuid) TO authenticated;

-- ── 10. Convites pendentes do usuário logado ─────────────────
-- security_invoker + a policy "Avaliador lê próprios convites" já
-- limitam a linha; o join traz o nome de quem avaliar.
CREATE OR REPLACE VIEW public.rh_minhas_avaliacoes_360
WITH (security_invoker = true) AS
SELECT
  a.id,
  a.organization_id,
  a.ciclo_id,
  c.nome          AS ciclo_nome,
  c.prazo_resposta,
  c.status        AS ciclo_status,
  a.avaliado_id,
  f.nome          AS avaliado_nome,
  a.origem,
  a.status,
  a.nota,
  a.respondida_em
FROM public.rh_avaliacao_360 a
JOIN public.rh_ciclo_avaliacao c ON c.id = a.ciclo_id
JOIN public.funcionario f ON f.id = a.avaliado_id
WHERE a.avaliador_id = auth.uid();

COMMENT ON VIEW public.rh_minhas_avaliacoes_360 IS
  'Convites de avaliação 360 do usuário logado (quem ele precisa avaliar).';
