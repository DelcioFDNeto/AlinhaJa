-- =============================================================
-- RH passa a obedecer o RBAC (7/7): RPCs — gestao
-- =============================================================
-- Gerado a partir da ÚLTIMA definição de cada objeto nas migrations
-- (indicada em cada bloco). Só a checagem de acesso muda:
-- fn_is_rh()/fn_is_rh_admin() → fn_rh_pode(<módulo>, <ação>).
-- Ver 20260918110000_rh_rbac_helpers.sql.
-- =============================================================

-- rh_360_convidar ← 20260801120000_rh27_desempenho_ciclos_metas_360.sql
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
  IF NOT public.fn_rh_pode('rh_desempenho', 'manage') THEN
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

-- rh_meta_progresso ← 20260801120000_rh27_desempenho_ciclos_metas_360.sql
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
  IF NOT (public.fn_rh_pode('rh_desempenho', 'manage') OR public.fn_is_own_funcionario(v_meta.funcionario_id)) THEN
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

-- rh_add_adesao_beneficio ← 20260727100000_rh22_consolidacao_fases789.sql
CREATE OR REPLACE FUNCTION public.rh_add_adesao_beneficio(
  p_funcionario_id uuid,
  p_beneficio_id uuid,
  p_data_adesao date,
  p_valor_desconto text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_id uuid;
BEGIN
  IF NOT public.fn_rh_pode('rh_beneficios', 'manage') THEN
    RAISE EXCEPTION 'Apenas o RH pode registrar adesões';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.funcionario f
    WHERE f.id = p_funcionario_id
      AND f.organization_id = v_org AND f.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Funcionário não encontrado nesta organização';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.rh_beneficio b
    WHERE b.id = p_beneficio_id AND b.organization_id = v_org AND b.ativo
  ) THEN
    RAISE EXCEPTION 'Benefício inativo ou de outra organização';
  END IF;

  INSERT INTO public.rh_funcionario_beneficio
    (organization_id, funcionario_id, beneficio_id, data_adesao,
     valor_desconto_encrypted)
  VALUES
    (v_org, p_funcionario_id, p_beneficio_id, p_data_adesao,
     public.fn_rh_encrypt(nullif(trim(coalesce(p_valor_desconto, '')), ''), v_org))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- rh_list_adesoes_beneficio ← 20260727100000_rh22_consolidacao_fases789.sql
CREATE OR REPLACE FUNCTION public.rh_list_adesoes_beneficio(
  p_funcionario_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_res jsonb;
BEGIN
  IF NOT public.fn_rh_pode('rh_beneficios', 'view') THEN
    IF p_funcionario_id IS NULL
       OR NOT public.fn_is_own_funcionario(p_funcionario_id) THEN
      RAISE EXCEPTION 'Acesso negado';
    END IF;
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'id', fb.id,
    'funcionario_id', fb.funcionario_id,
    'funcionario_nome', f.nome,
    'beneficio_id', fb.beneficio_id,
    'beneficio_nome', b.nome,
    'beneficio_tipo', b.tipo,
    'data_adesao', fb.data_adesao,
    'data_cancelamento', fb.data_cancelamento,
    'valor_desconto', public.fn_rh_decrypt(fb.valor_desconto_encrypted, v_org)
  ) ORDER BY fb.data_adesao DESC) INTO v_res
  FROM public.rh_funcionario_beneficio fb
  JOIN public.funcionario f ON f.id = fb.funcionario_id
  JOIN public.rh_beneficio b ON b.id = fb.beneficio_id
  WHERE fb.organization_id = v_org
    AND (p_funcionario_id IS NULL OR fb.funcionario_id = p_funcionario_id);

  RETURN coalesce(v_res, '[]'::jsonb);
END;
$$;

-- rh_get_smtp_config ← 20260727100000_rh22_consolidacao_fases789.sql
CREATE OR REPLACE FUNCTION public.rh_get_smtp_config()
RETURNS TABLE (
  host TEXT, port INTEGER, username TEXT,
  from_email TEXT, from_name TEXT, has_password BOOLEAN
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT (public.fn_is_admin() OR public.fn_rh_pode('rh_automacoes', 'view')) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  RETURN QUERY
  SELECT c.host, c.port, c.username, c.from_email, c.from_name,
         (c.password_encrypted IS NOT NULL) AS has_password
  FROM public.org_smtp_config c
  WHERE c.organization_id = v_org;
END;
$$;

-- rh_save_smtp_config ← 20260727100000_rh22_consolidacao_fases789.sql
CREATE OR REPLACE FUNCTION public.rh_save_smtp_config(
  p_host TEXT, p_port INTEGER, p_username TEXT,
  p_password TEXT, p_from_email TEXT, p_from_name TEXT
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_secret TEXT;
  v_cipher BYTEA;
BEGIN
  IF NOT (public.fn_is_admin() OR public.fn_rh_pode('rh_automacoes', 'manage')) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Organização não resolvida';
  END IF;

  -- Chave por organização no Vault (mesmo padrão de fn_rh_encrypt);
  -- o salt estático derivável do rh19 nunca chegou a cifrar dados reais.
  v_secret := public.fn_rh_data_key(v_org);

  IF p_password IS NULL OR length(trim(p_password)) = 0 THEN
    SELECT c.password_encrypted INTO v_cipher
    FROM public.org_smtp_config c WHERE c.organization_id = v_org;
    IF v_cipher IS NULL THEN
      RAISE EXCEPTION 'Informe a senha do servidor SMTP';
    END IF;
  ELSE
    v_cipher := extensions.pgp_sym_encrypt(p_password, v_secret);
  END IF;

  INSERT INTO public.org_smtp_config (
    organization_id, host, port, username,
    password_encrypted, from_email, from_name
  ) VALUES (
    v_org, p_host, p_port, p_username, v_cipher, p_from_email, p_from_name
  )
  ON CONFLICT (organization_id) DO UPDATE SET
    host = EXCLUDED.host,
    port = EXCLUDED.port,
    username = EXCLUDED.username,
    password_encrypted = EXCLUDED.password_encrypted,
    from_email = EXCLUDED.from_email,
    from_name = EXCLUDED.from_name;
END;
$$;

-- fn_tg_rh_holerite_somente_visualizacao ← 20260918100000_rh_rbac_auditoria.sql
CREATE OR REPLACE FUNCTION public.fn_tg_rh_holerite_somente_visualizacao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_esperado public.rh_holerite;
BEGIN
  IF public.fn_rh_pode('rh_holerites', 'manage') THEN
    RETURN NEW;
  END IF;

  v_esperado := OLD;
  v_esperado.data_visualizacao := NEW.data_visualizacao;
  IF NEW IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'O colaborador só pode registrar a visualização do holerite.'
      USING ERRCODE = '42501';
  END IF;

  -- Uma vez, com a hora do servidor.
  NEW.data_visualizacao := COALESCE(OLD.data_visualizacao, now());
  RETURN NEW;
END;
$$;

-- fn_tg_rh_ponto_hora_servidor ← 20260918100000_rh_rbac_auditoria.sql
CREATE OR REPLACE FUNCTION public.fn_tg_rh_ponto_hora_servidor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.fn_rh_pode('rh_ponto', 'manage')
     OR public.fn_is_own_funcionario(NEW.funcionario_id) THEN
    NEW.data_hora := now();
    SELECT f.organization_id INTO NEW.organization_id
      FROM public.funcionario f
     WHERE f.id = NEW.funcionario_id;
  END IF;
  RETURN NEW;
END;
$$;

