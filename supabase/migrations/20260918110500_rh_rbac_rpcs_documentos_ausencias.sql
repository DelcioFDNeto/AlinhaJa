-- =============================================================
-- RH passa a obedecer o RBAC (6/7): RPCs — documentos e ausencias
-- =============================================================
-- Gerado a partir da ÚLTIMA definição de cada objeto nas migrations
-- (indicada em cada bloco). Só a checagem de acesso muda:
-- fn_is_rh()/fn_is_rh_admin() → fn_rh_pode(<módulo>, <ação>).
-- Ver 20260918110000_rh_rbac_helpers.sql.
-- =============================================================

-- rh_rejeitar_documento ← 20260710110000_rh6_alertas_integracao_rejeicao.sql
CREATE OR REPLACE FUNCTION public.rh_rejeitar_documento(
  p_documento_id uuid, p_motivo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT public.fn_rh_pode('rh_documentos', 'manage') THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;
  IF COALESCE(trim(p_motivo), '') = '' THEN
    RAISE EXCEPTION 'Informe o motivo da rejeição';
  END IF;
  UPDATE public.rh_documento
     SET status = 'rejeitado', motivo_rejeicao = p_motivo, updated_at = NOW()
   WHERE id = p_documento_id
     AND organization_id = public.fn_current_org()
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Documento não encontrado';
  END IF;
END;
$$;

-- rh_set_exige_aceite ← 20260731110000_rh24_documento_aceite.sql
CREATE OR REPLACE FUNCTION public.rh_set_exige_aceite(
  p_documento_id uuid,
  p_exige        boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_rh_pode('rh_documentos', 'manage') THEN
    RAISE EXCEPTION 'Apenas o RH pode exigir aceite de documentos';
  END IF;

  UPDATE public.rh_documento
     SET exige_aceite = p_exige
   WHERE id = p_documento_id
     AND organization_id = v_org
     AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Documento não encontrado';
  END IF;

  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_org, auth.uid(), 'alterou_exigencia_aceite',
          jsonb_build_object('documento_id', p_documento_id, 'exige', p_exige));
END;
$$;

-- rh_marcar_alerta_lido ← 20260709120000_rh5_onboarding.sql
CREATE OR REPLACE FUNCTION public.rh_marcar_alerta_lido(p_alerta_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_rh_pode('rh_alertas', 'view') THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;
  UPDATE public.rh_alerta
  SET lido = true, lido_por = auth.uid(), lido_em = NOW()
  WHERE id = p_alerta_id AND organization_id = v_org;
END;
$$;

-- rh_abrir_periodo_aquisitivo ← 20260801110000_rh26_ferias_saldo.sql
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
  IF NOT public.fn_rh_pode('rh_ausencias', 'manage') THEN
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

-- rh_decidir_ausencia ← 20260801110000_rh26_ferias_saldo.sql
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
  IF NOT public.fn_rh_pode('rh_ausencias', 'manage') THEN
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

-- rh_set_dias_abonados ← 20260801110000_rh26_ferias_saldo.sql
CREATE OR REPLACE FUNCTION public.rh_set_dias_abonados(
  p_periodo_id uuid,
  p_dias       smallint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_saldo record;
BEGIN
  IF NOT public.fn_rh_pode('rh_ausencias', 'manage') THEN
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

