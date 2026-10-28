-- Completa a remocao do fluxo de aprovacao no Workflow e corrige Emplacamento.

BEGIN;

-- Emplacamento: o app grava e le este campo no card.
ALTER TABLE public.workflow_cards
  ADD COLUMN IF NOT EXISTS branch TEXT;

-- Mantem compatibilidade com bancos que ainda tenham a coluna da fase de aprovacao.
ALTER TABLE public.workflow_cards
  DROP COLUMN IF EXISTS approval_threshold;

-- Remove a RPC de aprovacao se ainda existir.
DROP FUNCTION IF EXISTS public.approve_workflow_card(uuid, boolean, text);

-- Converte etapas antigas de aprovacao para etapas operacionais.
UPDATE public.workflow_cards
SET status = 'Aguardando Solicitante'
WHERE status = 'Aguardando aprovação';

UPDATE public.workflow_cards
SET status = 'Liberado para Pagamento'
WHERE status = 'Aprovado';

UPDATE public.workflow_cards
SET status = 'Cancelado'
WHERE status = 'Rejeitado';

UPDATE public.workflow_status_config
SET status = 'Aguardando Solicitante',
    color = '#8B5CF6',
    icon = 'hourglass_empty',
    is_final = FALSE
WHERE status = 'Aguardando aprovação';

UPDATE public.workflow_status_config
SET status = 'Liberado para Pagamento',
    color = '#06B6D4',
    icon = 'payments',
    is_final = FALSE
WHERE status = 'Aprovado';

UPDATE public.workflow_status_config
SET status = 'Cancelado',
    color = '#EF4444',
    icon = 'cancel',
    is_final = FALSE
WHERE status = 'Rejeitado';

-- Se a conversao criou etapas duplicadas no mesmo canal, mantem a primeira.
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY channel_id, status
           ORDER BY status_order, id
         ) AS rn
  FROM public.workflow_status_config
)
DELETE FROM public.workflow_status_config wsc
USING ranked r
WHERE wsc.id = r.id
  AND r.rn > 1;

-- Reordena as etapas restantes de cada canal para manter o board consistente.
WITH ordered AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY channel_id
           ORDER BY status_order, id
         ) AS new_order
  FROM public.workflow_status_config
)
UPDATE public.workflow_status_config wsc
SET status_order = ordered.new_order
FROM ordered
WHERE wsc.id = ordered.id;

CREATE OR REPLACE FUNCTION public.update_workflow_card_status(
  p_card_id UUID,
  p_new_status TEXT,
  p_observations TEXT DEFAULT NULL
)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_old_status TEXT;
  v_user_id UUID;
  v_role_level TEXT;
  v_assigned_to UUID;
  v_requested_by UUID;
  v_channel_id UUID;
  v_status_exists BOOLEAN;
BEGIN
  v_user_id := auth.uid();

  SELECT role_level::TEXT INTO v_role_level
  FROM public.users
  WHERE id = v_user_id;

  SELECT status, assigned_to, requested_by, channel_id
  INTO v_old_status, v_assigned_to, v_requested_by, v_channel_id
  FROM public.workflow_cards
  WHERE id = p_card_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Card nao encontrado';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.workflow_status_config
    WHERE channel_id = v_channel_id
      AND status = p_new_status
  ) INTO v_status_exists;

  IF NOT v_status_exists AND LOWER(p_new_status) <> 'cancelado' THEN
    RAISE EXCEPTION 'Status nao configurado neste workflow: %', p_new_status;
  END IF;

  IF v_role_level = 'member' THEN
    IF (v_assigned_to IS DISTINCT FROM v_user_id) AND (v_requested_by IS DISTINCT FROM v_user_id) THEN
      RAISE EXCEPTION 'Acesso negado: apenas responsaveis, solicitantes ou gestores podem alterar o status.';
    END IF;
  END IF;

  UPDATE public.workflow_cards
  SET status = p_new_status,
      updated_at = NOW()
  WHERE id = p_card_id;

  INSERT INTO public.workflow_card_history (
    card_id, user_id, action, field_changed, old_value, new_value, observations
  )
  VALUES (
    p_card_id, v_user_id, 'Status alterado', 'status', v_old_status, p_new_status, p_observations
  );

  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_workflow_metrics(p_channel_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  result JSONB;
BEGIN
  result := jsonb_build_object(
    'total_cards', (SELECT COUNT(*) FROM workflow_cards WHERE channel_id = p_channel_id),
    'by_status', (
      SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb)
      FROM (
        SELECT status, COUNT(*) as cnt
        FROM workflow_cards
        WHERE channel_id = p_channel_id
        GROUP BY status
      ) t
    ),
    'total_amount', (SELECT COALESCE(SUM(amount), 0) FROM workflow_cards WHERE channel_id = p_channel_id)
  );
  RETURN result;
END;
$$;

COMMIT;
