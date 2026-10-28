-- ============================================================
-- RH-13 / Fase 5 — Pipeline avançado (parte 1: responsável + SLA)
-- (PLANO-RH-COMPLETO.md, Onda 5).
--
-- Aditiva e de baixo risco: responsável pelo candidato (+ filtro
-- "meus candidatos") e carimbo de tempo na etapa (status_changed_at)
-- para o SLA "parado há > N dias". As etapas customizáveis por org
-- (data-driven) ficam para uma etapa seguinte — aqui o funil segue
-- em CandidateStatus, sem refactor arriscado.
-- ============================================================

-- ── 1. Responsável pelo candidato ────────────────────────────
ALTER TABLE public.candidato
  ADD COLUMN IF NOT EXISTS responsavel_id UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS status_changed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_candidato_responsavel
  ON public.candidato(organization_id, responsavel_id)
  WHERE deleted_at IS NULL AND responsavel_id IS NOT NULL;

-- ── 2. Backfill do carimbo de etapa ──────────────────────────
-- Última mudança de status registrada no histórico; se nunca mudou,
-- usa a data de criação. Idempotente (só preenche o que está NULL).
UPDATE public.candidato c
SET status_changed_at = COALESCE(
  (SELECT max(h.created_at) FROM public.candidato_historico h
    WHERE h.candidato_id = c.id AND h.acao = 'mudanca_status'),
  c.created_at)
WHERE c.status_changed_at IS NULL;

ALTER TABLE public.candidato
  ALTER COLUMN status_changed_at SET DEFAULT NOW();

-- ── 3. Trigger de status também carimba status_changed_at ────
-- Recria a guarda de transição (mesma lógica) adicionando o carimbo
-- de tempo na etapa quando o status muda.
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
      RAISE EXCEPTION 'Candidato descartado só pode ser reativado como novo';
    ELSIF NEW.status <> 'descartado' AND OLD.status <> 'descartado'
      AND (v_ordem->>NEW.status::text)::int < (v_ordem->>OLD.status::text)::int THEN
      RAISE EXCEPTION 'Transição retroativa de status não permitida (% → %)',
        OLD.status, NEW.status;
    END IF;
    NEW.status_changed_at := NOW();  -- SLA: reinicia o relógio da etapa
    INSERT INTO public.candidato_historico (candidato_id, acao, detalhes, usuario_id)
    VALUES (NEW.id, 'mudanca_status',
            jsonb_build_object('de', OLD.status, 'para', NEW.status),
            auth.uid());
  END IF;
  RETURN NEW;
END;
$$;

-- ── 4. Atribuição de responsável em lote (ações em massa) ────
-- Guard RH + mesma org; devolve quantos foram atualizados.
-- p_responsavel NULL desatribui.
CREATE OR REPLACE FUNCTION public.rh_atribuir_responsavel(
  p_ids uuid[], p_responsavel uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_count integer;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Apenas o RH pode atribuir responsáveis';
  END IF;
  -- Responsável (quando informado) precisa ser da mesma org.
  IF p_responsavel IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = p_responsavel AND u.organization_id = v_org) THEN
    RAISE EXCEPTION 'Responsável não pertence à organização';
  END IF;

  UPDATE public.candidato
     SET responsavel_id = p_responsavel, updated_by = auth.uid()
   WHERE id = ANY(p_ids)
     AND organization_id = v_org
     AND deleted_at IS NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_atribuir_responsavel(uuid[], uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_atribuir_responsavel(uuid[], uuid) TO authenticated;
