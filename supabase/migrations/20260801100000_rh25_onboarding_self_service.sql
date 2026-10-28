-- ============================================================
-- RH-25 / Fase 8 — Onboarding self-service
-- (PLANO-RH-COMPLETO.md, seção 11: "o funcionário vinculado executa
-- checklists no próprio app").
--
-- Até aqui o checklist só existia do lado do RH. Esta migration abre
-- a leitura do PRÓPRIO onboarding para o funcionário vinculado (F1.2)
-- e cria uma RPC restrita para ele concluir os itens que são
-- responsabilidade dele (responsavel = 'funcionario').
--
-- O que o funcionário NÃO pode: mexer em item de RH/gestor, marcar
-- 'nao_aplicavel' (dispensa é decisão do RH) ou concluir a execução.
--
-- Migration 100% aditiva (só policies + funções novas).
-- ============================================================

-- ── 1. Leitura do próprio onboarding ─────────────────────────
-- fn_is_own_funcionario (rh21) já valida vínculo + organização.
DROP POLICY IF EXISTS "Funcionário lê próprio onboarding" ON public.onboarding_execucao;
CREATE POLICY "Funcionário lê próprio onboarding"
  ON public.onboarding_execucao FOR SELECT
  USING (public.fn_is_own_funcionario(funcionario_id));

DROP POLICY IF EXISTS "Funcionário lê próprios itens" ON public.onboarding_item;
CREATE POLICY "Funcionário lê próprios itens"
  ON public.onboarding_item FOR SELECT
  USING (public.fn_is_own_funcionario(funcionario_id));

-- Nada de policy de UPDATE: a escrita do funcionário passa pela RPC
-- abaixo, que restringe o item e os status permitidos.

-- ── 2. Funcionário conclui/reabre item que é dele ────────────
CREATE OR REPLACE FUNCTION public.rh_meu_item_onboarding(
  p_item_id   uuid,
  p_concluido boolean,
  p_observacao text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_item public.onboarding_item%ROWTYPE;
  v_exec_status public.onboarding_status;
BEGIN
  SELECT * INTO v_item
    FROM public.onboarding_item
   WHERE id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Item não encontrado';
  END IF;
  IF NOT public.fn_is_own_funcionario(v_item.funcionario_id) THEN
    RAISE EXCEPTION 'Este item não é do seu onboarding';
  END IF;
  IF v_item.responsavel <> 'funcionario' THEN
    RAISE EXCEPTION 'Este item é responsabilidade do %, não sua', v_item.responsavel;
  END IF;
  -- Item já dispensado pelo RH não volta para o fluxo do funcionário.
  IF v_item.status = 'nao_aplicavel' THEN
    RAISE EXCEPTION 'Este item foi dispensado pelo RH';
  END IF;

  SELECT status INTO v_exec_status
    FROM public.onboarding_execucao
   WHERE id = v_item.execucao_id;
  IF v_exec_status <> 'em_andamento' THEN
    RAISE EXCEPTION 'Este onboarding já foi finalizado';
  END IF;

  UPDATE public.onboarding_item
     SET status       = CASE WHEN p_concluido THEN 'concluido'::public.onboarding_item_status
                             ELSE 'pendente'::public.onboarding_item_status END,
         observacao   = COALESCE(NULLIF(trim(COALESCE(p_observacao, '')), ''), observacao),
         concluido_em  = CASE WHEN p_concluido THEN NOW() ELSE NULL END,
         concluido_por = CASE WHEN p_concluido THEN auth.uid() ELSE NULL END
   WHERE id = p_item_id;

  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_item.organization_id, auth.uid(), 'onboarding_item_self_service',
          jsonb_build_object('item_id', p_item_id,
                             'titulo', v_item.titulo,
                             'concluido', p_concluido));
END;
$$;
REVOKE ALL ON FUNCTION public.rh_meu_item_onboarding(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_meu_item_onboarding(uuid, boolean, text) TO authenticated;

-- ── 3. Recalcula o progresso quando o item muda ──────────────
-- O progresso era calculado só nas RPCs de RH; com o funcionário
-- mexendo nos itens, a barra precisa acompanhar. Trigger cobre as duas
-- origens de escrita de uma vez.
CREATE OR REPLACE FUNCTION public.fn_tg_onboarding_progresso()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_exec uuid := COALESCE(NEW.execucao_id, OLD.execucao_id);
  v_total int;
  v_feitos int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE status <> 'pendente')
    INTO v_total, v_feitos
    FROM public.onboarding_item
   WHERE execucao_id = v_exec;

  UPDATE public.onboarding_execucao
     SET progresso  = CASE WHEN v_total = 0 THEN 0
                           ELSE round((v_feitos::numeric * 100) / v_total) END,
         updated_at = NOW()
   WHERE id = v_exec;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_onboarding_progresso ON public.onboarding_item;
CREATE TRIGGER trg_onboarding_progresso
  AFTER INSERT OR UPDATE OF status OR DELETE ON public.onboarding_item
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_onboarding_progresso();

-- ── 4. Pendências do funcionário (badge da tela) ─────────────
-- security_invoker: a policy do item 1 já limita cada um ao que é seu.
CREATE OR REPLACE VIEW public.rh_meu_onboarding_pendente
WITH (security_invoker = true) AS
SELECT
  i.execucao_id,
  i.organization_id,
  i.funcionario_id,
  count(*)                                        AS pendentes,
  count(*) FILTER (WHERE i.obrigatorio)           AS pendentes_obrigatorios,
  count(*) FILTER (WHERE i.prazo < CURRENT_DATE)  AS atrasados
FROM public.onboarding_item i
JOIN public.onboarding_execucao e ON e.id = i.execucao_id
WHERE i.responsavel = 'funcionario'
  AND i.status = 'pendente'
  AND e.status = 'em_andamento'
GROUP BY i.execucao_id, i.organization_id, i.funcionario_id;
