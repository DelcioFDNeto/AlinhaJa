-- ============================================================
-- Módulo RH-1 — Banco de Talentos (escopo S029–S041, S013/S014)
-- Tabelas de candidatos, currículos e dados extraídos por IA,
-- máquina de estados de status, histórico e buckets de storage.
-- Depende da Fase 0 (organizations, fn_current_org, fn_is_rh).
-- ============================================================

-- ── 1. Enums ─────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE public.candidato_status AS ENUM
    ('novo', 'em_analise', 'entrevista', 'aprovado', 'contratado', 'descartado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.candidato_fonte AS ENUM
    ('portal', 'upload_manual', 'indicacao');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.extracao_status AS ENUM
    ('pendente', 'processando', 'extraido', 'falhou');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 2. Tabela principal: candidato (S029) ────────────────────
CREATE TABLE IF NOT EXISTS public.candidato (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     UUID NOT NULL REFERENCES public.organizations(id),
  nome                TEXT NOT NULL CHECK (char_length(nome) >= 3),
  email               TEXT NOT NULL CHECK (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  telefone            TEXT,
  cidade              TEXT,
  estado              TEXT,
  area_interesse      TEXT,
  cargo_pretendido    TEXT,
  nivel               TEXT,
  disponibilidade     TEXT,
  pretensao_salarial  NUMERIC(12,2),
  foto_url            TEXT,
  status              public.candidato_status NOT NULL DEFAULT 'novo',
  fonte               public.candidato_fonte  NOT NULL DEFAULT 'upload_manual',
  extracao            public.extracao_status  NOT NULL DEFAULT 'pendente',
  score_completude    SMALLINT CHECK (score_completude BETWEEN 0 AND 100),
  resumo_executivo    TEXT,
  -- LGPD (S009/S036/S054): sem aceite não há cadastro
  consentimento_lgpd  BOOLEAN NOT NULL CHECK (consentimento_lgpd = true),
  consentimento_data  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  consentimento_versao TEXT NOT NULL DEFAULT 'v1',
  consentimento_ip    TEXT,
  consentimento_user_agent TEXT,
  -- Área do candidato (RH-2.7): token com expiração de 90 dias
  portal_token        UUID NOT NULL DEFAULT gen_random_uuid(),
  portal_token_expira TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '90 days',
  -- Auditoria (S005) e soft delete (S006/S010 — anonimização futura)
  created_by          UUID REFERENCES public.users(id),
  updated_by          UUID REFERENCES public.users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at          TIMESTAMPTZ,
  deleted_by          UUID REFERENCES public.users(id)
);

-- E-mail único por organização, não global (S035)
CREATE UNIQUE INDEX IF NOT EXISTS uq_candidato_org_email
  ON public.candidato(organization_id, lower(email))
  WHERE deleted_at IS NULL;

-- Índices de performance (S026) e token do portal
CREATE INDEX IF NOT EXISTS idx_candidato_org_status
  ON public.candidato(organization_id, status) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_candidato_portal_token
  ON public.candidato(portal_token);

DROP TRIGGER IF EXISTS candidato_updated_at ON public.candidato;
CREATE TRIGGER candidato_updated_at
  BEFORE UPDATE ON public.candidato
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 3. Tabelas satélite ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.candidato_curriculo (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidato_id   UUID NOT NULL REFERENCES public.candidato(id) ON DELETE CASCADE,
  arquivo_url    TEXT NOT NULL,
  tipo_arquivo   TEXT NOT NULL CHECK (tipo_arquivo IN ('pdf', 'docx')),
  tamanho_bytes  BIGINT NOT NULL CHECK (tamanho_bytes <= 5242880),
  texto_extraido TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.candidato_formacao (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidato_id UUID NOT NULL REFERENCES public.candidato(id) ON DELETE CASCADE,
  instituicao  TEXT,
  curso        TEXT,
  grau         TEXT,
  ano_inicio   SMALLINT,
  ano_fim      SMALLINT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.candidato_experiencia (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidato_id UUID NOT NULL REFERENCES public.candidato(id) ON DELETE CASCADE,
  empresa      TEXT,
  cargo        TEXT,
  descricao    TEXT,
  data_inicio  DATE,
  data_fim     DATE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.candidato_habilidade (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidato_id UUID NOT NULL REFERENCES public.candidato(id) ON DELETE CASCADE,
  nome         TEXT NOT NULL,
  origem       TEXT NOT NULL DEFAULT 'ia' CHECK (origem IN ('ia', 'manual')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (candidato_id, nome)
);

CREATE INDEX IF NOT EXISTS idx_curriculo_candidato   ON public.candidato_curriculo(candidato_id);
CREATE INDEX IF NOT EXISTS idx_formacao_candidato    ON public.candidato_formacao(candidato_id);
CREATE INDEX IF NOT EXISTS idx_experiencia_candidato ON public.candidato_experiencia(candidato_id);
CREATE INDEX IF NOT EXISTS idx_habilidade_candidato  ON public.candidato_habilidade(candidato_id);
CREATE INDEX IF NOT EXISTS idx_habilidade_nome       ON public.candidato_habilidade(lower(nome));

-- ── 4. Histórico e máquina de estados (S034/S039/S040) ───────
CREATE TABLE IF NOT EXISTS public.candidato_historico (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidato_id UUID NOT NULL REFERENCES public.candidato(id) ON DELETE CASCADE,
  acao         TEXT NOT NULL,
  detalhes     JSONB NOT NULL DEFAULT '{}',
  usuario_id   UUID REFERENCES public.users(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_historico_candidato
  ON public.candidato_historico(candidato_id, created_at DESC);

-- Ordem do funil; 'descartado' é terminal alcançável de qualquer
-- status exceto 'contratado'. Nenhuma transição retroativa (S039).
CREATE OR REPLACE FUNCTION public.fn_candidato_status_guard()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_ordem CONSTANT JSONB :=
    '{"novo":1,"em_analise":2,"entrevista":3,"aprovado":4,"contratado":5}';
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    IF OLD.status = 'contratado' THEN
      RAISE EXCEPTION 'Candidato contratado não pode mudar de status';
    ELSIF OLD.status = 'descartado' AND NEW.status <> 'novo' THEN
      -- Reativação de descartado só recomeçando o funil
      RAISE EXCEPTION 'Candidato descartado só pode ser reativado como novo';
    ELSIF NEW.status <> 'descartado' AND OLD.status <> 'descartado'
      AND (v_ordem->>NEW.status::text)::int < (v_ordem->>OLD.status::text)::int THEN
      RAISE EXCEPTION 'Transição retroativa de status não permitida (% → %)',
        OLD.status, NEW.status;
    END IF;
    INSERT INTO public.candidato_historico (candidato_id, acao, detalhes, usuario_id)
    VALUES (NEW.id, 'mudanca_status',
            jsonb_build_object('de', OLD.status, 'para', NEW.status),
            auth.uid());
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS candidato_status_guard ON public.candidato;
CREATE TRIGGER candidato_status_guard
  BEFORE UPDATE ON public.candidato
  FOR EACH ROW EXECUTE FUNCTION public.fn_candidato_status_guard();

-- ── 5. RLS (S002): somente RH da mesma organização ───────────
ALTER TABLE public.candidato             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidato_curriculo   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidato_formacao    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidato_experiencia ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidato_habilidade  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidato_historico   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "RH lê candidatos da própria org" ON public.candidato;
CREATE POLICY "RH lê candidatos da própria org"
  ON public.candidato FOR SELECT
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org()
         AND deleted_at IS NULL);

DROP POLICY IF EXISTS "RH insere candidatos na própria org" ON public.candidato;
CREATE POLICY "RH insere candidatos na própria org"
  ON public.candidato FOR INSERT
  WITH CHECK (public.fn_is_rh() AND organization_id = public.fn_current_org());

DROP POLICY IF EXISTS "RH atualiza candidatos da própria org" ON public.candidato;
CREATE POLICY "RH atualiza candidatos da própria org"
  ON public.candidato FOR UPDATE
  USING (public.fn_is_rh() AND organization_id = public.fn_current_org())
  WITH CHECK (organization_id = public.fn_current_org());
-- Sem policy de DELETE: exclusão real proibida (S006) — usar deleted_at.

-- Satélites herdam o acesso via join com candidato
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['candidato_curriculo','candidato_formacao',
                           'candidato_experiencia','candidato_habilidade',
                           'candidato_historico']
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS "RH acessa %1$s da própria org" ON public.%1$s', t);
    EXECUTE format($f$
      CREATE POLICY "RH acessa %1$s da própria org"
        ON public.%1$s FOR ALL
        USING (public.fn_is_rh() AND EXISTS (
          SELECT 1 FROM public.candidato c
          WHERE c.id = %1$s.candidato_id
            AND c.organization_id = public.fn_current_org()))
        WITH CHECK (public.fn_is_rh() AND EXISTS (
          SELECT 1 FROM public.candidato c
          WHERE c.id = %1$s.candidato_id
            AND c.organization_id = public.fn_current_org()));
    $f$, t);
  END LOOP;
END $$;

-- ── 6. Dashboard: contagem por status (S041) ─────────────────
CREATE OR REPLACE VIEW public.candidato_contagem_status
WITH (security_invoker = true) AS
SELECT organization_id, status, count(*) AS total
FROM public.candidato
WHERE deleted_at IS NULL
GROUP BY organization_id, status;

-- ── 7. Buckets de storage do RH (S013/S014) ──────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('rh-curriculos', 'rh-curriculos', false, 5242880,
   ARRAY['application/pdf',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document']),
  ('rh-fotos', 'rh-fotos', false, 2097152,
   ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('rh-documentos', 'rh-documentos', false, 10485760,
   ARRAY['application/pdf', 'image/jpeg', 'image/png',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
ON CONFLICT (id) DO NOTHING;

-- Leitura/escrita nos buckets RH somente para papel RH; o portal
-- público grava via Edge Function (service role, bypassa RLS).
DROP POLICY IF EXISTS "RH acessa storage RH" ON storage.objects;
CREATE POLICY "RH acessa storage RH"
  ON storage.objects FOR ALL
  USING (bucket_id IN ('rh-curriculos', 'rh-fotos', 'rh-documentos')
         AND public.fn_is_rh())
  WITH CHECK (bucket_id IN ('rh-curriculos', 'rh-fotos', 'rh-documentos')
              AND public.fn_is_rh());
