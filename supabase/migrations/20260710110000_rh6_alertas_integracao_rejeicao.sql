-- ============================================================
-- RH-6 — Fecha as lacunas de Documentos:
--   S096      Notificação automática ao RH no vencimento (via rh_alerta)
--   S098      Rejeição de documento COM motivo
--   S092/RH-6.9  Documento enviado no onboarding vinculado ao repositório
--   (agenda o cron diário de vencimentos, antes ausente)
-- ============================================================

-- ── 1. Motivo de rejeição (S098) ─────────────────────────────
ALTER TABLE public.rh_documento
  ADD COLUMN IF NOT EXISTS motivo_rejeicao TEXT;

-- ── 2. Vínculo onboarding_item → documento (S092/RH-6.9) ─────
ALTER TABLE public.onboarding_item
  ADD COLUMN IF NOT EXISTS documento_id UUID
    REFERENCES public.rh_documento(id) ON DELETE SET NULL;

-- ── 3. Cron de vencimentos agora também alimenta rh_alerta (S096) ─
-- Além de reclassificar o status, insere um alerta (deduplicado por
-- chave que inclui o status alvo) para aparecer no Painel de Alertas,
-- que lê exclusivamente de rh_alerta.
CREATE OR REPLACE FUNCTION public.rh_atualizar_status_documentos()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  -- 1. válido → proximo_vencimento (faltam <= 30 dias)
  UPDATE public.rh_documento
     SET status = 'proximo_vencimento'
   WHERE status = 'valido'
     AND data_vencimento IS NOT NULL
     AND deleted_at IS NULL
     AND data_vencimento <= CURRENT_DATE + INTERVAL '30 days'
     AND data_vencimento >= CURRENT_DATE;

  -- 2. válido/proximo → vencido (data já passou)
  UPDATE public.rh_documento
     SET status = 'vencido'
   WHERE status IN ('valido', 'proximo_vencimento')
     AND data_vencimento IS NOT NULL
     AND deleted_at IS NULL
     AND data_vencimento < CURRENT_DATE;

  -- 3. Notificação ao RH (S096/RH-6.5): um alerta por documento e por
  -- status alvo. A chave inclui o status, então "vai vencer" e depois
  -- "venceu" geram avisos distintos, sem duplicar dentro do mesmo estado.
  INSERT INTO public.rh_alerta
    (organization_id, funcionario_id, tipo, titulo, mensagem, severidade, chave)
  SELECT d.organization_id, d.funcionario_id, 'documento_vencimento',
    CASE WHEN d.status = 'vencido'
         THEN 'Documento vencido'
         ELSE 'Documento próximo do vencimento' END,
    format('%s de %s %s em %s.',
           d.titulo, f.nome,
           CASE WHEN d.status = 'vencido' THEN 'venceu' ELSE 'vence' END,
           to_char(d.data_vencimento, 'DD/MM/YYYY')),
    'alerta',
    'doc_' || d.status || '_' || d.id::text
  FROM public.rh_documento d
  JOIN public.funcionario f ON f.id = d.funcionario_id
  WHERE d.status IN ('proximo_vencimento', 'vencido')
    AND d.deleted_at IS NULL
  ON CONFLICT (chave) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_atualizar_status_documentos()
  FROM PUBLIC, anon, authenticated;

-- Agenda diária (08:00) — antes a função existia mas não era agendada.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('rh-documentos-diario')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rh-documentos-diario');
    PERFORM cron.schedule('rh-documentos-diario', '0 8 * * *',
      $cron$ SELECT public.rh_atualizar_status_documentos(); $cron$);
  ELSE
    RAISE NOTICE 'pg_cron não habilitado: agende rh-documentos-diario manualmente após habilitar a extensão.';
  END IF;
END $$;

-- ── 4. Rejeição de documento com motivo (S098) ───────────────
CREATE OR REPLACE FUNCTION public.rh_rejeitar_documento(
  p_documento_id uuid, p_motivo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;
  IF COALESCE(trim(p_motivo), '') = '' THEN
    RAISE EXCEPTION 'Informe o motivo da rejeição';
  END IF;
  UPDATE public.rh_documento
     SET status = 'rejeitado', motivo_rejeicao = p_motivo, updated_at = NOW()
   WHERE id = p_documento_id
     AND organization_id = public.fn_current_org()
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Documento não encontrado';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_rejeitar_documento(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_rejeitar_documento(uuid, text) TO authenticated;

-- ── 5. Anexar documento a um item de onboarding (S092/RH-6.9) ─
-- O RH sobe o arquivo para o bucket rh-documentos (pasta <funcionario_id>/)
-- e chama esta RPC: cria a linha em rh_documento (repositório), vincula ao
-- item e o conclui numa transação. Assim o documento do checklist passa a
-- existir automaticamente no repositório do funcionário.
CREATE OR REPLACE FUNCTION public.rh_anexar_documento_onboarding(
  p_item_id uuid,
  p_storage_path text,
  p_titulo text,
  p_categoria public.rh_documento_categoria DEFAULT 'outro',
  p_data_vencimento date DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_func uuid;
  v_doc uuid;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Acesso restrito ao RH';
  END IF;

  SELECT funcionario_id INTO v_func
  FROM public.onboarding_item
  WHERE id = p_item_id AND organization_id = v_org;
  IF v_func IS NULL THEN
    RAISE EXCEPTION 'Item de onboarding não encontrado';
  END IF;

  INSERT INTO public.rh_documento
    (organization_id, funcionario_id, titulo, categoria, storage_path,
     data_vencimento, status, created_by)
  VALUES (v_org, v_func, p_titulo, p_categoria, p_storage_path,
          p_data_vencimento, 'valido', auth.uid())
  RETURNING id INTO v_doc;

  UPDATE public.onboarding_item
     SET documento_id = v_doc,
         status = 'concluido',
         concluido_em = NOW(),
         concluido_por = auth.uid()
   WHERE id = p_item_id;

  RETURN v_doc;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_anexar_documento_onboarding(
  uuid, text, text, public.rh_documento_categoria, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_anexar_documento_onboarding(
  uuid, text, text, public.rh_documento_categoria, date) TO authenticated;
