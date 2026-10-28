-- Configuracao flexivel de operadores por canal de workflow.
-- Canais antigos seguem funcionando: sem operator_ids, qualquer membro pode assumir.

CREATE OR REPLACE FUNCTION public.claim_workflow_card(
  p_card_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_channel_id UUID;
  v_assigned_to UUID;
  v_requested_by UUID;
  v_status TEXT;
  v_channel_metadata JSONB;
  v_assignment_mode TEXT;
  v_default_operator_id TEXT;
  v_operator_ids JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuario nao autenticado.';
  END IF;

  SELECT wc.channel_id,
         wc.assigned_to,
         wc.requested_by,
         wc.status,
         COALESCE(c.metadata, '{}'::JSONB)
  INTO v_channel_id,
       v_assigned_to,
       v_requested_by,
       v_status,
       v_channel_metadata
  FROM public.workflow_cards wc
  JOIN public.chats c ON c.id = wc.channel_id
  WHERE wc.id = p_card_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Card nao encontrado.';
  END IF;

  IF LOWER(COALESCE(v_status, '')) = 'cancelado' THEN
    RAISE EXCEPTION 'Card cancelado nao pode ser assumido.';
  END IF;

  IF v_requested_by = v_user_id THEN
    RAISE EXCEPTION 'O solicitante nao deve assumir o proprio atendimento.';
  END IF;

  IF v_assigned_to IS NOT NULL AND v_assigned_to <> v_user_id THEN
    RAISE EXCEPTION 'Este card ja possui responsavel.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.chat_members cm
    WHERE cm.chat_id = v_channel_id
      AND cm.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: usuario nao participa deste workspace.';
  END IF;

  v_assignment_mode := COALESCE(
    NULLIF(v_channel_metadata->>'assignment_mode', ''),
    'operator_pool'
  );
  v_default_operator_id := NULLIF(v_channel_metadata->>'default_operator_id', '');
  v_operator_ids := v_channel_metadata->'operator_ids';

  IF v_assignment_mode = 'single_operator'
     AND v_default_operator_id IS NOT NULL
     AND v_default_operator_id <> v_user_id::TEXT THEN
    RAISE EXCEPTION 'Este canal possui operador unico configurado para assumir os cards.';
  END IF;

  IF jsonb_typeof(v_operator_ids) = 'array'
     AND jsonb_array_length(v_operator_ids) > 0
     AND NOT EXISTS (
       SELECT 1
       FROM jsonb_array_elements_text(v_operator_ids) AS operator_id(value)
       WHERE operator_id.value = v_user_id::TEXT
     ) THEN
    RAISE EXCEPTION 'Usuario nao esta configurado como operador deste workflow.';
  END IF;

  UPDATE public.workflow_cards
  SET assigned_to = v_user_id,
      updated_at = NOW()
  WHERE id = p_card_id;

  INSERT INTO public.workflow_card_history (
    card_id, user_id, action, field_changed, old_value, new_value, observations
  )
  VALUES (
    p_card_id,
    v_user_id,
    'Card assumido',
    'assigned_to',
    COALESCE(v_assigned_to::TEXT, ''),
    v_user_id::TEXT,
    'Operador assumiu o atendimento'
  );

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_workflow_card(UUID) TO authenticated;
