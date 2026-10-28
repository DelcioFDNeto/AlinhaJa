-- =============================================================
-- RH passa a obedecer o RBAC (5/7): RPCs — onboarding
-- =============================================================
-- Gerado a partir da ÚLTIMA definição de cada objeto nas migrations
-- (indicada em cada bloco). Só a checagem de acesso muda:
-- fn_is_rh()/fn_is_rh_admin() → fn_rh_pode(<módulo>, <ação>).
-- Ver 20260918110000_rh_rbac_helpers.sql.
-- =============================================================

-- rh_anexar_documento_onboarding ← 20260710110000_rh6_alertas_integracao_rejeicao.sql
CREATE OR REPLACE FUNCTION public.rh_anexar_documento_onboarding(
  p_item_id uuid,
  p_storage_path text,
  p_titulo text,
  p_categoria public.rh_documento_categoria DEFAULT 'outro',
  p_data_vencimento date DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_func uuid;
  v_doc uuid;
BEGIN
  IF NOT public.fn_rh_pode('rh_onboarding', 'manage') THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;

  SELECT funcionario_id INTO v_func
  FROM public.onboarding_item
  WHERE id = p_item_id AND organization_id = v_org;
  IF v_func IS NULL THEN
    RAISE EXCEPTION 'Item de onboarding não encontrado';
  END IF;

  INSERT INTO public.rh_documento
    (organization_id, funcionario_id, titulo, categoria, storage_path,
     data_vencimento, status, created_by)
  VALUES (v_org, v_func, p_titulo, p_categoria, p_storage_path,
          p_data_vencimento, 'valido', auth.uid())
  RETURNING id INTO v_doc;

  UPDATE public.onboarding_item
     SET documento_id = v_doc,
         status = 'concluido',
         concluido_em = NOW(),
         concluido_por = auth.uid()
   WHERE id = p_item_id;

  RETURN v_doc;
END;
$$;

-- rh_atualizar_item_onboarding ← 20260709120000_rh5_onboarding.sql
CREATE OR REPLACE FUNCTION public.rh_atualizar_item_onboarding(
  p_item_id uuid, p_status public.onboarding_item_status,
  p_observacao text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_rh_pode('rh_onboarding', 'manage') THEN
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

-- rh_concluir_onboarding ← 20260709120000_rh5_onboarding.sql
CREATE OR REPLACE FUNCTION public.rh_concluir_onboarding(p_execucao_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_pendentes int;
  v_func uuid;
BEGIN
  IF NOT public.fn_rh_pode('rh_onboarding', 'manage') THEN
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

-- rh_decidir_experiencia ← 20260709120000_rh5_onboarding.sql
CREATE OR REPLACE FUNCTION public.rh_decidir_experiencia(
  p_periodo_id uuid, p_decisao text, p_observacao text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_p public.periodo_experiencia%ROWTYPE;
BEGIN
  -- Decisão de experiência exige RH admin
  IF NOT public.fn_rh_pode('rh_onboarding', 'manage') THEN
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

-- rh_iniciar_experiencia ← 20260709120000_rh5_onboarding.sql
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
  IF NOT public.fn_rh_pode('rh_onboarding', 'manage') THEN
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

-- rh_iniciar_onboarding ← 20260709120000_rh5_onboarding.sql
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
  IF NOT public.fn_rh_pode('rh_onboarding', 'manage') THEN
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

