-- ============================================================
-- Criptografia dos dados sensíveis restantes (achado LGPD 2.3)
--
-- PROBLEMA
-- `funcionario_dados_sensiveis` cifrava apenas `cpf` e `dados_bancarios`.
-- Ficavam em texto claro: `rg`, `endereco`, `email_pessoal`, `telefone`,
-- `estado_civil` e — o mais crítico — `pcd` e `tipo_deficiencia`, que são
-- dado pessoal SENSÍVEL na definição do Art. 5º, II (saúde) e exigem
-- proteção reforçada e base legal específica (Art. 11).
--
-- ESCOPO DESTA MIGRATION
-- Cifra `rg`, `endereco` e `tipo_deficiencia`. `email_pessoal`, `telefone`
-- e `estado_civil` seguem em claro de propósito: são dados de contato
-- usados em consulta e filtro pelo RH, e cifrá-los quebraria busca sem
-- ganho proporcional — a proteção deles continua sendo a RLS de RH.
-- `pcd` (booleano) fica em claro porque é necessário para cota legal e
-- relatório obrigatório; o que identifica a condição de saúde é o
-- `tipo_deficiencia`, e esse passa a ser cifrado.
--
-- CONTRATO PRESERVADO
-- As RPCs rh_get_dados_sensiveis / rh_upsert_dados_sensiveis continuam
-- recebendo e devolvendo exatamente o mesmo JSON. O Flutter não muda uma
-- linha — a troca é só de armazenamento.
-- ============================================================

-- ── 1. Novas colunas cifradas ────────────────────────────────
ALTER TABLE public.funcionario_dados_sensiveis
  ADD COLUMN IF NOT EXISTS rg_encrypted               TEXT,
  ADD COLUMN IF NOT EXISTS endereco_encrypted         TEXT,
  ADD COLUMN IF NOT EXISTS tipo_deficiencia_encrypted TEXT;

-- ── 2. Backfill do que já existe ─────────────────────────────
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT funcionario_id, organization_id, rg, endereco, tipo_deficiencia
             FROM public.funcionario_dados_sensiveis
  LOOP
    UPDATE public.funcionario_dados_sensiveis ds
       SET rg_encrypted = CASE WHEN r.rg IS NULL OR r.rg = '' THEN NULL
                               ELSE public.fn_rh_encrypt(r.rg, r.organization_id) END,
           endereco_encrypted = CASE WHEN r.endereco IS NULL THEN NULL
                                     ELSE public.fn_rh_encrypt(r.endereco::text,
                                                               r.organization_id) END,
           tipo_deficiencia_encrypted =
             CASE WHEN r.tipo_deficiencia IS NULL OR r.tipo_deficiencia = '' THEN NULL
                  ELSE public.fn_rh_encrypt(r.tipo_deficiencia, r.organization_id) END
     WHERE ds.funcionario_id = r.funcionario_id;
  END LOOP;
END $$;

-- ── 3. Remove as versões em claro ────────────────────────────
-- Só depois do backfill. Se algo acima falhar, a migration aborta em
-- transação e as colunas originais continuam intactas.
ALTER TABLE public.funcionario_dados_sensiveis
  DROP COLUMN IF EXISTS rg,
  DROP COLUMN IF EXISTS endereco,
  DROP COLUMN IF EXISTS tipo_deficiencia;

COMMENT ON COLUMN public.funcionario_dados_sensiveis.tipo_deficiencia_encrypted IS
  'Dado sensível de saúde (LGPD Art. 5º, II). Cifrado; leitura só via rh_get_dados_sensiveis, que audita.';

-- ── 4. RPC de leitura, agora decifrando os três ──────────────
CREATE OR REPLACE FUNCTION public.rh_get_dados_sensiveis(p_funcionario_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_row public.funcionario_dados_sensiveis%ROWTYPE;
  v_salario text;
  v_endereco text;
BEGIN
  IF NOT public.fn_is_rh() THEN
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
REVOKE ALL ON FUNCTION public.rh_get_dados_sensiveis(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_get_dados_sensiveis(uuid) TO authenticated;

-- ── 5. RPC de gravação, cifrando os três ─────────────────────
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
  IF NOT public.fn_is_rh_admin() THEN
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
REVOKE ALL ON FUNCTION public.rh_upsert_dados_sensiveis(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_upsert_dados_sensiveis(uuid, jsonb) TO authenticated;

-- ── 6. Acesso direto à tabela deixa de existir ───────────────
-- Toda leitura passa a ser pela RPC, que audita. Sem isso, o RH podia
-- ler a ficha por REST direto sem deixar registro em rh_access_log.
REVOKE ALL ON public.funcionario_dados_sensiveis FROM authenticated, anon;
