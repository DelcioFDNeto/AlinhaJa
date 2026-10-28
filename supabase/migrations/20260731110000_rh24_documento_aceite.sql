-- ============================================================
-- RH-24 / Fase 8 — Aceite (assinatura eletrônica simples) de
-- documentos (PLANO-RH-COMPLETO.md, seção 11: "Documentos:
-- assinatura/aceite, validade e alertas de vencimento").
--
-- Validade e alertas já existiam (rh6). O que faltava era o aceite:
-- o RH marca um documento como "exige aceite" e o funcionário
-- vinculado (F1.2) registra a concordância na tela /meus-documentos.
--
-- O carimbo do aceite (quem, quando, de onde) é feito SEMPRE no
-- servidor — o cliente só dispara a RPC. Sem isso não há valor
-- probatório. Mesmo racional do consentimento LGPD do candidato,
-- que já grava ip + user_agent.
--
-- Migration 100% aditiva.
-- ============================================================

-- ── 1. Colunas de aceite ─────────────────────────────────────
ALTER TABLE public.rh_documento
  ADD COLUMN IF NOT EXISTS exige_aceite       BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS aceito_em          TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS aceito_por         UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS aceite_ip          TEXT,
  ADD COLUMN IF NOT EXISTS aceite_user_agent  TEXT;

COMMENT ON COLUMN public.rh_documento.exige_aceite IS
  'RH marcou que o funcionário precisa declarar ciência/concordância.';
COMMENT ON COLUMN public.rh_documento.aceito_em IS
  'Instante do aceite, carimbado pelo servidor (nunca pelo cliente).';
COMMENT ON COLUMN public.rh_documento.aceite_ip IS
  'IP de origem do aceite, para trilha de auditoria.';

-- Pendências de aceite: alimenta o contador da tela do funcionário.
CREATE INDEX IF NOT EXISTS idx_rh_documento_aceite_pendente
  ON public.rh_documento(organization_id, funcionario_id)
  WHERE exige_aceite = true AND aceito_em IS NULL AND deleted_at IS NULL;

-- ── 2. RH liga/desliga a exigência de aceite ─────────────────
-- Desligar não apaga um aceite já registrado: a trilha é preservada.
CREATE OR REPLACE FUNCTION public.rh_set_exige_aceite(
  p_documento_id uuid,
  p_exige        boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT public.fn_is_rh() THEN
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
REVOKE ALL ON FUNCTION public.rh_set_exige_aceite(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_set_exige_aceite(uuid, boolean) TO authenticated;

-- ── 3. Funcionário registra o aceite ─────────────────────────
-- Só o dono do documento aceita, uma única vez. ip/user_agent saem dos
-- cabeçalhos da requisição (PostgREST), não de parâmetro do cliente.
CREATE OR REPLACE FUNCTION public.rh_aceitar_documento(p_documento_id uuid)
RETURNS TIMESTAMPTZ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_doc     public.rh_documento%ROWTYPE;
  v_headers json;
  v_ip      text;
  v_agent   text;
  v_agora   timestamptz := NOW();
BEGIN
  SELECT * INTO v_doc
    FROM public.rh_documento
   WHERE id = p_documento_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Documento não encontrado';
  END IF;
  IF NOT public.fn_is_own_funcionario(v_doc.funcionario_id) THEN
    RAISE EXCEPTION 'Você só pode aceitar os seus próprios documentos';
  END IF;
  IF NOT v_doc.exige_aceite THEN
    RAISE EXCEPTION 'Este documento não exige aceite';
  END IF;
  IF v_doc.aceito_em IS NOT NULL THEN
    -- Idempotente: reenvio do mesmo aceite não vira erro nem sobrescreve
    -- o carimbo original.
    RETURN v_doc.aceito_em;
  END IF;

  BEGIN
    v_headers := current_setting('request.headers', true)::json;
    v_ip      := COALESCE(v_headers ->> 'cf-connecting-ip',
                          split_part(v_headers ->> 'x-forwarded-for', ',', 1));
    v_agent   := left(COALESCE(v_headers ->> 'user-agent', ''), 500);
  EXCEPTION WHEN OTHERS THEN
    -- Chamada fora do PostgREST (psql, job): segue sem os cabeçalhos.
    v_ip := NULL; v_agent := NULL;
  END;

  UPDATE public.rh_documento
     SET aceito_em         = v_agora,
         aceito_por        = auth.uid(),
         aceite_ip         = NULLIF(trim(COALESCE(v_ip, '')), ''),
         aceite_user_agent = NULLIF(trim(COALESCE(v_agent, '')), '')
   WHERE id = p_documento_id;

  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_doc.organization_id, auth.uid(), 'aceitou_documento',
          jsonb_build_object('documento_id', p_documento_id,
                             'titulo', v_doc.titulo,
                             'ip', v_ip));

  RETURN v_agora;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_aceitar_documento(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_aceitar_documento(uuid) TO authenticated;

-- ── 4. Pendências de aceite (painel do RH) ───────────────────
-- security_invoker: a RLS de rh_documento decide quem enxerga o quê —
-- o RH vê a org inteira, o funcionário vê só as próprias linhas.
CREATE OR REPLACE VIEW public.rh_documento_aceite_pendente
WITH (security_invoker = true) AS
SELECT
  d.id,
  d.organization_id,
  d.funcionario_id,
  f.nome AS funcionario_nome,
  d.titulo,
  d.categoria,
  d.created_at
FROM public.rh_documento d
JOIN public.funcionario f ON f.id = d.funcionario_id
WHERE d.exige_aceite = true
  AND d.aceito_em IS NULL
  AND d.deleted_at IS NULL;
