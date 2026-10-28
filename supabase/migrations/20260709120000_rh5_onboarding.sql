-- ============================================================
-- Módulo RH-5 — Onboarding e Período de Experiência (S082–S092)
-- Templates de integração + execução por funcionário com itens
-- (checklist), progresso automático (S088), bloqueio de conclusão
-- com obrigatórios pendentes (S091), período de experiência 45+45
-- com alerta D-7 (S086/S087) e job pg_cron diário que alimenta um
-- feed de alertas do RH (rh_alerta — S089/S090).
--
-- O onboarding é iniciado automaticamente na conversão
-- candidato→funcionário quando a organização tem um template
-- padrão ativo (S082/S078). Multi-tenant: tudo escopado por
-- organization_id e protegido por fn_is_rh()/fn_is_rh_admin().
-- ============================================================

-- ── 1. Enums ─────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE public.onboarding_status AS ENUM
    ('em_andamento', 'concluido', 'cancelado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.onboarding_item_status AS ENUM
    ('pendente', 'concluido', 'nao_aplicavel');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.experiencia_fase AS ENUM
    ('primeiro_periodo', 'segundo_periodo', 'concluido');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.experiencia_resultado AS ENUM
    ('em_andamento', 'efetivado', 'desligado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 2. Templates de onboarding ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.onboarding_template (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  nome            TEXT NOT NULL CHECK (char_length(nome) >= 3),
  descricao       TEXT,
  ativo           BOOLEAN NOT NULL DEFAULT true,
  -- Template padrão usado na conversão candidato->funcionário (S082)
  padrao          BOOLEAN NOT NULL DEFAULT false,
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ
);

-- Nome único por org (entre os não excluídos)
CREATE UNIQUE INDEX IF NOT EXISTS uq_onboarding_template_nome
  ON public.onboarding_template(organization_id, lower(nome))
  WHERE deleted_at IS NULL;
-- No máximo um template padrão ativo por org
CREATE UNIQUE INDEX IF NOT EXISTS uq_onboarding_template_padrao
  ON public.onboarding_template(organization_id)
  WHERE padrao = true AND ativo = true AND deleted_at IS NULL;

DROP TRIGGER IF EXISTS onboarding_template_updated_at ON public.onboarding_template;
CREATE TRIGGER onboarding_template_updated_at
  BEFORE UPDATE ON public.onboarding_template
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.onboarding_template_item (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id     UUID NOT NULL REFERENCES public.onboarding_template(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  ordem           SMALLINT NOT NULL DEFAULT 0,
  titulo          TEXT NOT NULL CHECK (char_length(titulo) >= 2),
  descricao       TEXT,
  -- documentacao | equipamento | acesso | treinamento | integracao | outro
  categoria       TEXT NOT NULL DEFAULT 'outro',
  obrigatorio     BOOLEAN NOT NULL DEFAULT true,
  -- prazo em dias corridos a partir da data de admissão
  prazo_dias      SMALLINT,
  -- rh | gestor | funcionario
  responsavel     TEXT NOT NULL DEFAULT 'rh',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_onb_template_item_tpl
  ON public.onboarding_template_item(template_id, ordem);

-- ── 3. Execução do onboarding por funcionário ────────────────
CREATE TABLE IF NOT EXISTS public.onboarding_execucao (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  funcionario_id   UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  organization_id  UUID NOT NULL REFERENCES public.organizations(id),
  template_id      UUID REFERENCES public.onboarding_template(id),
  template_nome    TEXT,
  status           public.onboarding_status NOT NULL DEFAULT 'em_andamento',
  progresso        SMALLINT NOT NULL DEFAULT 0,   -- 0..100
  data_inicio      DATE NOT NULL DEFAULT CURRENT_DATE,
  data_prevista    DATE,
  data_conclusao   DATE,
  created_by       UUID REFERENCES public.users(id),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_onb_execucao_func
  ON public.onboarding_execucao(funcionario_id, status);
CREATE INDEX IF NOT EXISTS idx_onb_execucao_org
  ON public.onboarding_execucao(organization_id, status);
-- Uma execução ativa por funcionário
CREATE UNIQUE INDEX IF NOT EXISTS uq_onb_execucao_ativa
  ON public.onboarding_execucao(funcionario_id)
  WHERE status = 'em_andamento';

DROP TRIGGER IF EXISTS onboarding_execucao_updated_at ON public.onboarding_execucao;
CREATE TRIGGER onboarding_execucao_updated_at
  BEFORE UPDATE ON public.onboarding_execucao
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.onboarding_item (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execucao_id     UUID NOT NULL REFERENCES public.onboarding_execucao(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  funcionario_id  UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  ordem           SMALLINT NOT NULL DEFAULT 0,
  titulo          TEXT NOT NULL,
  descricao       TEXT,
  categoria       TEXT NOT NULL DEFAULT 'outro',
  obrigatorio     BOOLEAN NOT NULL DEFAULT true,
  responsavel     TEXT NOT NULL DEFAULT 'rh',
  prazo           DATE,
  status          public.onboarding_item_status NOT NULL DEFAULT 'pendente',
  observacao      TEXT,
  concluido_em    TIMESTAMPTZ,
  concluido_por   UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_onb_item_execucao
  ON public.onboarding_item(execucao_id, ordem);
CREATE INDEX IF NOT EXISTS idx_onb_item_prazo
  ON public.onboarding_item(organization_id, prazo)
  WHERE status = 'pendente';

-- ── 4. Período de experiência (45+45 — S086/S087) ────────────
CREATE TABLE IF NOT EXISTS public.periodo_experiencia (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  funcionario_id   UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  vinculo_id       UUID REFERENCES public.vinculo(id) ON DELETE SET NULL,
  organization_id  UUID NOT NULL REFERENCES public.organizations(id),
  data_inicio      DATE NOT NULL,
  fim_primeiro     DATE NOT NULL,   -- data_inicio + 45
  fim_segundo      DATE NOT NULL,   -- data_inicio + 90
  fase             public.experiencia_fase NOT NULL DEFAULT 'primeiro_periodo',
  resultado        public.experiencia_resultado NOT NULL DEFAULT 'em_andamento',
  alerta_d7_primeiro_em TIMESTAMPTZ,
  alerta_d7_segundo_em  TIMESTAMPTZ,
  decidido_em      TIMESTAMPTZ,
  decidido_por     UUID REFERENCES public.users(id),
  observacao       TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_periodo_exp_func
  ON public.periodo_experiencia(funcionario_id);
CREATE INDEX IF NOT EXISTS idx_periodo_exp_aberto
  ON public.periodo_experiencia(organization_id, fim_primeiro, fim_segundo)
  WHERE resultado = 'em_andamento';

DROP TRIGGER IF EXISTS periodo_experiencia_updated_at ON public.periodo_experiencia;
CREATE TRIGGER periodo_experiencia_updated_at
  BEFORE UPDATE ON public.periodo_experiencia
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 5. Feed de alertas do RH (S089/S090) ─────────────────────
CREATE TABLE IF NOT EXISTS public.rh_alerta (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  funcionario_id  UUID REFERENCES public.funcionario(id) ON DELETE CASCADE,
  -- experiencia_d7 | item_atrasado | onboarding_concluido
  tipo            TEXT NOT NULL,
  titulo          TEXT NOT NULL,
  mensagem        TEXT,
  severidade      TEXT NOT NULL DEFAULT 'info',  -- info | alerta
  -- chave de deduplicação: cada alerta dispara uma única vez
  chave           TEXT NOT NULL,
  lido            BOOLEAN NOT NULL DEFAULT false,
  lido_por        UUID REFERENCES public.users(id),
  lido_em         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_rh_alerta_chave ON public.rh_alerta(chave);
CREATE INDEX IF NOT EXISTS idx_rh_alerta_feed
  ON public.rh_alerta(organization_id, lido, created_at DESC);

-- ── 6. RLS ───────────────────────────────────────────────────
ALTER TABLE public.onboarding_template      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.onboarding_template_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.onboarding_execucao      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.onboarding_item          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.periodo_experiencia      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_alerta                ENABLE ROW LEVEL SECURITY;

-- Todas as tabelas de RH-5: RH gerencia dentro da própria org.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'onboarding_template', 'onboarding_template_item',
    'onboarding_execucao', 'onboarding_item', 'periodo_experiencia'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS "RH gerencia %1$s" ON public.%1$s', t);
    EXECUTE format(
      'CREATE POLICY "RH gerencia %1$s" ON public.%1$s FOR ALL '
      'USING (public.fn_is_rh() AND organization_id = public.fn_current_org()) '
      'WITH CHECK (public.fn_is_rh() AND organization_id = public.fn_current_org())',
      t);
  END LOOP;
END $$;

-- rh_alerta: RH lê e marca como lido; inserção só via cron (definer)
DROP POLICY IF EXISTS "RH lê alertas" ON public.rh_alerta;
CREATE POLICY "RH lê alertas"
  ON public.rh_alerta FOR SELECT
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "RH marca alertas como lido" ON public.rh_alerta;
CREATE POLICY "RH marca alertas como lido"
  ON public.rh_alerta FOR UPDATE
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org())
  WITH CHECK (organization_id = public.fn_current_org());

-- ── 7. Trigger de progresso (S088) ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_onboarding_progresso()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_exec uuid := COALESCE(NEW.execucao_id, OLD.execucao_id);
  v_total int;
  v_feitos int;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE status IN ('concluido', 'nao_aplicavel'))
    INTO v_total, v_feitos
  FROM public.onboarding_item WHERE execucao_id = v_exec;

  UPDATE public.onboarding_execucao
  SET progresso = CASE WHEN v_total = 0 THEN 0
                       ELSE round(v_feitos::numeric * 100 / v_total) END
  WHERE id = v_exec;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_onboarding_progresso ON public.onboarding_item;
CREATE TRIGGER trg_onboarding_progresso
  AFTER INSERT OR UPDATE OF status OR DELETE ON public.onboarding_item
  FOR EACH ROW EXECUTE FUNCTION public.fn_onboarding_progresso();

-- ── 8. RPC: iniciar onboarding a partir de um template ───────
CREATE OR REPLACE FUNCTION public.rh_iniciar_onboarding(
  p_funcionario_id uuid, p_template_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_admissao date;
  v_tpl public.onboarding_template%ROWTYPE;
  v_exec_id uuid;
  v_max_prazo int;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionario f
                 WHERE f.id = p_funcionario_id AND f.organization_id = v_org
                   AND f.deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Funcionário não encontrado';
  END IF;
  IF EXISTS (SELECT 1 FROM public.onboarding_execucao
             WHERE funcionario_id = p_funcionario_id AND status = 'em_andamento') THEN
    RAISE EXCEPTION 'Funcionário já possui um onboarding em andamento';
  END IF;

  SELECT * INTO v_tpl FROM public.onboarding_template
  WHERE id = p_template_id AND organization_id = v_org AND deleted_at IS NULL;
  IF v_tpl.id IS NULL THEN
    RAISE EXCEPTION 'Template não encontrado';
  END IF;

  SELECT data_admissao INTO v_admissao FROM public.vinculo
  WHERE funcionario_id = p_funcionario_id
  ORDER BY created_at DESC LIMIT 1;
  v_admissao := COALESCE(v_admissao, CURRENT_DATE);

  SELECT max(coalesce(prazo_dias, 0)) INTO v_max_prazo
  FROM public.onboarding_template_item WHERE template_id = p_template_id;

  INSERT INTO public.onboarding_execucao
    (funcionario_id, organization_id, template_id, template_nome,
     data_inicio, data_prevista, created_by)
  VALUES (p_funcionario_id, v_org, v_tpl.id, v_tpl.nome,
          CURRENT_DATE,
          v_admissao + COALESCE(v_max_prazo, 0),
          auth.uid())
  RETURNING id INTO v_exec_id;

  -- Snapshot dos itens do template (com prazo já calculado)
  INSERT INTO public.onboarding_item
    (execucao_id, organization_id, funcionario_id, ordem, titulo, descricao,
     categoria, obrigatorio, responsavel, prazo)
  SELECT v_exec_id, v_org, p_funcionario_id, ti.ordem, ti.titulo, ti.descricao,
         ti.categoria, ti.obrigatorio, ti.responsavel,
         CASE WHEN ti.prazo_dias IS NULL THEN NULL
              ELSE v_admissao + ti.prazo_dias END
  FROM public.onboarding_template_item ti
  WHERE ti.template_id = p_template_id
  ORDER BY ti.ordem;

  RETURN v_exec_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_iniciar_onboarding(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_iniciar_onboarding(uuid, uuid) TO authenticated;

-- ── 9. RPC: concluir/atualizar item do checklist ─────────────
CREATE OR REPLACE FUNCTION public.rh_atualizar_item_onboarding(
  p_item_id uuid, p_status public.onboarding_item_status,
  p_observacao text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;
  UPDATE public.onboarding_item
  SET status = p_status,
      observacao = COALESCE(p_observacao, observacao),
      concluido_em = CASE WHEN p_status = 'pendente' THEN NULL ELSE NOW() END,
      concluido_por = CASE WHEN p_status = 'pendente' THEN NULL ELSE auth.uid() END
  WHERE id = p_item_id AND organization_id = v_org;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Item não encontrado';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_atualizar_item_onboarding(uuid, public.onboarding_item_status, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_atualizar_item_onboarding(uuid, public.onboarding_item_status, text) TO authenticated;

-- ── 10. RPC: concluir onboarding (bloqueia obrigatórios — S091) ─
CREATE OR REPLACE FUNCTION public.rh_concluir_onboarding(p_execucao_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_pendentes int;
  v_func uuid;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;

  SELECT funcionario_id INTO v_func FROM public.onboarding_execucao
  WHERE id = p_execucao_id AND organization_id = v_org AND status = 'em_andamento';
  IF v_func IS NULL THEN
    RAISE EXCEPTION 'Onboarding não encontrado ou já finalizado';
  END IF;

  SELECT count(*) INTO v_pendentes FROM public.onboarding_item
  WHERE execucao_id = p_execucao_id AND obrigatorio AND status = 'pendente';
  IF v_pendentes > 0 THEN
    RAISE EXCEPTION 'Existem % item(ns) obrigatório(s) pendente(s)', v_pendentes;
  END IF;

  UPDATE public.onboarding_execucao
  SET status = 'concluido', progresso = 100, data_conclusao = CURRENT_DATE
  WHERE id = p_execucao_id;

  INSERT INTO public.rh_alerta
    (organization_id, funcionario_id, tipo, titulo, mensagem, severidade, chave)
  VALUES (v_org, v_func, 'onboarding_concluido', 'Onboarding concluído',
          'A integração do funcionário foi concluída.', 'info',
          'onb_ok_' || p_execucao_id::text)
  ON CONFLICT (chave) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_concluir_onboarding(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_concluir_onboarding(uuid) TO authenticated;

-- ── 11. RPC: iniciar período de experiência (45+45) ──────────
CREATE OR REPLACE FUNCTION public.rh_iniciar_experiencia(
  p_funcionario_id uuid, p_data_inicio date DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_vinc uuid;
  v_inicio date;
  v_id uuid;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;

  SELECT id, data_admissao INTO v_vinc, v_inicio FROM public.vinculo
  WHERE funcionario_id = p_funcionario_id AND organization_id = v_org
  ORDER BY created_at DESC LIMIT 1;
  IF v_vinc IS NULL THEN
    RAISE EXCEPTION 'Funcionário sem vínculo ativo';
  END IF;
  v_inicio := COALESCE(p_data_inicio, v_inicio, CURRENT_DATE);

  IF EXISTS (SELECT 1 FROM public.periodo_experiencia
             WHERE funcionario_id = p_funcionario_id AND resultado = 'em_andamento') THEN
    RAISE EXCEPTION 'Já existe um período de experiência em andamento';
  END IF;

  INSERT INTO public.periodo_experiencia
    (funcionario_id, vinculo_id, organization_id, data_inicio,
     fim_primeiro, fim_segundo)
  VALUES (p_funcionario_id, v_vinc, v_org, v_inicio,
          v_inicio + 45, v_inicio + 90)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_iniciar_experiencia(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_iniciar_experiencia(uuid, date) TO authenticated;

-- ── 12. RPC: decidir experiência (efetivar/prorrogar/desligar) ─
CREATE OR REPLACE FUNCTION public.rh_decidir_experiencia(
  p_periodo_id uuid, p_decisao text, p_observacao text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_p public.periodo_experiencia%ROWTYPE;
BEGIN
  -- Decisão de experiência exige RH admin
  IF NOT public.fn_is_rh_admin() THEN
    RAISE EXCEPTION 'Apenas administradores do RH podem decidir a experiência';
  END IF;

  SELECT * INTO v_p FROM public.periodo_experiencia
  WHERE id = p_periodo_id AND organization_id = v_org FOR UPDATE;
  IF v_p.id IS NULL THEN
    RAISE EXCEPTION 'Período de experiência não encontrado';
  END IF;
  IF v_p.resultado <> 'em_andamento' THEN
    RAISE EXCEPTION 'Período de experiência já foi decidido';
  END IF;

  IF p_decisao = 'prorrogar' THEN
    -- Passa do 1º para o 2º período (45+45). Só faz sentido no 1º.
    IF v_p.fase <> 'primeiro_periodo' THEN
      RAISE EXCEPTION 'Só é possível prorrogar durante o primeiro período';
    END IF;
    UPDATE public.periodo_experiencia
    SET fase = 'segundo_periodo', observacao = COALESCE(p_observacao, observacao)
    WHERE id = p_periodo_id;

  ELSIF p_decisao = 'efetivar' THEN
    UPDATE public.periodo_experiencia
    SET resultado = 'efetivado', fase = 'concluido',
        decidido_em = NOW(), decidido_por = auth.uid(),
        observacao = COALESCE(p_observacao, observacao)
    WHERE id = p_periodo_id;
    UPDATE public.vinculo SET status = 'efetivo'
    WHERE id = v_p.vinculo_id AND status = 'experiencia';

  ELSIF p_decisao = 'desligar' THEN
    UPDATE public.periodo_experiencia
    SET resultado = 'desligado', fase = 'concluido',
        decidido_em = NOW(), decidido_por = auth.uid(),
        observacao = COALESCE(p_observacao, observacao)
    WHERE id = p_periodo_id;
    UPDATE public.vinculo SET status = 'desligado',
           data_desligamento = CURRENT_DATE
    WHERE id = v_p.vinculo_id;
    UPDATE public.funcionario SET status = 'desligado', updated_by = auth.uid()
    WHERE id = v_p.funcionario_id;

  ELSE
    RAISE EXCEPTION 'Decisão inválida: % (use efetivar | prorrogar | desligar)', p_decisao;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_decidir_experiencia(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_decidir_experiencia(uuid, text, text) TO authenticated;

-- ── 13. RPC: marcar alerta como lido ─────────────────────────
CREATE OR REPLACE FUNCTION public.rh_marcar_alerta_lido(p_alerta_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;
  UPDATE public.rh_alerta
  SET lido = true, lido_por = auth.uid(), lido_em = NOW()
  WHERE id = p_alerta_id AND organization_id = v_org;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_marcar_alerta_lido(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_marcar_alerta_lido(uuid) TO authenticated;

-- ── 14. Job diário: alertas de experiência D-7 e itens atrasados ─
-- (S089/S090) Roda por pg_cron; alimenta rh_alerta com deduplicação.
CREATE OR REPLACE FUNCTION public.fn_rh_cron_diario()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE r record;
BEGIN
  -- 14.1 Experiência: D-7 do fim do 1º período
  FOR r IN
    SELECT pe.id, pe.organization_id, pe.funcionario_id, pe.fim_primeiro, f.nome
    FROM public.periodo_experiencia pe
    JOIN public.funcionario f ON f.id = pe.funcionario_id
    WHERE pe.resultado = 'em_andamento' AND pe.fase = 'primeiro_periodo'
      AND pe.alerta_d7_primeiro_em IS NULL
      AND pe.fim_primeiro <= CURRENT_DATE + 7
  LOOP
    INSERT INTO public.rh_alerta
      (organization_id, funcionario_id, tipo, titulo, mensagem, severidade, chave)
    VALUES (r.organization_id, r.funcionario_id, 'experiencia_d7',
      'Fim do 1º período de experiência se aproxima',
      format('O 1º período de experiência de %s termina em %s. Decida efetivar, prorrogar (45+45) ou desligar.',
             r.nome, to_char(r.fim_primeiro, 'DD/MM/YYYY')),
      'alerta', 'exp_d7_1_' || r.id::text)
    ON CONFLICT (chave) DO NOTHING;
    UPDATE public.periodo_experiencia SET alerta_d7_primeiro_em = NOW() WHERE id = r.id;
  END LOOP;

  -- 14.2 Experiência: D-7 do fim do 2º período
  FOR r IN
    SELECT pe.id, pe.organization_id, pe.funcionario_id, pe.fim_segundo, f.nome
    FROM public.periodo_experiencia pe
    JOIN public.funcionario f ON f.id = pe.funcionario_id
    WHERE pe.resultado = 'em_andamento' AND pe.fase = 'segundo_periodo'
      AND pe.alerta_d7_segundo_em IS NULL
      AND pe.fim_segundo <= CURRENT_DATE + 7
  LOOP
    INSERT INTO public.rh_alerta
      (organization_id, funcionario_id, tipo, titulo, mensagem, severidade, chave)
    VALUES (r.organization_id, r.funcionario_id, 'experiencia_d7',
      'Fim do período de experiência se aproxima',
      format('O período de experiência de %s termina em %s. Decida efetivar ou desligar.',
             r.nome, to_char(r.fim_segundo, 'DD/MM/YYYY')),
      'alerta', 'exp_d7_2_' || r.id::text)
    ON CONFLICT (chave) DO NOTHING;
    UPDATE public.periodo_experiencia SET alerta_d7_segundo_em = NOW() WHERE id = r.id;
  END LOOP;

  -- 14.3 Itens de onboarding atrasados (prazo vencido e ainda pendentes)
  FOR r IN
    SELECT oi.id, oi.organization_id, oi.funcionario_id, oi.titulo, oi.prazo, f.nome
    FROM public.onboarding_item oi
    JOIN public.onboarding_execucao oe ON oe.id = oi.execucao_id
    JOIN public.funcionario f ON f.id = oi.funcionario_id
    WHERE oi.status = 'pendente' AND oe.status = 'em_andamento'
      AND oi.prazo IS NOT NULL AND oi.prazo < CURRENT_DATE
  LOOP
    INSERT INTO public.rh_alerta
      (organization_id, funcionario_id, tipo, titulo, mensagem, severidade, chave)
    VALUES (r.organization_id, r.funcionario_id, 'item_atrasado',
      'Item de onboarding atrasado',
      format('"%s" (%s) venceu em %s.', r.titulo, r.nome,
             to_char(r.prazo, 'DD/MM/YYYY')),
      'alerta', 'item_atraso_' || r.id::text)
    ON CONFLICT (chave) DO NOTHING;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_rh_cron_diario() FROM PUBLIC, anon, authenticated;

-- Agenda diária via pg_cron. Guardado num bloco que não derruba a
-- migration caso a extensão ainda não esteja habilitada no projeto
-- (habilite pg_cron no dashboard e reexecute o SELECT cron.schedule).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('rh-cron-diario')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rh-cron-diario');
    PERFORM cron.schedule('rh-cron-diario', '0 9 * * *',
      $cron$ SELECT public.fn_rh_cron_diario(); $cron$);
  ELSE
    RAISE NOTICE 'pg_cron não habilitado: agende rh-cron-diario manualmente após habilitar a extensão.';
  END IF;
END $$;

-- ── 15. Gancho na conversão candidato→funcionário (S078/S082) ─
-- Reescreve rh_converter_candidato acrescentando: início automático
-- do onboarding (se houver template padrão ativo) e abertura do
-- período de experiência para vínculos CLT/aprendiz.
CREATE OR REPLACE FUNCTION public.rh_converter_candidato(
  p_candidato_id uuid,
  p_tipo public.vinculo_tipo DEFAULT 'clt',
  p_data_admissao date DEFAULT CURRENT_DATE,
  p_matricula text DEFAULT NULL,
  p_carga_horaria text DEFAULT NULL,
  p_salario text DEFAULT NULL,
  p_filial_id uuid DEFAULT NULL,
  p_departamento_id text DEFAULT NULL,
  p_cargo_id text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_cand public.candidato%ROWTYPE;
  v_func_id uuid;
  v_vinc_id uuid;
  v_tpl_id uuid;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;

  SELECT * INTO v_cand FROM public.candidato
  WHERE id = p_candidato_id AND organization_id = v_org
    AND deleted_at IS NULL
  FOR UPDATE;
  IF v_cand.id IS NULL THEN
    RAISE EXCEPTION 'Candidato não encontrado';
  END IF;
  IF v_cand.status <> 'aprovado' THEN
    RAISE EXCEPTION 'Somente candidatos aprovados podem ser convertidos (status atual: %)', v_cand.status;
  END IF;
  IF EXISTS (SELECT 1 FROM public.funcionario
             WHERE candidato_id = p_candidato_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Candidato já foi convertido em funcionário';
  END IF;

  INSERT INTO public.funcionario
    (organization_id, nome, foto_url, candidato_id, created_by)
  VALUES (v_org, v_cand.nome, v_cand.foto_url, v_cand.id, auth.uid())
  RETURNING id INTO v_func_id;

  INSERT INTO public.funcionario_dados_sensiveis
    (funcionario_id, organization_id, email_pessoal, telefone, updated_by)
  VALUES (v_func_id, v_org, v_cand.email, v_cand.telefone, auth.uid());

  INSERT INTO public.vinculo
    (funcionario_id, organization_id, tipo, data_admissao, matricula,
     carga_horaria, salario_encrypted, filial_id, departamento_id,
     cargo_id, created_by)
  VALUES (v_func_id, v_org, p_tipo, p_data_admissao, p_matricula,
          p_carga_horaria,
          public.fn_rh_encrypt(nullif(p_salario, ''), v_org),
          p_filial_id, p_departamento_id, p_cargo_id, auth.uid())
  RETURNING id INTO v_vinc_id;

  UPDATE public.candidato SET status = 'contratado', updated_by = auth.uid()
  WHERE id = p_candidato_id;

  -- RH-5: inicia onboarding com o template padrão ativo da org, se houver
  SELECT id INTO v_tpl_id FROM public.onboarding_template
  WHERE organization_id = v_org AND padrao = true AND ativo = true
    AND deleted_at IS NULL
  LIMIT 1;
  IF v_tpl_id IS NOT NULL THEN
    PERFORM public.rh_iniciar_onboarding(v_func_id, v_tpl_id);
  END IF;

  -- RH-5: abre período de experiência para vínculos com experiência (CLT/aprendiz)
  IF p_tipo IN ('clt', 'aprendiz') THEN
    INSERT INTO public.periodo_experiencia
      (funcionario_id, vinculo_id, organization_id, data_inicio,
       fim_primeiro, fim_segundo)
    VALUES (v_func_id, v_vinc_id, v_org, p_data_admissao,
            p_data_admissao + 45, p_data_admissao + 90);
  END IF;

  INSERT INTO public.rh_access_log
    (organization_id, funcionario_id, usuario_id, acao, detalhes)
  VALUES (v_org, v_func_id, auth.uid(), 'converteu_candidato',
          jsonb_build_object('candidato_id', p_candidato_id));

  RETURN v_func_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_converter_candidato FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_converter_candidato TO authenticated;
