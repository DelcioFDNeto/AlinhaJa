-- =============================================================
-- RH passa a obedecer o RBAC (3/7): RPCs — talentos
-- =============================================================
-- Gerado a partir da ÚLTIMA definição de cada objeto nas migrations
-- (indicada em cada bloco). Só a checagem de acesso muda:
-- fn_is_rh()/fn_is_rh_admin() → fn_rh_pode(<módulo>, <ação>).
-- Ver 20260918110000_rh_rbac_helpers.sql.
-- =============================================================

-- retry_cv_extraction ← 20260710174700_retry_cv_extraction.sql
CREATE OR REPLACE FUNCTION public.retry_cv_extraction(p_curriculo_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_base text := public.get_edge_base_url();
  v_curriculo record;
BEGIN
  -- Segurança: garantir que só RH da mesma org possa rodar
  IF NOT public.fn_rh_pode('rh_banco_talentos', 'manage') THEN
    RAISE EXCEPTION 'Acesso negado: apenas administradores de RH podem reprocessar currículos.';
  END IF;

  SELECT * INTO v_curriculo FROM public.candidato_curriculo WHERE id = p_curriculo_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Currículo não encontrado';
  END IF;

  -- Resetar status no candidato para dar feedback visual imediato
  UPDATE public.candidato 
  SET extracao = 'processando' 
  WHERE id = v_curriculo.candidato_id AND organization_id = public.fn_current_org();

  IF v_base = '' THEN
    RAISE WARNING 'edge_base_url não configurada no Vault';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_base || '/functions/v1/rh-extract-cv',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.get_webhook_secret()
    ),
    body := jsonb_build_object(
      'type', 'MANUAL_RETRY',
      'table', 'candidato_curriculo',
      'record', row_to_json(v_curriculo),
      'attempt', 1
    )
  );
END;
$$;

-- rh_anonimizar_candidato ← 20260710100000_rh_lgpd_retencao_esquecimento.sql
CREATE OR REPLACE FUNCTION public.rh_anonimizar_candidato(p_candidato_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT public.fn_rh_pode('rh_banco_talentos', 'manage') THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.candidato
                 WHERE id = p_candidato_id
                   AND organization_id = public.fn_current_org()) THEN
    RAISE EXCEPTION 'Candidato não encontrado';
  END IF;
  PERFORM public.fn_anonimizar_candidato(p_candidato_id, 'solicitacao_titular');
END;
$$;

-- rh_atribuir_responsavel ← 20260718100000_rh13_pipeline_avancado.sql
CREATE OR REPLACE FUNCTION public.rh_atribuir_responsavel(
  p_ids uuid[], p_responsavel uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_count integer;
BEGIN
  IF NOT public.fn_rh_pode('rh_banco_talentos', 'manage') THEN
    RAISE EXCEPTION 'Apenas o RH pode atribuir responsáveis';
  END IF;
  -- Responsável (quando informado) precisa ser da mesma org.
  IF p_responsavel IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = p_responsavel AND u.organization_id = v_org) THEN
    RAISE EXCEPTION 'Responsável não pertence à organização';
  END IF;

  UPDATE public.candidato
     SET responsavel_id = p_responsavel, updated_by = auth.uid()
   WHERE id = ANY(p_ids)
     AND organization_id = v_org
     AND deleted_at IS NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- rh_converter_candidato ← 20260709120000_rh5_onboarding.sql
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
  IF NOT (public.fn_rh_pode('rh_banco_talentos', 'manage') AND public.fn_rh_pode('rh_funcionarios', 'manage')) THEN
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

