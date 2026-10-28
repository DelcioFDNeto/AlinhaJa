-- FASE 2: Fluxo de Aprovação

-- Adicionar o limite de aprovação na tabela de cards (valor a partir do qual exige diretoria)
ALTER TABLE public.workflow_cards 
ADD COLUMN IF NOT EXISTS approval_threshold NUMERIC(15,2);

-- Atualizar o RPC de aprovação para validar o threshold
CREATE OR REPLACE FUNCTION public.approve_workflow_card(p_card_id uuid, p_approve boolean, p_observations text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_user_id UUID;
  v_role_level TEXT;
  v_amount NUMERIC;
  v_threshold NUMERIC;
BEGIN
  v_user_id := auth.uid();
  
  -- Buscar o cargo global do usuário
  SELECT role_level::TEXT INTO v_role_level FROM public.users WHERE id = v_user_id;

  -- Regra RBAC Básica
  IF v_role_level = 'member' THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas líderes e gestores têm permissão para aprovar ou rejeitar cards.';
  END IF;

  -- Regra RBAC Financeira (Threshold)
  SELECT amount, approval_threshold INTO v_amount, v_threshold 
  FROM public.workflow_cards WHERE id = p_card_id;

  IF v_threshold IS NOT NULL AND v_amount > v_threshold THEN
    IF v_role_level NOT IN ('director', 'admin', 'sysadmin') THEN
      RAISE EXCEPTION 'Acesso Negado: Operações acima de R$ % exigem aprovação da Diretoria.', v_threshold;
    END IF;
  END IF;
  
  UPDATE public.workflow_cards
  SET 
    approval_status = CASE WHEN p_approve THEN 'approved'::workflow_approval_status ELSE 'rejected'::workflow_approval_status END,
    approved_by = v_user_id,
    approval_date = NOW(),
    approval_observations = p_observations,
    updated_at = NOW()
  WHERE id = p_card_id;
  
  INSERT INTO public.workflow_card_history (card_id, user_id, action, new_value, observations)
  VALUES (
    p_card_id, v_user_id, 
    CASE WHEN p_approve THEN 'Aprovado' ELSE 'Rejeitado' END,
    CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
    p_observations
  );
  
  RETURN TRUE;
END;
$function$;

-- FASE 4: RPC Dashboard Analytics
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
    'approved', (SELECT COUNT(*) FROM workflow_cards WHERE channel_id = p_channel_id AND approval_status = 'approved'),
    'rejected', (SELECT COUNT(*) FROM workflow_cards WHERE channel_id = p_channel_id AND approval_status = 'rejected'),
    'total_amount', (SELECT COALESCE(SUM(amount), 0) FROM workflow_cards WHERE channel_id = p_channel_id)
  );
  RETURN result;
END;
$$;
