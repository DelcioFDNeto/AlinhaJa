-- ============================================================
-- Módulo RH-8.1 — Expansão da Gestão de Pessoas (Ficha Funcional)
-- Criação das tabelas de Histórico Salarial, Dependentes, Benefícios,
-- Desempenho, Holerites e Ponto Eletrônico.
-- Tudo mantendo a criptografia (pgcrypto) para valores salariais.
-- ============================================================

-- ── 1. Histórico de Cargos e Salários ───────────────────────
CREATE TABLE IF NOT EXISTS public.rh_historico_cargo_salario (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  funcionario_id  UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  cargo_id        TEXT REFERENCES public.job_positions(id),
  departamento_id TEXT REFERENCES public.departments(id),
  salario_encrypted TEXT NOT NULL,
  data_inicio     DATE NOT NULL,
  motivo          TEXT NOT NULL, -- Ex: Contratação, Promoção, Dissídio, Mérito
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by      UUID REFERENCES public.users(id)
);
CREATE INDEX IF NOT EXISTS idx_rh_hist_cargo_func ON public.rh_historico_cargo_salario(funcionario_id);
ALTER TABLE public.rh_historico_cargo_salario ENABLE ROW LEVEL SECURITY;

-- ── 2. Dependentes ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rh_dependente (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  funcionario_id  UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  nome            TEXT NOT NULL,
  data_nascimento DATE NOT NULL,
  parentesco      TEXT NOT NULL, -- Ex: Filho, Cônjuge
  cpf_encrypted   TEXT, -- Se precisar do CPF pra plano de saúde
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rh_dependente_func ON public.rh_dependente(funcionario_id);
ALTER TABLE public.rh_dependente ENABLE ROW LEVEL SECURITY;

-- ── 3. Benefícios ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rh_beneficio (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  nome            TEXT NOT NULL,
  tipo            TEXT NOT NULL, -- Saúde, Odonto, VA, VR, VT, etc
  fornecedor      TEXT,
  ativo           BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.rh_beneficio ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.rh_funcionario_beneficio (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  funcionario_id  UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  beneficio_id    UUID NOT NULL REFERENCES public.rh_beneficio(id) ON DELETE CASCADE,
  data_adesao     DATE NOT NULL,
  data_cancelamento DATE,
  valor_desconto_encrypted TEXT, -- Desconto em folha (coparticipação, etc)
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rh_func_benef_func ON public.rh_funcionario_beneficio(funcionario_id);
ALTER TABLE public.rh_funcionario_beneficio ENABLE ROW LEVEL SECURITY;

-- ── 4. Avaliação de Desempenho ──────────────────────────────
CREATE TABLE IF NOT EXISTS public.rh_avaliacao_desempenho (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  funcionario_id  UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  avaliador_id    UUID REFERENCES public.users(id),
  tipo            TEXT NOT NULL, -- 1:1, Experiência 45d, Anual, etc
  data_avaliacao  DATE NOT NULL,
  pontuacao_geral NUMERIC(5,2), -- Ex: 0 a 100, ou 0 a 5.
  feedback_texto  TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rh_aval_desemp_func ON public.rh_avaliacao_desempenho(funcionario_id);
ALTER TABLE public.rh_avaliacao_desempenho ENABLE ROW LEVEL SECURITY;

-- ── 5. Holerites (Recibos de Pagamento) ─────────────────────
CREATE TABLE IF NOT EXISTS public.rh_holerite (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  funcionario_id  UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  mes_referencia  SMALLINT NOT NULL CHECK (mes_referencia BETWEEN 1 AND 12),
  ano_referencia  SMALLINT NOT NULL,
  arquivo_pdf_path TEXT, -- Armazenamento no Supabase Storage
  dados_gerados   JSONB, -- Caso o RH gere na tela (proventos, descontos, total)
  data_disponibilizacao TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  data_visualizacao TIMESTAMPTZ, -- Registrado quando o colaborador acessa
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rh_holerite_func ON public.rh_holerite(funcionario_id);
ALTER TABLE public.rh_holerite ENABLE ROW LEVEL SECURITY;

-- ── 6. Ponto Eletrônico (Registros) ─────────────────────────
CREATE TABLE IF NOT EXISTS public.rh_ponto_registro (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id),
  funcionario_id  UUID NOT NULL REFERENCES public.funcionario(id) ON DELETE CASCADE,
  data_hora       TIMESTAMPTZ NOT NULL,
  tipo            TEXT NOT NULL, -- Entrada, Saida Almoço, Retorno Almoço, Saída
  latitude        NUMERIC(10,8),
  longitude       NUMERIC(11,8),
  dispositivo_info TEXT,
  origem          TEXT NOT NULL DEFAULT 'app', -- 'app' ou 'importacao' (REP)
  status          TEXT NOT NULL DEFAULT 'aprovado', -- aprovado, aguardando_ajuste, rejeitado
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rh_ponto_func ON public.rh_ponto_registro(funcionario_id, data_hora DESC);
ALTER TABLE public.rh_ponto_registro ENABLE ROW LEVEL SECURITY;

-- ── 7. Políticas de Acesso (RLS) ────────────────────────────

-- RH: Acesso total aos registros de sua organização.
-- Funcionário: Leitura de SEUS PRÓPRIOS registros via user_id -> funcionario.id.

-- Criação de uma view auxiliar ou junção pra validar se quem chama é o próprio
CREATE OR REPLACE FUNCTION public.fn_is_own_funcionario(p_func_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.funcionario
    WHERE id = p_func_id
      AND user_id = auth.uid()
      AND organization_id = public.fn_current_org()
  );
$$;

-- rh_historico_cargo_salario
CREATE POLICY "RH lê e insere histórico" ON public.rh_historico_cargo_salario FOR ALL
USING (public.fn_is_rh() AND organization_id = public.fn_current_org());

-- Para proteger valores salariais, vamos permitir que o próprio funcionário veja o registro,
-- Mas a string cifrada já o impede de ler sem a RPC, a menos que ele tenha a view.
-- Na verdade, a leitura do salário dele mesmo é feita por RPC.
CREATE POLICY "Funcionário lê próprio histórico" ON public.rh_historico_cargo_salario FOR SELECT
USING (public.fn_is_own_funcionario(funcionario_id));

-- rh_dependente
CREATE POLICY "RH acessa dependentes" ON public.rh_dependente FOR ALL
USING (public.fn_is_rh() AND organization_id = public.fn_current_org());
CREATE POLICY "Funcionário lê próprios dependentes" ON public.rh_dependente FOR SELECT
USING (public.fn_is_own_funcionario(funcionario_id));

-- rh_beneficio (catálogo)
CREATE POLICY "RH e todos da org leem beneficios" ON public.rh_beneficio FOR SELECT
USING (organization_id = public.fn_current_org());
CREATE POLICY "RH insere beneficios" ON public.rh_beneficio FOR ALL
USING (public.fn_is_rh() AND organization_id = public.fn_current_org());

-- rh_funcionario_beneficio
CREATE POLICY "RH acessa func_beneficios" ON public.rh_funcionario_beneficio FOR ALL
USING (public.fn_is_rh() AND organization_id = public.fn_current_org());
CREATE POLICY "Funcionário lê próprios beneficios" ON public.rh_funcionario_beneficio FOR SELECT
USING (public.fn_is_own_funcionario(funcionario_id));

-- rh_avaliacao_desempenho
CREATE POLICY "RH acessa avaliacoes" ON public.rh_avaliacao_desempenho FOR ALL
USING (public.fn_is_rh() AND organization_id = public.fn_current_org());
CREATE POLICY "Funcionário lê próprias avaliacoes" ON public.rh_avaliacao_desempenho FOR SELECT
USING (public.fn_is_own_funcionario(funcionario_id));

-- rh_holerite
CREATE POLICY "RH acessa holerites" ON public.rh_holerite FOR ALL
USING (public.fn_is_rh() AND organization_id = public.fn_current_org());
CREATE POLICY "Funcionário lê e atualiza próprio holerite" ON public.rh_holerite FOR SELECT
USING (public.fn_is_own_funcionario(funcionario_id));
CREATE POLICY "Funcionário atualiza visualizacao" ON public.rh_holerite FOR UPDATE
USING (public.fn_is_own_funcionario(funcionario_id));

-- rh_ponto_registro
CREATE POLICY "RH acessa ponto" ON public.rh_ponto_registro FOR ALL
USING (public.fn_is_rh() AND organization_id = public.fn_current_org());
CREATE POLICY "Funcionário acessa próprio ponto" ON public.rh_ponto_registro FOR SELECT
USING (public.fn_is_own_funcionario(funcionario_id));
CREATE POLICY "Funcionário insere próprio ponto" ON public.rh_ponto_registro FOR INSERT
WITH CHECK (public.fn_is_own_funcionario(funcionario_id));

-- ── 8. RPC: ler dados sensíveis completos (incluindo cargo) ──
-- Precisamos atualizar a RPC `rh_get_dados_sensiveis` ou criar uma para ler histórico salarial
CREATE OR REPLACE FUNCTION public.rh_get_historico_cargo_salario(p_funcionario_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_res jsonb;
BEGIN
  -- Apenas RH ou o próprio funcionário podem ler
  IF NOT (public.fn_is_rh() OR public.fn_is_own_funcionario(p_funcionario_id)) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  -- Se for RH acessando de outro, audita
  IF public.fn_is_rh() AND NOT public.fn_is_own_funcionario(p_funcionario_id) THEN
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
REVOKE ALL ON FUNCTION public.rh_get_historico_cargo_salario(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_get_historico_cargo_salario(uuid) TO authenticated;
