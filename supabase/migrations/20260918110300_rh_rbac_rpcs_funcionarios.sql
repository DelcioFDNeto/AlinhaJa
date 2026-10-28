-- =============================================================
-- RH passa a obedecer o RBAC (4/7): RPCs — funcionarios
-- =============================================================
-- Gerado a partir da ÚLTIMA definição de cada objeto nas migrations
-- (indicada em cada bloco). Só a checagem de acesso muda:
-- fn_is_rh()/fn_is_rh_admin() → fn_rh_pode(<módulo>, <ação>).
-- Ver 20260918110000_rh_rbac_helpers.sql.
-- =============================================================

-- rh_add_dependente ← 20260727100000_rh22_consolidacao_fases789.sql
CREATE OR REPLACE FUNCTION public.rh_add_dependente(
  p_funcionario_id uuid,
  p_nome text,
  p_data_nascimento date,
  p_parentesco text,
  p_cpf text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_id uuid;
BEGIN
  IF NOT public.fn_rh_pode('rh_funcionarios', 'manage') THEN
    RAISE EXCEPTION 'Apenas o RH pode registrar dependentes';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.funcionario f
    WHERE f.id = p_funcionario_id
      AND f.organization_id = v_org AND f.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Funcionário não encontrado nesta organização';
  END IF;

  INSERT INTO public.rh_dependente
    (organization_id, funcionario_id, nome, data_nascimento, parentesco,
     cpf_encrypted)
  VALUES
    (v_org, p_funcionario_id, trim(p_nome), p_data_nascimento, trim(p_parentesco),
     public.fn_rh_encrypt(nullif(trim(coalesce(p_cpf, '')), ''), v_org))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- rh_add_historico_cargo_salario ← 20260727100000_rh22_consolidacao_fases789.sql
CREATE OR REPLACE FUNCTION public.rh_add_historico_cargo_salario(
  p_funcionario_id uuid,
  p_salario text,
  p_data_inicio date,
  p_motivo text,
  p_cargo_id text DEFAULT NULL,
  p_departamento_id text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_id uuid;
BEGIN
  IF NOT public.fn_rh_pode('rh_funcionarios', 'manage') THEN
    RAISE EXCEPTION 'Apenas o RH pode registrar histórico salarial';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.funcionario f
    WHERE f.id = p_funcionario_id
      AND f.organization_id = v_org AND f.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Funcionário não encontrado nesta organização';
  END IF;
  IF coalesce(trim(p_motivo), '') = '' THEN
    RAISE EXCEPTION 'Informe o motivo do registro';
  END IF;

  INSERT INTO public.rh_historico_cargo_salario
    (organization_id, funcionario_id, cargo_id, departamento_id,
     salario_encrypted, data_inicio, motivo, created_by)
  VALUES
    (v_org, p_funcionario_id, nullif(p_cargo_id, ''), nullif(p_departamento_id, ''),
     public.fn_rh_encrypt(p_salario, v_org), p_data_inicio, trim(p_motivo), auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.rh_access_log
    (organization_id, funcionario_id, usuario_id, acao)
  VALUES (v_org, p_funcionario_id, auth.uid(), 'registrou_historico_salarial');

  RETURN v_id;
END;
$$;

-- rh_dash_aniversariantes ← 20260720100000_rh15_dashboard_fase6_completa.sql
CREATE OR REPLACE FUNCTION public.rh_dash_aniversariantes(p_mes int DEFAULT NULL)
RETURNS TABLE (funcionario_id uuid, nome text, foto_url text, dia smallint)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_mes int  := COALESCE(p_mes, extract(month FROM CURRENT_DATE)::int);
BEGIN
  IF NOT public.fn_rh_pode('rh_funcionarios', 'view') THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;
  IF v_mes NOT BETWEEN 1 AND 12 THEN
    RAISE EXCEPTION 'Mês inválido: %', v_mes;
  END IF;

  RETURN QUERY
  SELECT f.id, f.nome, f.foto_url,
         extract(day FROM ds.data_nascimento)::smallint
  FROM public.funcionario f
  JOIN public.funcionario_dados_sensiveis ds ON ds.funcionario_id = f.id
  WHERE f.organization_id = v_org
    AND f.deleted_at IS NULL
    AND f.status <> 'desligado'
    AND ds.data_nascimento IS NOT NULL
    AND extract(month FROM ds.data_nascimento)::int = v_mes
  ORDER BY 4, 2;
END;
$$;

-- rh_desvincular_usuario ← 20260714110000_rh8_vinculo_usuario.sql
CREATE OR REPLACE FUNCTION public.rh_desvincular_usuario(p_funcionario_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_atual uuid;
BEGIN
  IF NOT public.fn_rh_pode('rh_funcionarios', 'manage') THEN
    RAISE EXCEPTION 'Apenas administradores do RH podem desvincular usuários';
  END IF;

  SELECT f.user_id INTO v_atual
  FROM public.funcionario f
  WHERE f.id = p_funcionario_id
    AND f.organization_id = v_org
    AND f.deleted_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado';
  END IF;
  IF v_atual IS NULL THEN
    RETURN; -- já está desvinculado, nada a fazer
  END IF;

  UPDATE public.funcionario
     SET user_id = NULL, updated_by = auth.uid()
   WHERE id = p_funcionario_id;

  INSERT INTO public.rh_access_log
    (organization_id, funcionario_id, usuario_id, acao, detalhes)
  VALUES (v_org, p_funcionario_id, auth.uid(), 'desvinculou_usuario',
          jsonb_build_object('user_id', v_atual));
END;
$$;

-- rh_get_dados_sensiveis ← 20260803220000_rh_sensitive_encryption.sql
CREATE OR REPLACE FUNCTION public.rh_get_dados_sensiveis(p_funcionario_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_row public.funcionario_dados_sensiveis%ROWTYPE;
  v_salario text;
  v_endereco text;
BEGIN
  IF NOT public.fn_rh_pode('rh_funcionarios', 'manage') THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;

  SELECT ds.* INTO v_row
  FROM public.funcionario_dados_sensiveis ds
  WHERE ds.funcionario_id = p_funcionario_id
    AND ds.organization_id = v_org;

  -- Auditoria obrigatória (S008): quem viu a ficha completa
  INSERT INTO public.rh_access_log
    (organization_id, funcionario_id, usuario_id, acao)
  VALUES (v_org, p_funcionario_id, auth.uid(), 'visualizou_dados_sensiveis');

  IF v_row.funcionario_id IS NULL THEN
    RETURN jsonb_build_object('exists', false);
  END IF;

  SELECT public.fn_rh_decrypt(vv.salario_encrypted, v_org) INTO v_salario
  FROM public.vinculo vv
  WHERE vv.funcionario_id = p_funcionario_id
  ORDER BY vv.created_at DESC LIMIT 1;

  v_endereco := public.fn_rh_decrypt(v_row.endereco_encrypted, v_org);

  RETURN jsonb_build_object(
    'exists', true,
    'cpf', public.fn_rh_decrypt(v_row.cpf_encrypted, v_org),
    'rg', public.fn_rh_decrypt(v_row.rg_encrypted, v_org),
    'data_nascimento', v_row.data_nascimento,
    'email_pessoal', v_row.email_pessoal,
    'telefone', v_row.telefone,
    -- Volta como objeto JSON, igual antes da criptografia.
    'endereco', CASE WHEN v_endereco IS NULL OR v_endereco = ''
                     THEN NULL ELSE v_endereco::jsonb END,
    'dados_bancarios', public.fn_rh_decrypt(v_row.dados_bancarios_encrypted, v_org),
    'estado_civil', v_row.estado_civil,
    'dependentes', v_row.dependentes,
    'pcd', v_row.pcd,
    'tipo_deficiencia',
      public.fn_rh_decrypt(v_row.tipo_deficiencia_encrypted, v_org),
    'salario', v_salario
  );
END;
$$;

-- rh_get_historico_cargo_salario ← 20260725100000_rh21_ficha_funcionario_expansao.sql
CREATE OR REPLACE FUNCTION public.rh_get_historico_cargo_salario(p_funcionario_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_res jsonb;
BEGIN
  -- Apenas RH ou o próprio funcionário podem ler
  IF NOT (public.fn_rh_pode('rh_funcionarios', 'manage') OR public.fn_is_own_funcionario(p_funcionario_id)) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  -- Se for RH acessando de outro, audita
  IF public.fn_rh_pode('rh_funcionarios', 'manage') AND NOT public.fn_is_own_funcionario(p_funcionario_id) THEN
    INSERT INTO public.rh_access_log
      (organization_id, funcionario_id, usuario_id, acao)
    VALUES (v_org, p_funcionario_id, auth.uid(), 'visualizou_historico_salarial');
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', h.id,
      'cargo_id', h.cargo_id,
      'departamento_id', h.departamento_id,
      'salario', public.fn_rh_decrypt(h.salario_encrypted, v_org),
      'data_inicio', h.data_inicio,
      'motivo', h.motivo,
      'created_at', h.created_at
    ) ORDER BY h.data_inicio DESC, h.created_at DESC
  ) INTO v_res
  FROM public.rh_historico_cargo_salario h
  WHERE h.funcionario_id = p_funcionario_id AND h.organization_id = v_org;

  RETURN coalesce(v_res, '[]'::jsonb);
END;
$$;

-- rh_list_dependentes ← 20260727100000_rh22_consolidacao_fases789.sql
CREATE OR REPLACE FUNCTION public.rh_list_dependentes(p_funcionario_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_res jsonb;
BEGIN
  IF NOT (public.fn_rh_pode('rh_funcionarios', 'manage') OR public.fn_is_own_funcionario(p_funcionario_id)) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'id', d.id,
    'nome', d.nome,
    'data_nascimento', d.data_nascimento,
    'parentesco', d.parentesco,
    'cpf', public.fn_rh_decrypt(d.cpf_encrypted, v_org)
  ) ORDER BY d.data_nascimento) INTO v_res
  FROM public.rh_dependente d
  WHERE d.funcionario_id = p_funcionario_id AND d.organization_id = v_org;

  RETURN coalesce(v_res, '[]'::jsonb);
END;
$$;

-- rh_upsert_dados_sensiveis ← 20260803220000_rh_sensitive_encryption.sql
CREATE OR REPLACE FUNCTION public.rh_upsert_dados_sensiveis(
  p_funcionario_id uuid, p_dados jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_cpf text := regexp_replace(coalesce(p_dados->>'cpf', ''), '\D', '', 'g');
  v_salario text := nullif(p_dados->>'salario', '');
BEGIN
  -- Edição de sensíveis exige RH admin (S080)
  IF NOT public.fn_rh_pode('rh_funcionarios', 'manage') THEN
    RAISE EXCEPTION 'Apenas administradores do RH podem editar dados sensíveis';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionario f
                 WHERE f.id = p_funcionario_id AND f.organization_id = v_org) THEN
    RAISE EXCEPTION 'Funcionário não encontrado';
  END IF;
  IF v_cpf <> '' AND NOT public.fn_validar_cpf(v_cpf) THEN
    RAISE EXCEPTION 'CPF inválido';
  END IF;

  INSERT INTO public.funcionario_dados_sensiveis AS ds (
    funcionario_id, organization_id,
    cpf_encrypted, cpf_hash, rg_encrypted, data_nascimento,
    email_pessoal, telefone, endereco_encrypted,
    dados_bancarios_encrypted, estado_civil, dependentes,
    pcd, tipo_deficiencia_encrypted, updated_by, updated_at
  ) VALUES (
    p_funcionario_id, v_org,
    public.fn_rh_encrypt(nullif(v_cpf, ''), v_org),
    CASE WHEN v_cpf = '' THEN NULL
         ELSE encode(extensions.digest(v_cpf || v_org::text, 'sha256'), 'hex') END,
    public.fn_rh_encrypt(nullif(p_dados->>'rg', ''), v_org),
    (p_dados->>'data_nascimento')::date,
    nullif(p_dados->>'email_pessoal', ''),
    nullif(p_dados->>'telefone', ''),
    public.fn_rh_encrypt(
      CASE WHEN p_dados->'endereco' IS NULL
                OR jsonb_typeof(p_dados->'endereco') = 'null'
           THEN NULL ELSE (p_dados->'endereco')::text END, v_org),
    public.fn_rh_encrypt(nullif(p_dados->>'dados_bancarios', ''), v_org),
    nullif(p_dados->>'estado_civil', ''),
    (p_dados->>'dependentes')::smallint,
    coalesce((p_dados->>'pcd')::boolean, false),
    public.fn_rh_encrypt(nullif(p_dados->>'tipo_deficiencia', ''), v_org),
    auth.uid(), NOW()
  )
  ON CONFLICT (funcionario_id) DO UPDATE SET
    cpf_encrypted = EXCLUDED.cpf_encrypted,
    cpf_hash = EXCLUDED.cpf_hash,
    rg_encrypted = EXCLUDED.rg_encrypted,
    data_nascimento = EXCLUDED.data_nascimento,
    email_pessoal = EXCLUDED.email_pessoal,
    telefone = EXCLUDED.telefone,
    endereco_encrypted = EXCLUDED.endereco_encrypted,
    dados_bancarios_encrypted = EXCLUDED.dados_bancarios_encrypted,
    estado_civil = EXCLUDED.estado_civil,
    dependentes = EXCLUDED.dependentes,
    pcd = EXCLUDED.pcd,
    tipo_deficiencia_encrypted = EXCLUDED.tipo_deficiencia_encrypted,
    updated_by = EXCLUDED.updated_by,
    updated_at = NOW();

  -- Salário fica no vínculo mais recente (S072/S073)
  IF v_salario IS NOT NULL THEN
    UPDATE public.vinculo vv
    SET salario_encrypted = public.fn_rh_encrypt(v_salario, v_org)
    WHERE vv.id = (SELECT id FROM public.vinculo
                   WHERE funcionario_id = p_funcionario_id
                   ORDER BY created_at DESC LIMIT 1);
  END IF;

  -- Auditoria de alteração (S081) — mantida como estava, para não
  -- quebrar relatórios que já leem rh_access_log.
  INSERT INTO public.rh_access_log
    (organization_id, funcionario_id, usuario_id, acao, detalhes)
  VALUES (v_org, p_funcionario_id, auth.uid(), 'editou_dados_sensiveis',
          jsonb_build_object('campos', (SELECT jsonb_agg(k) FROM jsonb_object_keys(p_dados) k)));

  -- E também no log central, para a visão unificada do Art. 37.
  PERFORM public.fn_audit('rh.dados_sensiveis_editados', 'funcionario',
    p_funcionario_id::text, '{}');
END;
$$;

-- rh_vincular_usuario ← 20260714110000_rh8_vinculo_usuario.sql
CREATE OR REPLACE FUNCTION public.rh_vincular_usuario(
  p_funcionario_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_atual uuid;
BEGIN
  IF NOT public.fn_rh_pode('rh_funcionarios', 'manage') THEN
    RAISE EXCEPTION 'Apenas administradores do RH podem vincular usuários';
  END IF;

  SELECT f.user_id INTO v_atual
  FROM public.funcionario f
  WHERE f.id = p_funcionario_id
    AND f.organization_id = v_org
    AND f.deleted_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado';
  END IF;
  IF v_atual IS NOT NULL THEN
    RAISE EXCEPTION 'Este funcionário já está vinculado a um usuário — desvincule primeiro';
  END IF;

  -- Usuário precisa ser da MESMA organização e estar ativo
  IF NOT EXISTS (SELECT 1 FROM public.users u
                 WHERE u.id = p_user_id
                   AND u.organization_id = v_org
                   AND u.is_active = true) THEN
    RAISE EXCEPTION 'Usuário não encontrado na organização';
  END IF;

  -- Unicidade 1:1 (o índice uq_funcionario_user é a defesa final)
  IF EXISTS (SELECT 1 FROM public.funcionario f
             WHERE f.user_id = p_user_id AND f.deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Este usuário já está vinculado a outro funcionário';
  END IF;

  UPDATE public.funcionario
     SET user_id = p_user_id, updated_by = auth.uid()
   WHERE id = p_funcionario_id;

  INSERT INTO public.rh_access_log
    (organization_id, funcionario_id, usuario_id, acao, detalhes)
  VALUES (v_org, p_funcionario_id, auth.uid(), 'vinculou_usuario',
          jsonb_build_object('user_id', p_user_id));
END;
$$;

