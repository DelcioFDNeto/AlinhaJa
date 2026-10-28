-- ============================================================
-- RH-14 / Fase 5 — Pipeline avançado (parte 2: etapas por org)
-- (PLANO-RH-COMPLETO.md, Onda 5 — fecha a Fase 5).
--
-- O funil deixa de ser fixo no enum candidato_status e passa a ler
-- as etapas da organização em `pipeline_etapa` (seed = etapas atuais,
-- nada quebra). Três etapas têm papel reservado e slug imutável:
--   entrada    ('novo')       — onde candidaturas nascem/reativam
--   contratado ('contratado') — terminal de sucesso (conversão)
--   descartado ('descartado') — descarte, alcançável de qualquer etapa
-- As demais ('normal') podem ser criadas, renomeadas, recoloridas,
-- reordenadas e excluídas (se vazias) pelo admin do RH.
--
-- `candidato.status` vira TEXT (o enum limitaria os slugs novos);
-- o guard de transição continua no banco, agora dirigido por dados,
-- com fallback no comportamento estático para orgs sem etapas.
-- ============================================================

-- ── 1. Tabela de etapas ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pipeline_etapa (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  slug            TEXT NOT NULL CHECK (slug ~ '^[a-z0-9_]{2,40}$'),
  nome            TEXT NOT NULL CHECK (char_length(trim(nome)) BETWEEN 2 AND 40),
  ordem           SMALLINT NOT NULL CHECK (ordem BETWEEN 1 AND 99),
  -- Papel semântico de cor (StatusRole no app — white-label, nunca cor crua)
  role_cor        TEXT NOT NULL DEFAULT 'info' CHECK (role_cor IN
    ('success','info','warning','danger','neutral','highlight','progress','pending')),
  tipo            TEXT NOT NULL DEFAULT 'normal' CHECK (tipo IN
    ('entrada','normal','contratado','descartado')),
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_pipeline_etapa_org_slug
  ON public.pipeline_etapa(organization_id, slug);
-- Uma única etapa de cada tipo reservado por org
CREATE UNIQUE INDEX IF NOT EXISTS uq_pipeline_etapa_org_tipo
  ON public.pipeline_etapa(organization_id, tipo) WHERE tipo <> 'normal';
CREATE INDEX IF NOT EXISTS idx_pipeline_etapa_org_ordem
  ON public.pipeline_etapa(organization_id, ordem);

-- ── 2. Proteções estruturais (slug/tipo imutáveis, exclusão segura) ──
CREATE OR REPLACE FUNCTION public.fn_tg_pipeline_etapa_protege()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.slug IS DISTINCT FROM OLD.slug THEN
      RAISE EXCEPTION 'O identificador (slug) da etapa não pode ser alterado';
    END IF;
    IF NEW.tipo IS DISTINCT FROM OLD.tipo THEN
      RAISE EXCEPTION 'O tipo da etapa não pode ser alterado';
    END IF;
    RETURN NEW;
  END IF;
  -- DELETE
  IF OLD.tipo <> 'normal' THEN
    RAISE EXCEPTION 'As etapas de entrada, contratação e descarte não podem ser excluídas';
  END IF;
  IF EXISTS (SELECT 1 FROM public.candidato c
             WHERE c.organization_id = OLD.organization_id
               AND c.status = OLD.slug AND c.deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Há candidatos nesta etapa — mova-os antes de excluí-la';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS pipeline_etapa_protege ON public.pipeline_etapa;
CREATE TRIGGER pipeline_etapa_protege
  BEFORE UPDATE OR DELETE ON public.pipeline_etapa
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_pipeline_etapa_protege();

-- ── 3. RLS (padrão do catálogo RH-9) ─────────────────────────
ALTER TABLE public.pipeline_etapa ENABLE ROW LEVEL SECURITY;

-- Org inteira lê (o funil aparece para todo o RH); só admin RH escreve.
DROP POLICY IF EXISTS "Org lê etapas" ON public.pipeline_etapa;
CREATE POLICY "Org lê etapas" ON public.pipeline_etapa FOR SELECT
  USING (organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "Admin RH gerencia etapas" ON public.pipeline_etapa;
CREATE POLICY "Admin RH gerencia etapas" ON public.pipeline_etapa FOR ALL
  USING (public.fn_is_rh_admin() AND organization_id = public.fn_current_org())
  WITH CHECK (public.fn_is_rh_admin() AND organization_id = public.fn_current_org());

DROP TRIGGER IF EXISTS trg_force_org ON public.pipeline_etapa;
CREATE TRIGGER trg_force_org BEFORE INSERT ON public.pipeline_etapa
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org();

DROP POLICY IF EXISTS tenant_isolation ON public.pipeline_etapa;
CREATE POLICY tenant_isolation ON public.pipeline_etapa AS RESTRICTIVE FOR ALL
  USING (organization_id = public.fn_current_org())
  WITH CHECK (organization_id = public.fn_current_org());

DROP POLICY IF EXISTS module_entitlement ON public.pipeline_etapa;
CREATE POLICY module_entitlement ON public.pipeline_etapa AS RESTRICTIVE FOR ALL
  USING (public.fn_org_has_module('rh_banco_talentos'))
  WITH CHECK (public.fn_org_has_module('rh_banco_talentos'));

-- ── 4. Seed das orgs existentes (idempotente) ────────────────
-- Espelha exatamente o funil fixo atual — comportamento inalterado.
INSERT INTO public.pipeline_etapa (organization_id, slug, nome, ordem, role_cor, tipo)
SELECT o.id, e.slug, e.nome, e.ordem::smallint, e.role_cor, e.tipo
FROM public.organizations o
CROSS JOIN (VALUES
  ('novo',       'Novo',        1,  'info',      'entrada'),
  ('em_analise', 'Em análise',  2,  'warning',   'normal'),
  ('entrevista', 'Entrevista',  3,  'highlight', 'normal'),
  ('aprovado',   'Aprovado',    4,  'progress',  'normal'),
  ('contratado', 'Contratado',  5,  'success',   'contratado'),
  ('descartado', 'Descartado',  99, 'neutral',   'descartado')
) AS e(slug, nome, ordem, role_cor, tipo)
ON CONFLICT DO NOTHING;

-- Orgs criadas depois desta migration não são semeadas automaticamente:
-- o app cai no funil padrão e o admin RH semeia ao personalizar (RPC).
CREATE OR REPLACE FUNCTION public.rh_pipeline_seed_padrao()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_count integer := 0;
BEGIN
  IF NOT public.fn_is_rh_admin() THEN
    RAISE EXCEPTION 'Apenas administradores do RH podem configurar etapas';
  END IF;
  IF EXISTS (SELECT 1 FROM public.pipeline_etapa
             WHERE organization_id = v_org) THEN
    RETURN 0;  -- já semeado
  END IF;
  INSERT INTO public.pipeline_etapa
    (organization_id, slug, nome, ordem, role_cor, tipo, created_by)
  VALUES
    (v_org, 'novo',       'Novo',        1,  'info',      'entrada',    auth.uid()),
    (v_org, 'em_analise', 'Em análise',  2,  'warning',   'normal',     auth.uid()),
    (v_org, 'entrevista', 'Entrevista',  3,  'highlight', 'normal',     auth.uid()),
    (v_org, 'aprovado',   'Aprovado',    4,  'progress',  'normal',     auth.uid()),
    (v_org, 'contratado', 'Contratado',  5,  'success',   'contratado', auth.uid()),
    (v_org, 'descartado', 'Descartado',  99, 'neutral',   'descartado', auth.uid());
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_pipeline_seed_padrao() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_pipeline_seed_padrao() TO authenticated;

-- ── 5. candidato.status: enum → TEXT ─────────────────────────
-- O enum não comporta slugs de etapas novas. As views que dependem
-- da coluna precisam ser derrubadas e recriadas (definições idênticas).
DROP VIEW IF EXISTS public.candidato_contagem_status;
DROP VIEW IF EXISTS public.rh_metricas_divulgacao;
DROP VIEW IF EXISTS public.vaga_resumo;
DROP VIEW IF EXISTS public.rh_dash_tempo_pipeline;

ALTER TABLE public.candidato ALTER COLUMN status DROP DEFAULT;
ALTER TABLE public.candidato ALTER COLUMN status TYPE TEXT USING status::text;
ALTER TABLE public.candidato ALTER COLUMN status SET DEFAULT 'novo';

-- Recriação — candidato_contagem_status (rh1, S041)
CREATE OR REPLACE VIEW public.candidato_contagem_status
WITH (security_invoker = true) AS
SELECT organization_id, status, count(*) AS total
FROM public.candidato
WHERE deleted_at IS NULL
GROUP BY organization_id, status;

-- Recriação — rh_metricas_divulgacao (rh7)
CREATE OR REPLACE VIEW public.rh_metricas_divulgacao
WITH (security_invoker = true) AS
SELECT
  organization_id,
  count(*) FILTER (WHERE fonte = 'portal') AS portal_total,
  count(*) FILTER (WHERE fonte = 'portal'
                     AND created_at >= NOW() - interval '30 days') AS portal_30d,
  count(*) FILTER (WHERE fonte = 'portal'
                     AND status NOT IN ('novo', 'descartado')) AS portal_em_processo,
  count(*) FILTER (WHERE fonte = 'portal'
                     AND status = 'contratado') AS portal_contratados
FROM public.candidato
WHERE deleted_at IS NULL
GROUP BY organization_id;

-- Recriação — vaga_resumo (rh10)
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

-- ── 6. Guard de transição dirigido por dados ─────────────────
-- Mesmas regras de sempre, agora lidas de pipeline_etapa:
--   • contratado é imutável;
--   • descartado só reativa para a etapa de entrada;
--   • sem transição retroativa (ordem menor), exceto rumo a
--     descartado/contratado;
--   • etapa destino precisa existir na org.
-- Fallback: org sem etapas usa o mapa estático original.
-- Passa a rodar também no INSERT para validar o slug (o TEXT não
-- tem mais a proteção do enum) e carimbar status_changed_at.
CREATE OR REPLACE FUNCTION public.fn_candidato_status_guard()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_ordem CONSTANT JSONB :=
    '{"novo":1,"em_analise":2,"entrevista":3,"aprovado":4,"contratado":5}';
  v_tem_etapas BOOLEAN;
  v_old RECORD;
  v_new RECORD;
BEGIN
  SELECT EXISTS (SELECT 1 FROM public.pipeline_etapa e
                 WHERE e.organization_id = NEW.organization_id)
    INTO v_tem_etapas;

  IF TG_OP = 'INSERT' THEN
    IF v_tem_etapas THEN
      IF NOT EXISTS (SELECT 1 FROM public.pipeline_etapa e
                     WHERE e.organization_id = NEW.organization_id
                       AND e.slug = NEW.status) THEN
        RAISE EXCEPTION 'Etapa desconhecida: %', NEW.status;
      END IF;
    ELSIF NEW.status NOT IN ('novo','em_analise','entrevista',
                             'aprovado','contratado','descartado') THEN
      RAISE EXCEPTION 'Etapa desconhecida: %', NEW.status;
    END IF;
    IF NEW.status_changed_at IS NULL THEN
      NEW.status_changed_at := NOW();
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status IS DISTINCT FROM NEW.status THEN
    IF v_tem_etapas THEN
      SELECT e.tipo, e.ordem INTO v_old FROM public.pipeline_etapa e
        WHERE e.organization_id = NEW.organization_id AND e.slug = OLD.status;
      SELECT e.tipo, e.ordem INTO v_new FROM public.pipeline_etapa e
        WHERE e.organization_id = NEW.organization_id AND e.slug = NEW.status;
      IF v_new IS NULL THEN
        RAISE EXCEPTION 'Etapa desconhecida: %', NEW.status;
      END IF;
      IF v_old.tipo = 'contratado' THEN
        RAISE EXCEPTION 'Candidato contratado não pode mudar de status';
      ELSIF v_old.tipo = 'descartado' AND v_new.tipo <> 'entrada' THEN
        RAISE EXCEPTION 'Candidato descartado só pode ser reativado na etapa de entrada';
      ELSIF v_old IS NOT NULL AND v_old.tipo <> 'descartado'
        AND v_new.tipo NOT IN ('descartado','contratado')
        AND v_new.ordem < v_old.ordem THEN
        RAISE EXCEPTION 'Transição retroativa de status não permitida (% → %)',
          OLD.status, NEW.status;
      END IF;
    ELSE
      -- Fallback estático (orgs sem etapas configuradas)
      IF OLD.status = 'contratado' THEN
        RAISE EXCEPTION 'Candidato contratado não pode mudar de status';
      ELSIF OLD.status = 'descartado' AND NEW.status <> 'novo' THEN
        RAISE EXCEPTION 'Candidato descartado só pode ser reativado como novo';
      ELSIF NEW.status <> 'descartado' AND OLD.status <> 'descartado'
        AND (v_ordem->>NEW.status)::int < (v_ordem->>OLD.status)::int THEN
        RAISE EXCEPTION 'Transição retroativa de status não permitida (% → %)',
          OLD.status, NEW.status;
      END IF;
    END IF;

    NEW.status_changed_at := NOW();  -- SLA: reinicia o relógio da etapa
    INSERT INTO public.candidato_historico (candidato_id, acao, detalhes, usuario_id)
    VALUES (NEW.id, 'mudanca_status',
            jsonb_build_object('de', OLD.status, 'para', NEW.status),
            auth.uid());
  END IF;
  RETURN NEW;
END;
$$;

-- O trigger passa a cobrir INSERT também (validação de slug + carimbo)
DROP TRIGGER IF EXISTS candidato_status_guard ON public.candidato;
CREATE TRIGGER candidato_status_guard
  BEFORE INSERT OR UPDATE ON public.candidato
  FOR EACH ROW EXECUTE FUNCTION public.fn_candidato_status_guard();
