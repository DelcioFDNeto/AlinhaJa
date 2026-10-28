-- ============================================================
-- LGPD — Retenção e Direito ao Esquecimento (escopo S010–S012)
-- Fecha as três lacunas do Módulo 0:
--   S010  Anonimização de candidato (direito ao esquecimento, LGPD Art. 18)
--   S011  Tempo de retenção configurável por empresa
--   S012  Rotina de expiração automática (pg_cron diário)
--
-- Estratégia de anonimização: mantém a LINHA do candidato (id) para
-- não quebrar FKs de histórico/funcionário, mas remove todo PII e
-- apaga currículos/documentos do Storage. A linha anonimizada sai
-- das listagens (deleted_at) e do índice de e-mail único.
-- ============================================================

-- ── 1. Marca de anonimização na tabela candidato ─────────────
ALTER TABLE public.candidato
  ADD COLUMN IF NOT EXISTS anonimizado_em TIMESTAMPTZ;

-- ── 2. Retenção configurável por organização (S011) ──────────
-- Guardada em organizations.settings->>'candidato_retencao_meses'.
-- Padrão: 24 meses (2 anos), conforme exemplo do escopo.
CREATE OR REPLACE FUNCTION public.fn_org_retencao_meses(p_org uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT COALESCE(
    NULLIF(settings->>'candidato_retencao_meses', '')::int,
    24
  )
  FROM public.organizations WHERE id = p_org;
$$;
REVOKE ALL ON FUNCTION public.fn_org_retencao_meses(uuid) FROM PUBLIC, anon;

-- RPC para o admin da própria org ajustar a política de retenção
CREATE OR REPLACE FUNCTION public.rh_set_retencao_candidatos(p_meses int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_org uuid;
BEGIN
  SELECT organization_id INTO v_org FROM public.users
   WHERE id = auth.uid() AND role_level IN ('super_admin', 'admin');
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Apenas administradores podem alterar a política de retenção';
  END IF;
  IF p_meses < 1 OR p_meses > 120 THEN
    RAISE EXCEPTION 'Período de retenção inválido (use de 1 a 120 meses)';
  END IF;
  UPDATE public.organizations
     SET settings = jsonb_set(COALESCE(settings, '{}'),
                              '{candidato_retencao_meses}', to_jsonb(p_meses)),
         updated_at = NOW()
   WHERE id = v_org;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_set_retencao_candidatos(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_set_retencao_candidatos(int) TO authenticated;

-- ── 3. Motor de anonimização (S010) ──────────────────────────
-- Interno: sem checagem de papel (usado pelo cron, onde auth.uid()
-- é null). O acesso do usuário passa pelo wrapper rh_anonimizar_*.
CREATE OR REPLACE FUNCTION public.fn_anonimizar_candidato(
  p_candidato_id uuid, p_motivo text DEFAULT 'solicitacao_titular')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_org uuid;
BEGIN
  SELECT organization_id INTO v_org
  FROM public.candidato WHERE id = p_candidato_id;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Candidato não encontrado';
  END IF;

  -- Dados estruturados extraídos e conversas
  DELETE FROM public.candidato_formacao    WHERE candidato_id = p_candidato_id;
  DELETE FROM public.candidato_experiencia WHERE candidato_id = p_candidato_id;
  DELETE FROM public.candidato_habilidade  WHERE candidato_id = p_candidato_id;
  DELETE FROM public.candidato_mensagem    WHERE candidato_id = p_candidato_id;

  -- Arquivos físicos no Storage: currículos (<id>/...) e documentos
  -- adicionais do candidato (candidatos/<id>/...)
  DELETE FROM storage.objects
   WHERE bucket_id = 'rh-curriculos'
     AND (storage.foldername(name))[1] = p_candidato_id::text;
  DELETE FROM storage.objects
   WHERE bucket_id = 'rh-documentos'
     AND (storage.foldername(name))[1] = 'candidatos'
     AND (storage.foldername(name))[2] = p_candidato_id::text;
  DELETE FROM public.candidato_curriculo WHERE candidato_id = p_candidato_id;

  -- Linha principal: remove todo PII, preserva o id para auditoria.
  -- deleted_at exclui do índice único de e-mail e das listagens (RLS).
  UPDATE public.candidato SET
    nome = 'Candidato anonimizado',
    email = 'anon+' || p_candidato_id::text || '@anonimizado.invalid',
    telefone = NULL, cidade = NULL, estado = NULL,
    area_interesse = NULL, cargo_pretendido = NULL, nivel = NULL,
    disponibilidade = NULL, pretensao_salarial = NULL, foto_url = NULL,
    resumo_executivo = NULL, score_completude = NULL,
    consentimento_ip = NULL, consentimento_user_agent = NULL,
    extracao = 'pendente',
    anonimizado_em = NOW(),
    deleted_at = COALESCE(deleted_at, NOW()),
    deleted_by = auth.uid(),
    updated_at = NOW()
  WHERE id = p_candidato_id;

  INSERT INTO public.candidato_historico
    (candidato_id, acao, detalhes, usuario_id)
  VALUES (p_candidato_id, 'anonimizado',
          jsonb_build_object('motivo', p_motivo), auth.uid());
END;
$$;
REVOKE ALL ON FUNCTION public.fn_anonimizar_candidato(uuid, text)
  FROM PUBLIC, anon, authenticated;

-- Wrapper com guarda de papel para uso pela aplicação (RH da própria org)
CREATE OR REPLACE FUNCTION public.rh_anonimizar_candidato(p_candidato_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT public.fn_is_rh() THEN
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
REVOKE ALL ON FUNCTION public.rh_anonimizar_candidato(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_anonimizar_candidato(uuid) TO authenticated;

-- ── 4. Expiração automática por retenção (S012) ──────────────
-- Anonimiza candidatos além do prazo de retenção da org, exceto os
-- contratados (viraram funcionários) e os já anonimizados.
CREATE OR REPLACE FUNCTION public.fn_rh_expirar_candidatos()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE r record; v_count int := 0;
BEGIN
  FOR r IN
    SELECT c.id
    FROM public.candidato c
    WHERE c.status <> 'contratado'
      AND c.anonimizado_em IS NULL
      AND c.created_at < NOW()
          - (public.fn_org_retencao_meses(c.organization_id) || ' months')::interval
  LOOP
    PERFORM public.fn_anonimizar_candidato(r.id, 'retencao_expirada');
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_rh_expirar_candidatos()
  FROM PUBLIC, anon, authenticated;

-- Agenda diária (03:00). Bloco tolerante à ausência de pg_cron:
-- habilite a extensão no dashboard e reexecute o cron.schedule.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('rh-lgpd-diario')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rh-lgpd-diario');
    PERFORM cron.schedule('rh-lgpd-diario', '0 3 * * *',
      $cron$ SELECT public.fn_rh_expirar_candidatos(); $cron$);
  ELSE
    RAISE NOTICE 'pg_cron não habilitado: agende rh-lgpd-diario manualmente após habilitar a extensão.';
  END IF;
END $$;
