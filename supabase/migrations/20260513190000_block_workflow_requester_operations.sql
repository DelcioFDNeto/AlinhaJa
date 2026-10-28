-- Impede que o solicitante opere o proprio card.
-- Ele continua podendo acompanhar/comentar e ver o resultado final, mas nao pode
-- assumir, atribuir, fixar, arquivar, cancelar, finalizar ou mover status.

DROP POLICY IF EXISTS "Membros atualizam cards" ON public.workflow_cards;
DROP POLICY IF EXISTS "Responsável atualiza cards" ON public.workflow_cards;

CREATE POLICY "Operadores e gestores atualizam cards"
  ON public.workflow_cards FOR UPDATE
  USING (
    requested_by IS DISTINCT FROM auth.uid()
    AND (
      assigned_to = auth.uid()
      OR (
        EXISTS (
          SELECT 1
          FROM public.users u
          WHERE u.id = auth.uid()
            AND COALESCE(u.is_active, TRUE) = TRUE
            AND u.role_level::TEXT IN ('super_admin', 'admin', 'manager')
        )
        AND EXISTS (
          SELECT 1
          FROM public.channel_members cm
          WHERE cm.channel_id = workflow_cards.channel_id
            AND cm.user_id = auth.uid()
        )
      )
    )
  )
  WITH CHECK (
    requested_by IS DISTINCT FROM auth.uid()
    AND assigned_to IS DISTINCT FROM requested_by
  );

CREATE OR REPLACE FUNCTION public.update_workflow_card_status(
  p_card_id UUID,
  p_new_status TEXT,
  p_observations TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_status TEXT;
  v_user_id UUID := auth.uid();
  v_role_level TEXT;
  v_assigned_to UUID;
  v_requested_by UUID;
  v_channel_id UUID;
  v_status_exists BOOLEAN;
  v_is_final_status BOOLEAN;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso negado: usuario nao autenticado.';
  END IF;

  SELECT role_level::TEXT INTO v_role_level
  FROM public.users
  WHERE id = v_user_id
    AND COALESCE(is_active, TRUE) = TRUE;

  SELECT status, assigned_to, requested_by, channel_id
  INTO v_old_status, v_assigned_to, v_requested_by, v_channel_id
  FROM public.workflow_cards
  WHERE id = p_card_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Card nao encontrado.';
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

  SELECT EXISTS (
    SELECT 1
    FROM public.workflow_status_config
    WHERE channel_id = v_channel_id
      AND status = p_new_status
      AND COALESCE(is_final, FALSE) = TRUE
  ) INTO v_is_final_status;

  IF v_requested_by = v_user_id THEN
    RAISE EXCEPTION 'Acesso negado: o solicitante nao pode operar o proprio card. Ele podera interagir apenas apos a conclusao.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.channel_members cm
    WHERE cm.channel_id = v_channel_id
      AND cm.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Acesso negado: usuario nao participa deste workspace.';
  END IF;

  IF COALESCE(v_role_level, 'member') = 'member'
     AND v_assigned_to IS DISTINCT FROM v_user_id THEN
    RAISE EXCEPTION 'Acesso negado: apenas o responsavel ou gestores podem alterar o status.';
  END IF;

  IF LOWER(p_new_status) = 'cancelado'
     AND COALESCE(v_role_level, 'member') = 'member'
     AND v_assigned_to IS DISTINCT FROM v_user_id THEN
    RAISE EXCEPTION 'Acesso negado: apenas o responsavel ou gestores podem cancelar o card.';
  END IF;

  UPDATE public.workflow_cards
  SET status = p_new_status,
      updated_at = NOW()
  WHERE id = p_card_id;

  INSERT INTO public.workflow_card_history (
    card_id, user_id, action, field_changed, old_value, new_value, observations
  )
  VALUES (
    p_card_id,
    v_user_id,
    CASE WHEN v_is_final_status THEN 'Card concluido' ELSE 'Status alterado' END,
    'status',
    v_old_status,
    p_new_status,
    p_observations
  );

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_workflow_card_status(UUID, TEXT, TEXT) TO authenticated;

DROP POLICY IF EXISTS "Membros inserem comentários" ON public.workflow_card_comments;
DROP POLICY IF EXISTS "Membros inserem comentarios" ON public.workflow_card_comments;

CREATE POLICY "Participantes inserem comentarios respeitando solicitante"
  ON public.workflow_card_comments FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.workflow_cards wc
      JOIN public.channel_members cm ON cm.channel_id = wc.channel_id
      WHERE wc.id = workflow_card_comments.card_id
        AND cm.user_id = auth.uid()
        AND (
          wc.requested_by IS DISTINCT FROM auth.uid()
          OR EXISTS (
            SELECT 1
            FROM public.workflow_status_config wsc
            WHERE wsc.channel_id = wc.channel_id
              AND wsc.status = wc.status
              AND COALESCE(wsc.is_final, FALSE) = TRUE
          )
        )
    )
  );
