-- ==============================================================================
-- Workflow RBAC - Proteção das RPCs e RLS baseada em Nível de Acesso
-- ==============================================================================

-- 1. Substituir a RPC update_workflow_card_status
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
  
  -- Buscar o cargo global do usuário
  SELECT role_level::TEXT INTO v_role_level FROM public.users WHERE id = v_user_id;
  
  -- Buscar dados do card
  SELECT status, assigned_to, requested_by INTO v_old_status, v_assigned_to, v_requested_by
  FROM public.workflow_cards WHERE id = p_card_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Card não encontrado';
  END IF;

  -- Regra RBAC: Se for member, DEVE ser o responsável ou o criador do card.
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

-- 2. Substituir a RPC approve_workflow_card
CREATE OR REPLACE FUNCTION public.approve_workflow_card(
  p_card_id UUID,
  p_approve BOOLEAN,
  p_observations TEXT DEFAULT NULL
)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_role_level TEXT;
BEGIN
  v_user_id := auth.uid();
  
  -- Buscar o cargo global do usuário
  SELECT role_level::TEXT INTO v_role_level FROM public.users WHERE id = v_user_id;

  -- Regra RBAC: Apenas cargos de gestão podem aprovar cards
  IF v_role_level = 'member' THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas líderes e gestores têm permissão para aprovar ou rejeitar cards.';
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
$$;

-- 3. Atualizar a Política RLS 'Responsável atualiza cards'
DROP POLICY IF EXISTS "Responsável atualiza cards" ON public.workflow_cards;
CREATE POLICY "Responsável atualiza cards"
  ON public.workflow_cards FOR UPDATE
  USING (
    -- Regra 1: Usuário é o criador ou responsável
    assigned_to = auth.uid() OR
    requested_by = auth.uid() OR
    -- Regra 2: Usuário é um Gestor/Admin no sistema (role_level) e está no canal
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role_level IN ('super_admin', 'admin', 'manager', 'director', 'ti_admin')
    ) AND EXISTS (
      SELECT 1 FROM public.chat_members cm
      WHERE cm.chat_id = channel_id AND cm.user_id = auth.uid()
    )
  );

