-- ============================================================
-- Módulo RH-2 — Portal do Candidato (escopo S042–S054)
-- Mensagens RH ↔ candidato e rate limiting do portal público.
-- O portal em si é servido pela Edge Function rh-candidatura
-- (service role) — nenhuma policy `anon` é criada aqui.
-- ============================================================

-- ── 1. Mensagens entre RH e candidato (RH-2.8) ───────────────
CREATE TABLE IF NOT EXISTS public.candidato_mensagem (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidato_id  UUID NOT NULL REFERENCES public.candidato(id) ON DELETE CASCADE,
  autor         TEXT NOT NULL CHECK (autor IN ('rh', 'candidato')),
  texto         TEXT NOT NULL DEFAULT '',
  -- Documento adicional enviado pelo candidato (RH-2.9): path no bucket
  anexo_url     TEXT,
  anexo_nome    TEXT,
  lida          BOOLEAN NOT NULL DEFAULT false,
  -- Autor RH (null quando autor = 'candidato')
  usuario_id    UUID REFERENCES public.users(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (texto <> '' OR anexo_url IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_mensagem_candidato
  ON public.candidato_mensagem(candidato_id, created_at);

ALTER TABLE public.candidato_mensagem ENABLE ROW LEVEL SECURITY;

-- RH da organização acessa; o candidato acessa via Edge Function
DROP POLICY IF EXISTS "RH acessa mensagens da própria org" ON public.candidato_mensagem;
CREATE POLICY "RH acessa mensagens da própria org"
  ON public.candidato_mensagem FOR ALL
  USING (public.fn_is_rh() AND EXISTS (
    SELECT 1 FROM public.candidato c
    WHERE c.id = candidato_mensagem.candidato_id
      AND c.organization_id = public.fn_current_org()))
  WITH CHECK (public.fn_is_rh() AND autor = 'rh' AND EXISTS (
    SELECT 1 FROM public.candidato c
    WHERE c.id = candidato_mensagem.candidato_id
      AND c.organization_id = public.fn_current_org()));

-- ── 2. Rate limiting do portal público (S052/B008) ───────────
-- Uma linha por tentativa de cadastro; a Edge Function conta as
-- tentativas do IP na última hora antes de aceitar (máx. 10).
CREATE TABLE IF NOT EXISTS public.rh_portal_rate_limit (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ip         TEXT NOT NULL,
  acao       TEXT NOT NULL DEFAULT 'apply',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rate_limit_ip
  ON public.rh_portal_rate_limit(ip, created_at DESC);

-- Sem policies: somente service role (Edge Function) lê/escreve.
ALTER TABLE public.rh_portal_rate_limit ENABLE ROW LEVEL SECURITY;

-- Limpeza de tentativas antigas (chamada pela própria Edge Function)
CREATE OR REPLACE FUNCTION public.fn_rh_rate_limit_cleanup()
RETURNS void LANGUAGE sql SECURITY DEFINER
SET search_path = public AS $$
  DELETE FROM public.rh_portal_rate_limit
  WHERE created_at < NOW() - INTERVAL '24 hours';
$$;
REVOKE EXECUTE ON FUNCTION public.fn_rh_rate_limit_cleanup() FROM anon, authenticated;
