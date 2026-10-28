-- ============================================================
-- RH-26 / Fase 8 — Saldo de férias (período aquisitivo) e calendário
-- (PLANO-RH-COMPLETO.md, seção 11: "Ausências/Férias: solicitação e
-- aprovação (workflow), saldo, calendário").
--
-- O workflow de solicitar/aprovar já existia (rh17). Faltava o saldo:
-- sem ele o RH aprova férias sem saber quantos dias a pessoa tem.
--
-- Modelo (CLT simplificada):
--   • rh_periodo_aquisitivo — 12 meses trabalhados dão 30 dias de
--     direito. Um funcionário pode ter mais de um período em aberto.
--   • rh_ausencia.periodo_aquisitivo_id — amarra a férias ao período
--     que ela consome. Ausência que não é férias fica NULL.
--   • rh_ferias_saldo (view) — direito − abonado − gozado − reservado.
--     "Reservado" = solicitação pendente: o dia ainda não foi gozado,
--     mas não pode ser prometido duas vezes.
--
-- Aprovação passa a ser RPC: aprovar férias sem saldo era possível e
-- agora é bloqueado no servidor.
--
-- Migration aditiva. Ausências antigas ficam com período NULL e
-- seguem funcionando (contam como gozo avulso, fora do controle).
-- ============================================================

-- ── 1. Período aquisitivo ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rh_periodo_aquisitivo (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  funcionario_id  UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  inicio          DATE NOT NULL,
  fim             DATE NOT NULL,
  -- Limite para gozar (concessivo): 12 meses após o fim do aquisitivo.
  limite_gozo     DATE NOT NULL,
  dias_direito    SMALLINT NOT NULL DEFAULT 30 CHECK (dias_direito BETWEEN 0 AND 30),
  -- Abono pecuniário ("venda"): até 1/3 do direito.
  dias_abonados   SMALLINT NOT NULL DEFAULT 0 CHECK (dias_abonados >= 0),
  status          TEXT NOT NULL DEFAULT 'aberto'
                    CHECK (status IN ('aberto', 'encerrado')),
  observacao      TEXT,
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_periodo_datas CHECK (fim > inicio AND limite_gozo > fim),
  CONSTRAINT chk_abono_ate_um_terco CHECK (dias_abonados * 3 <= dias_direito)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_periodo_aquisitivo_func_inicio
  ON public.rh_periodo_aquisitivo(funcionario_id, inicio);
CREATE INDEX IF NOT EXISTS idx_periodo_aquisitivo_org_func
  ON public.rh_periodo_aquisitivo(organization_id, funcionario_id, status);

DROP TRIGGER IF EXISTS set_rh_periodo_aquisitivo_updated_at ON public.rh_periodo_aquisitivo;
CREATE TRIGGER set_rh_periodo_aquisitivo_updated_at
  BEFORE UPDATE ON public.rh_periodo_aquisitivo
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 2. Vínculo da ausência com o período ─────────────────────
ALTER TABLE public.rh_ausencia
  ADD COLUMN IF NOT EXISTS periodo_aquisitivo_id UUID
    REFERENCES public.rh_periodo_aquisitivo(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_rh_ausencia_periodo
  ON public.rh_ausencia(periodo_aquisitivo_id)
  WHERE periodo_aquisitivo_id IS NOT NULL;

COMMENT ON COLUMN public.rh_ausencia.periodo_aquisitivo_id IS
  'Período aquisitivo consumido por estas férias. NULL para outros tipos.';

-- ── 3. RLS ───────────────────────────────────────────────────
ALTER TABLE public.rh_periodo_aquisitivo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "RH gerencia períodos aquisitivos" ON public.rh_periodo_aquisitivo;
CREATE POLICY "RH gerencia períodos aquisitivos"
  ON public.rh_periodo_aquisitivo FOR ALL
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org())
  WITH CHECK (public.fn_is_rh() AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "Funcionário lê próprios períodos" ON public.rh_periodo_aquisitivo;
CREATE POLICY "Funcionário lê próprios períodos"
  ON public.rh_periodo_aquisitivo FOR SELECT
  USING (public.fn_is_own_funcionario(funcionario_id));

DROP POLICY IF EXISTS tenant_isolation ON public.rh_periodo_aquisitivo;
CREATE POLICY tenant_isolation ON public.rh_periodo_aquisitivo AS RESTRICTIVE FOR ALL
  USING (organization_id = public.fn_current_org())
  WITH CHECK (organization_id = public.fn_current_org());

DROP POLICY IF EXISTS module_entitlement ON public.rh_periodo_aquisitivo;
CREATE POLICY module_entitlement ON public.rh_periodo_aquisitivo AS RESTRICTIVE FOR ALL
  USING (public.fn_org_has_module('rh_ausencias'))
  WITH CHECK (public.fn_org_has_module('rh_ausencias'));

DROP TRIGGER IF EXISTS trg_force_org ON public.rh_periodo_aquisitivo;
CREATE TRIGGER trg_force_org BEFORE INSERT ON public.rh_periodo_aquisitivo
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org();

-- ── 4. Saldo por período ─────────────────────────────────────
-- Dias contados de ponta a ponta (corridos), que é como a CLT conta
-- férias. security_invoker: RH vê a org, funcionário vê o que é dele.
CREATE OR REPLACE VIEW public.rh_ferias_saldo
WITH (security_invoker = true) AS
SELECT
  p.id                AS periodo_id,
  p.organization_id,
  p.funcionario_id,
  f.nome              AS funcionario_nome,
  p.inicio,
  p.fim,
  p.limite_gozo,
  p.status,
  p.dias_direito,
  p.dias_abonados,
  COALESCE(g.dias_gozados, 0)    AS dias_gozados,
  COALESCE(r.dias_reservados, 0) AS dias_reservados,
  GREATEST(
    p.dias_direito - p.dias_abonados
      - COALESCE(g.dias_gozados, 0) - COALESCE(r.dias_reservados, 0),
    0
  )                   AS dias_disponiveis,
  (p.limite_gozo < CURRENT_DATE) AS vencido
FROM public.rh_periodo_aquisitivo p
JOIN public.funcionario f ON f.id = p.funcionario_id
LEFT JOIN LATERAL (
  SELECT sum(a.data_fim - a.data_inicio + 1) AS dias_gozados
  FROM public.rh_ausencia a
  WHERE a.periodo_aquisitivo_id = p.id
    AND a.tipo = 'ferias' AND a.status = 'aprovado'
) g ON true
LEFT JOIN LATERAL (
  SELECT sum(a.data_fim - a.data_inicio + 1) AS dias_reservados
  FROM public.rh_ausencia a
  WHERE a.periodo_aquisitivo_id = p.id
    AND a.tipo = 'ferias' AND a.status = 'pendente'
) r ON true;

COMMENT ON VIEW public.rh_ferias_saldo IS
  'Saldo por período aquisitivo: direito − abonado − gozado − reservado (pendente).';

-- ── 5. RH abre um período aquisitivo ─────────────────────────
-- Sem p_inicio, encadeia a partir do último período (ou da admissão).
CREATE OR REPLACE FUNCTION public.rh_abrir_periodo_aquisitivo(
  p_funcionario_id uuid,
  p_inicio         date DEFAULT NULL,
  p_dias_direito   smallint DEFAULT 30)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org    uuid := public.fn_current_org();
  v_inicio date := p_inicio;
  v_fim    date;
  v_id     uuid;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Apenas o RH pode abrir períodos aquisitivos';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.funcionario
                  WHERE id = p_funcionario_id AND organization_id = v_org
                    AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Funcionário não encontrado';
  END IF;

  IF v_inicio IS NULL THEN
    -- Dia seguinte ao fim do último período; se não houver, a admissão.
    SELECT fim + 1 INTO v_inicio
      FROM public.rh_periodo_aquisitivo
     WHERE funcionario_id = p_funcionario_id
     ORDER BY fim DESC LIMIT 1;
  END IF;
  IF v_inicio IS NULL THEN
    SELECT data_admissao INTO v_inicio
      FROM public.vinculo
     WHERE funcionario_id = p_funcionario_id AND data_desligamento IS NULL
     ORDER BY data_admissao DESC LIMIT 1;
  END IF;
  IF v_inicio IS NULL THEN
    RAISE EXCEPTION 'Sem vínculo ativo: informe a data de início do período';
  END IF;

  v_fim := (v_inicio + INTERVAL '1 year - 1 day')::date;

  INSERT INTO public.rh_periodo_aquisitivo
    (organization_id, funcionario_id, inicio, fim, limite_gozo,
     dias_direito, created_by)
  VALUES
    (v_org, p_funcionario_id, v_inicio, v_fim,
     (v_fim + INTERVAL '1 year')::date, COALESCE(p_dias_direito, 30), auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_org, auth.uid(), 'abriu_periodo_aquisitivo',
          jsonb_build_object('funcionario_id', p_funcionario_id,
                             'inicio', v_inicio, 'fim', v_fim));
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_abrir_periodo_aquisitivo(uuid, date, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_abrir_periodo_aquisitivo(uuid, date, smallint) TO authenticated;

-- ── 6. Abono pecuniário (venda de dias) ──────────────────────
CREATE OR REPLACE FUNCTION public.rh_set_dias_abonados(
  p_periodo_id uuid,
  p_dias       smallint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_saldo record;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Apenas o RH pode registrar abono de férias';
  END IF;
  IF p_dias < 0 THEN
    RAISE EXCEPTION 'O abono não pode ser negativo';
  END IF;

  -- Filtro por organização é obrigatório: esta função é SECURITY DEFINER,
  -- então a RLS não filtra e o id vem do cliente.
  SELECT s.* INTO v_saldo
    FROM public.rh_ferias_saldo s
   WHERE s.periodo_id = p_periodo_id AND s.organization_id = v_org;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Período não encontrado';
  END IF;

  -- Teto legal: até 1/3 do direito pode virar abono pecuniário.
  IF p_dias * 3 > v_saldo.dias_direito THEN
    RAISE EXCEPTION 'O abono é limitado a 1/3 do direito (máximo % dias)',
      v_saldo.dias_direito / 3;
  END IF;
  -- O abono não pode invadir dias já gozados ou reservados.
  IF p_dias > v_saldo.dias_direito - v_saldo.dias_gozados - v_saldo.dias_reservados THEN
    RAISE EXCEPTION 'Abono de % dia(s) excede o saldo livre do período', p_dias;
  END IF;

  UPDATE public.rh_periodo_aquisitivo
     SET dias_abonados = p_dias
   WHERE id = p_periodo_id AND organization_id = v_org;

  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_org, auth.uid(), 'registrou_abono_ferias',
          jsonb_build_object('periodo_id', p_periodo_id, 'dias', p_dias));
END;
$$;
REVOKE ALL ON FUNCTION public.rh_set_dias_abonados(uuid, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_set_dias_abonados(uuid, smallint) TO authenticated;

-- ── 7. Aprovação com validação de saldo ──────────────────────
-- Antes o app dava UPDATE direto em rh_ausencia. Agora a decisão passa
-- por aqui: férias só são aprovadas se houver saldo no período.
CREATE OR REPLACE FUNCTION public.rh_decidir_ausencia(
  p_ausencia_id uuid,
  p_aprovar     boolean,
  p_periodo_id  uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org      uuid := public.fn_current_org();
  v_aus      public.rh_ausencia%ROWTYPE;
  v_periodo  uuid;
  v_dias     int;
  v_saldo    record;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Apenas o RH pode decidir solicitações de ausência';
  END IF;

  SELECT * INTO v_aus FROM public.rh_ausencia
   WHERE id = p_ausencia_id AND organization_id = v_org;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitação não encontrada';
  END IF;
  IF v_aus.status <> 'pendente' THEN
    RAISE EXCEPTION 'Esta solicitação já foi decidida';
  END IF;

  IF NOT p_aprovar THEN
    UPDATE public.rh_ausencia
       SET status = 'rejeitado', aprovador_id = auth.uid()
     WHERE id = p_ausencia_id;
    RETURN;
  END IF;

  IF v_aus.tipo = 'ferias' THEN
    v_periodo := COALESCE(p_periodo_id, v_aus.periodo_aquisitivo_id);
    -- Sem período informado, usa o mais antigo em aberto (vence antes).
    IF v_periodo IS NULL THEN
      SELECT s.periodo_id INTO v_periodo
        FROM public.rh_ferias_saldo s
       WHERE s.funcionario_id = v_aus.funcionario_id
         AND s.organization_id = v_org
         AND s.status = 'aberto' AND s.dias_disponiveis > 0
       ORDER BY s.limite_gozo LIMIT 1;
    END IF;
    IF v_periodo IS NULL THEN
      RAISE EXCEPTION 'Nenhum período aquisitivo com saldo para este funcionário';
    END IF;

    v_dias := v_aus.data_fim - v_aus.data_inicio + 1;

    -- p_periodo_id vem do cliente e esta função é SECURITY DEFINER: sem
    -- amarrar org + funcionário, daria para debitar férias no período de
    -- outra pessoa (ou de outra empresa).
    SELECT s.* INTO v_saldo
      FROM public.rh_ferias_saldo s
     WHERE s.periodo_id = v_periodo
       AND s.organization_id = v_org
       AND s.funcionario_id = v_aus.funcionario_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Período aquisitivo inválido para este funcionário';
    END IF;

    -- A própria solicitação já está em "reservados": some de volta para
    -- não descontar duas vezes na comparação.
    IF v_dias > v_saldo.dias_disponiveis
       + (CASE WHEN v_aus.periodo_aquisitivo_id = v_periodo THEN v_dias ELSE 0 END) THEN
      RAISE EXCEPTION 'Saldo insuficiente: % dia(s) disponível(is) no período, % solicitado(s)',
        v_saldo.dias_disponiveis, v_dias;
    END IF;

    UPDATE public.rh_ausencia
       SET status = 'aprovado',
           aprovador_id = auth.uid(),
           periodo_aquisitivo_id = v_periodo
     WHERE id = p_ausencia_id;
  ELSE
    UPDATE public.rh_ausencia
       SET status = 'aprovado', aprovador_id = auth.uid()
     WHERE id = p_ausencia_id;
  END IF;

  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_org, auth.uid(), 'decidiu_ausencia',
          jsonb_build_object('ausencia_id', p_ausencia_id, 'aprovado', p_aprovar,
                             'periodo_id', v_periodo));
END;
$$;
REVOKE ALL ON FUNCTION public.rh_decidir_ausencia(uuid, boolean, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_decidir_ausencia(uuid, boolean, uuid) TO authenticated;

-- ── 8. Calendário de ausências ───────────────────────────────
-- Uma linha por ausência que toca a janela pedida. A RLS de rh_ausencia
-- (RH vê a org, funcionário vê as próprias) continua valendo.
CREATE OR REPLACE VIEW public.rh_ausencia_calendario
WITH (security_invoker = true) AS
SELECT
  a.id,
  a.organization_id,
  a.funcionario_id,
  f.nome AS funcionario_nome,
  a.tipo,
  a.status,
  a.data_inicio,
  a.data_fim,
  (a.data_fim - a.data_inicio + 1) AS dias
FROM public.rh_ausencia a
JOIN public.funcionario f ON f.id = a.funcionario_id
WHERE a.status IN ('pendente', 'aprovado');

COMMENT ON VIEW public.rh_ausencia_calendario IS
  'Ausências pendentes/aprovadas com nome do funcionário, para a visão de calendário.';
