-- ============================================================
-- Módulo RH-4 — Ficha do Funcionário (escopo S070–S081)
-- Duas camadas: funcionario (dados públicos, toda a org lê) e
-- funcionario_dados_sensiveis (CPF/bancários/etc. criptografados,
-- acesso SOMENTE via RPCs que exigem papel RH e registram em
-- rh_access_log — S008/B009). Vínculos 1:N referenciam o
-- organograma existente (S072/RH-4.9).
--
-- Criptografia (S073): pgcrypto (pgp_sym_encrypt) com chave
-- simétrica POR ORGANIZAÇÃO guardada no Vault
-- (rh_data_key_<org_id>, criada sob demanda). A extensão pgcrypto
-- já está disponível no Supabase.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── 1. Enums ─────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE public.funcionario_status AS ENUM
    ('ativo', 'ferias', 'afastado', 'desligado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.vinculo_tipo AS ENUM
    ('clt', 'pj', 'estagio', 'temporario', 'aprendiz');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.vinculo_status AS ENUM
    ('experiencia', 'efetivo', 'aviso_previo', 'desligado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 2. Chave de criptografia por organização (Vault) ─────────
CREATE OR REPLACE FUNCTION public.fn_rh_data_key(p_org uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_name text := 'rh_data_key_' || p_org::text;
  v_key text;
BEGIN
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets WHERE name = v_name LIMIT 1;
  IF v_key IS NULL THEN
    v_key := encode(extensions.gen_random_bytes(32), 'hex');
    PERFORM vault.create_secret(v_key, v_name);
  END IF;
  RETURN v_key;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_rh_data_key(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_rh_encrypt(p_text text, p_org uuid)
RETURNS text LANGUAGE sql SECURITY DEFINER
SET search_path = '' AS $$
  SELECT CASE WHEN p_text IS NULL OR p_text = '' THEN NULL
    ELSE encode(
      extensions.pgp_sym_encrypt(p_text, public.fn_rh_data_key(p_org)), 'base64')
  END;
$$;

CREATE OR REPLACE FUNCTION public.fn_rh_decrypt(p_cipher text, p_org uuid)
RETURNS text LANGUAGE sql SECURITY DEFINER
SET search_path = '' AS $$
  SELECT CASE WHEN p_cipher IS NULL THEN NULL
    ELSE extensions.pgp_sym_decrypt(
      decode(p_cipher, 'base64'), public.fn_rh_data_key(p_org))
  END;
$$;
REVOKE ALL ON FUNCTION public.fn_rh_encrypt(text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_rh_decrypt(text, uuid) FROM PUBLIC, anon, authenticated;

-- ── 3. Validação de CPF (dígitos verificadores — S076) ───────
CREATE OR REPLACE FUNCTION public.fn_validar_cpf(p_cpf text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  soma int; dig int; i int;
BEGIN
  IF length(v) <> 11 OR v ~ '^(\d)\1{10}$' THEN RETURN false; END IF;
  soma := 0;
  FOR i IN 1..9 LOOP
    soma := soma + substr(v, i, 1)::int * (11 - i);
  END LOOP;
  dig := (soma * 10) % 11; IF dig = 10 THEN dig := 0; END IF;
  IF dig <> substr(v, 10, 1)::int THEN RETURN false; END IF;
  soma := 0;
  FOR i IN 1..10 LOOP
    soma := soma + substr(v, i, 1)::int * (12 - i);
  END LOOP;
  dig := (soma * 10) % 11; IF dig = 10 THEN dig := 0; END IF;
  RETURN dig = substr(v, 11, 1)::int;
END;
$$;

-- ── 4. Tabelas ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.funcionario (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  nome            TEXT NOT NULL CHECK (char_length(nome) >= 3),
  foto_url        TEXT,
  status          public.funcionario_status NOT NULL DEFAULT 'ativo',
  -- Vínculos com o restante da plataforma (S079/RH-4.9)
  user_id         UUID REFERENCES public.users(id),
  candidato_id    UUID REFERENCES public.candidato(id),
  created_by      UUID REFERENCES public.users(id),
  updated_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ,
  deleted_by      UUID REFERENCES public.users(id)
);

CREATE INDEX IF NOT EXISTS idx_funcionario_org
  ON public.funcionario(organization_id, status) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS funcionario_updated_at ON public.funcionario;
CREATE TRIGGER funcionario_updated_at
  BEFORE UPDATE ON public.funcionario
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.funcionario_dados_sensiveis (
  funcionario_id  UUID PRIMARY KEY REFERENCES public.funcionario(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  cpf_encrypted   TEXT,
  cpf_hash        TEXT,
  rg              TEXT,
  data_nascimento DATE,
  email_pessoal   TEXT,
  telefone        TEXT,
  endereco        JSONB,
  dados_bancarios_encrypted TEXT,
  estado_civil    TEXT,
  dependentes     SMALLINT,
  pcd             BOOLEAN NOT NULL DEFAULT false,
  tipo_deficiencia TEXT,
  updated_by      UUID REFERENCES public.users(id),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- CPF único por organização (hash — S077)
CREATE UNIQUE INDEX IF NOT EXISTS uq_funcionario_org_cpf
  ON public.funcionario_dados_sensiveis(organization_id, cpf_hash)
  WHERE cpf_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.vinculo (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  funcionario_id   UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  organization_id  UUID NOT NULL REFERENCES public.organizations(id),
  tipo             public.vinculo_tipo NOT NULL DEFAULT 'clt',
  data_admissao    DATE NOT NULL,
  data_desligamento DATE,
  salario_encrypted TEXT,
  carga_horaria    TEXT,
  matricula        TEXT,
  filial_id        UUID REFERENCES public.branches(id),
  departamento_id  TEXT REFERENCES public.departments(id),
  cargo_id         TEXT REFERENCES public.job_positions(id),
  status           public.vinculo_status NOT NULL DEFAULT 'experiencia',
  created_by       UUID REFERENCES public.users(id),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vinculo_funcionario
  ON public.vinculo(funcionario_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_vinculo_org_filial
  ON public.vinculo(organization_id, filial_id);

-- Log de acesso a dados sensíveis (S008/B009 — auditoria LGPD)
CREATE TABLE IF NOT EXISTS public.rh_access_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  funcionario_id  UUID REFERENCES public.funcionario(id) ON DELETE SET NULL,
  usuario_id      UUID REFERENCES public.users(id),
  acao            TEXT NOT NULL,
  detalhes        JSONB NOT NULL DEFAULT '{}',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rh_access_log_org
  ON public.rh_access_log(organization_id, created_at DESC);

-- ── 5. RLS ───────────────────────────────────────────────────
ALTER TABLE public.funcionario                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.funcionario_dados_sensiveis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vinculo                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rh_access_log               ENABLE ROW LEVEL SECURITY;

-- funcionario: toda a org lê (S074); escreve só RH
DROP POLICY IF EXISTS "Org lê funcionários" ON public.funcionario;
CREATE POLICY "Org lê funcionários"
  ON public.funcionario FOR SELECT
  USING (organization_id = public.fn_current_org() AND deleted_at IS NULL);

DROP POLICY IF EXISTS "RH insere funcionários" ON public.funcionario;
CREATE POLICY "RH insere funcionários"
  ON public.funcionario FOR INSERT
  WITH CHECK (public.fn_is_rh() AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "RH atualiza funcionários" ON public.funcionario;
CREATE POLICY "RH atualiza funcionários"
  ON public.funcionario FOR UPDATE
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org())
  WITH CHECK (organization_id = public.fn_current_org());
-- Sem DELETE: soft delete via deleted_at (S006)

-- dados_sensiveis: NENHUM acesso direto — só via RPCs abaixo (S074/S080)
-- (RLS habilitada sem policies = negado para anon/authenticated)

-- vinculo: RH lê e escreve na própria org
DROP POLICY IF EXISTS "RH acessa vínculos" ON public.vinculo;
CREATE POLICY "RH acessa vínculos"
  ON public.vinculo FOR ALL
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org())
  WITH CHECK (public.fn_is_rh() AND organization_id = public.fn_current_org());

-- rh_access_log: leitura só RH admin; escrita via RPCs (definer)
DROP POLICY IF EXISTS "RH admin lê log de acesso" ON public.rh_access_log;
CREATE POLICY "RH admin lê log de acesso"
  ON public.rh_access_log FOR SELECT
  USING (public.fn_is_rh_admin() AND organization_id = public.fn_current_org());

-- ── 6. View pública de listagem (S075) ───────────────────────
CREATE OR REPLACE VIEW public.funcionario_resumo
WITH (security_invoker = true) AS
SELECT
  f.id, f.organization_id, f.nome, f.foto_url, f.status,
  f.user_id, f.candidato_id, f.created_at,
  v.id  AS vinculo_id,
  v.tipo AS vinculo_tipo,
  v.status AS vinculo_status,
  v.data_admissao,
  v.matricula,
  b.name AS filial,
  d.name AS departamento,
  jp.name AS cargo
FROM public.funcionario f
LEFT JOIN LATERAL (
  SELECT * FROM public.vinculo vv
  WHERE vv.funcionario_id = f.id
  ORDER BY vv.created_at DESC LIMIT 1
) v ON true
LEFT JOIN public.branches      b  ON b.id = v.filial_id
LEFT JOIN public.job_positions jp ON jp.id = v.cargo_id
LEFT JOIN public.departments   d  ON d.id = v.departamento_id
WHERE f.deleted_at IS NULL;

-- ── 7. RPC: ler dados sensíveis (descriptografa + audita) ────
CREATE OR REPLACE FUNCTION public.rh_get_dados_sensiveis(p_funcionario_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_row public.funcionario_dados_sensiveis%ROWTYPE;
  v_salario text;
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

  RETURN jsonb_build_object(
    'exists', true,
    'cpf', public.fn_rh_decrypt(v_row.cpf_encrypted, v_org),
    'rg', v_row.rg,
    'data_nascimento', v_row.data_nascimento,
    'email_pessoal', v_row.email_pessoal,
    'telefone', v_row.telefone,
    'endereco', v_row.endereco,
    'dados_bancarios', public.fn_rh_decrypt(v_row.dados_bancarios_encrypted, v_org),
    'estado_civil', v_row.estado_civil,
    'dependentes', v_row.dependentes,
    'pcd', v_row.pcd,
    'tipo_deficiencia', v_row.tipo_deficiencia,
    'salario', v_salario
  );
END;
$$;
REVOKE ALL ON FUNCTION public.rh_get_dados_sensiveis(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_get_dados_sensiveis(uuid) TO authenticated;

-- ── 8. RPC: gravar dados sensíveis (valida CPF, criptografa) ─
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
    cpf_encrypted, cpf_hash, rg, data_nascimento, email_pessoal, telefone,
    endereco, dados_bancarios_encrypted, estado_civil, dependentes,
    pcd, tipo_deficiencia, updated_by, updated_at
  ) VALUES (
    p_funcionario_id, v_org,
    public.fn_rh_encrypt(nullif(v_cpf, ''), v_org),
    CASE WHEN v_cpf = '' THEN NULL
         ELSE encode(extensions.digest(v_cpf || v_org::text, 'sha256'), 'hex') END,
    nullif(p_dados->>'rg', ''),
    (p_dados->>'data_nascimento')::date,
    nullif(p_dados->>'email_pessoal', ''),
    nullif(p_dados->>'telefone', ''),
    p_dados->'endereco',
    public.fn_rh_encrypt(nullif(p_dados->>'dados_bancarios', ''), v_org),
    nullif(p_dados->>'estado_civil', ''),
    (p_dados->>'dependentes')::smallint,
    coalesce((p_dados->>'pcd')::boolean, false),
    nullif(p_dados->>'tipo_deficiencia', ''),
    auth.uid(), NOW()
  )
  ON CONFLICT (funcionario_id) DO UPDATE SET
    cpf_encrypted = EXCLUDED.cpf_encrypted,
    cpf_hash = EXCLUDED.cpf_hash,
    rg = EXCLUDED.rg,
    data_nascimento = EXCLUDED.data_nascimento,
    email_pessoal = EXCLUDED.email_pessoal,
    telefone = EXCLUDED.telefone,
    endereco = EXCLUDED.endereco,
    dados_bancarios_encrypted = EXCLUDED.dados_bancarios_encrypted,
    estado_civil = EXCLUDED.estado_civil,
    dependentes = EXCLUDED.dependentes,
    pcd = EXCLUDED.pcd,
    tipo_deficiencia = EXCLUDED.tipo_deficiencia,
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

  -- Auditoria de alteração (S081)
  INSERT INTO public.rh_access_log
    (organization_id, funcionario_id, usuario_id, acao, detalhes)
  VALUES (v_org, p_funcionario_id, auth.uid(), 'editou_dados_sensiveis',
          jsonb_build_object('campos', (SELECT jsonb_agg(k) FROM jsonb_object_keys(p_dados) k)));
END;
$$;
REVOKE ALL ON FUNCTION public.rh_upsert_dados_sensiveis(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_upsert_dados_sensiveis(uuid, jsonb) TO authenticated;

-- ── 9. RPC: converter candidato aprovado em funcionário ──────
-- Transação atômica (S078/S079/B011): cria funcionario + vinculo,
-- marca candidato como contratado e registra histórico. O gatilho
-- do onboarding (RH-5) será acoplado aqui na Etapa 5.
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

  -- Contato do candidato vira dado sensível inicial (S078)
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
          p_filial_id, p_departamento_id, p_cargo_id, auth.uid());

  UPDATE public.candidato SET status = 'contratado', updated_by = auth.uid()
  WHERE id = p_candidato_id;

  INSERT INTO public.rh_access_log
    (organization_id, funcionario_id, usuario_id, acao, detalhes)
  VALUES (v_org, v_func_id, auth.uid(), 'converteu_candidato',
          jsonb_build_object('candidato_id', p_candidato_id));

  RETURN v_func_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_converter_candidato FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_converter_candidato TO authenticated;
