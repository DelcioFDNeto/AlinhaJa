-- Remoção do fluxo de aprovação da diretoria
-- Execute este SQL no painel do Supabase (SQL Editor)

BEGIN;

-- 1. Remover a coluna approval_threshold da tabela workflow_cards
ALTER TABLE public.workflow_cards DROP COLUMN IF EXISTS approval_threshold;

-- 2. Atualizar a RPC update_workflow_card_status - RBAC mantido (solicitante/responsavel/gestor podem mover)
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
BEGIN
  v_user_id := auth.uid();
  
  SELECT role_level::TEXT INTO v_role_level FROM public.users WHERE id = v_user_id;
  
  SELECT status, assigned_to, requested_by INTO v_old_status, v_assigned_to, v_requested_by
  FROM public.workflow_cards WHERE id = p_card_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Card não encontrado';
  END IF;

  IF v_role_level = 'member' THEN
    IF (v_assigned_to IS DISTINCT FROM v_user_id) AND (v_requested_by IS DISTINCT FROM v_user_id) THEN
      RAISE EXCEPTION 'Acesso Negado: Apenas membros responsáveis pelo card ou gestores podem alterar seu status.';
    END IF;
  END IF;
  
  UPDATE public.workflow_cards
  SET status = p_new_status, updated_at = NOW()
  WHERE id = p_card_id;
  
  INSERT INTO public.workflow_card_history (card_id, user_id, action, field_changed, old_value, new_value, observations)
  VALUES (p_card_id, v_user_id, 'Status alterado', 'status', v_old_status, p_new_status, p_observations);
  
  RETURN TRUE;
END;
$$;

-- 3. Remover a RPC approve_workflow_card (não usada mais)
DROP FUNCTION IF EXISTS public.approve_workflow_card(uuid, boolean, text);

-- 4. Atualizar a RPC get_workflow_metrics para remover métricas de aprovação
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
        SELECT status, COUNT(*) as cnt FROM workflow_cards 
        WHERE channel_id = p_channel_id GROUP BY status
      ) t
    ),
    'total_amount', (SELECT COALESCE(SUM(amount), 0) FROM workflow_cards WHERE channel_id = p_channel_id)
  );
  RETURN result;
END;
$$;

COMMIT;