-- rh_get_avaliacao_config ← 20260731100000_rh23_avaliacao_timer.sql
CREATE OR REPLACE FUNCTION public.rh_get_avaliacao_config()
RETURNS TABLE (qtd integer, minutos integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_rh_pode('rh_banco_talentos', 'view') THEN
    RAISE EXCEPTION 'Sem permissão para ler a configuração da avaliação';
  END IF;

  RETURN QUERY
  SELECT
    COALESCE((o.settings ->> 'avaliacao_qtd')::int, 5),
    COALESCE((o.settings ->> 'avaliacao_minutos')::int, 0)
  FROM public.organizations o
  WHERE o.id = v_org;
END;
$$;

-- rh_pipeline_seed_padrao ← 20260719100000_rh14_pipeline_etapas.sql
CREATE OR REPLACE FUNCTION public.rh_pipeline_seed_padrao()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_count integer := 0;
BEGIN
  IF NOT public.fn_rh_pode('rh_banco_talentos', 'manage') THEN
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

-- rh_set_avaliacao_config ← 20260731100000_rh23_avaliacao_timer.sql
CREATE OR REPLACE FUNCTION public.rh_set_avaliacao_config(
  p_qtd     integer DEFAULT NULL,
  p_minutos integer DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_rh_pode('rh_banco_talentos', 'manage') THEN
    RAISE EXCEPTION 'Apenas administradores do RH podem configurar a avaliação';
  END IF;

  IF p_qtd IS NOT NULL AND p_qtd NOT BETWEEN 1 AND 15 THEN
    RAISE EXCEPTION 'A quantidade de questões deve ficar entre 1 e 15';
  END IF;
  IF p_minutos IS NOT NULL AND p_minutos NOT BETWEEN 0 AND 180 THEN
    RAISE EXCEPTION 'O tempo da prova deve ficar entre 0 (sem limite) e 180 minutos';
  END IF;

  IF p_qtd IS NOT NULL THEN
    UPDATE public.organizations
       SET settings = jsonb_set(COALESCE(settings, '{}'::jsonb),
                                '{avaliacao_qtd}', to_jsonb(p_qtd), true)
     WHERE id = v_org;
  END IF;

  IF p_minutos IS NOT NULL THEN
    UPDATE public.organizations
       SET settings = jsonb_set(COALESCE(settings, '{}'::jsonb),
                                '{avaliacao_minutos}', to_jsonb(p_minutos), true)
     WHERE id = v_org;
  END IF;

  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_org, auth.uid(), 'editou_avaliacao_config',
          jsonb_build_object('qtd', p_qtd, 'minutos', p_minutos));
END;
$$;

-- rh_set_carreiras_config ← 20260714100001_rh7_central_divulgacao.sql
CREATE OR REPLACE FUNCTION public.rh_set_carreiras_config(
  p_ativo boolean DEFAULT NULL,
  p_headline text DEFAULT NULL,
  p_sobre text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_rh_pode('rh_banco_talentos', 'manage') THEN
    RAISE EXCEPTION 'Apenas administradores do RH podem alterar a divulgação';
  END IF;

  UPDATE public.organizations SET
    carreiras_ativo    = COALESCE(p_ativo, carreiras_ativo),
    carreiras_headline = CASE WHEN p_headline IS NULL THEN carreiras_headline
                              ELSE NULLIF(trim(p_headline), '') END,
    carreiras_sobre    = CASE WHEN p_sobre IS NULL THEN carreiras_sobre
                              ELSE NULLIF(trim(p_sobre), '') END,
    updated_at = NOW()
  WHERE id = v_org;

  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_org, auth.uid(), 'editou_carreiras_config',
          jsonb_build_object('ativo', p_ativo,
                             'headline_alterada', p_headline IS NOT NULL,
                             'sobre_alterado', p_sobre IS NOT NULL));
END;
$$;

-- rh_soft_delete_candidato ← 20260918100000_rh_rbac_auditoria.sql
CREATE OR REPLACE FUNCTION public.rh_soft_delete_candidato(p_candidato_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_rh_pode('rh_banco_talentos', 'manage') THEN
    RAISE EXCEPTION 'Apenas o RH pode excluir candidatos.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.candidato
     SET deleted_at = now(),
         deleted_by = auth.uid()
   WHERE id = p_candidato_id
     AND organization_id = public.fn_current_org()
     AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidato não encontrado.';
  END IF;
END;
$$;

