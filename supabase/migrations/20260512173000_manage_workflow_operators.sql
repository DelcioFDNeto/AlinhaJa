-- Permite que super_admin ou criador do canal defina quem e operador do workflow.

CREATE OR REPLACE FUNCTION public.update_workflow_operators(
  p_channel_id UUID,
  p_assignment_mode TEXT,
  p_operator_ids UUID[] DEFAULT ARRAY[]::UUID[],
  p_default_operator_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_created_by UUID;
  v_role_level TEXT;
  v_operator_ids UUID[] := COALESCE(p_operator_ids, ARRAY[]::UUID[]);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuario nao autenticado.';
  END IF;

  SELECT created_by
  INTO v_created_by
  FROM public.chats
  WHERE id = p_channel_id
    AND type = 'channel';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Canal nao encontrado.';
  END IF;

  SELECT role_level
  INTO v_role_level
  FROM public.users
  WHERE id = v_user_id;

  IF COALESCE(v_role_level, 'member') <> 'super_admin'
     AND v_created_by <> v_user_id THEN
    RAISE EXCEPTION 'Acesso Negado: apenas super_admin ou criador do canal pode gerenciar operadores.';
  END IF;

  IF p_assignment_mode NOT IN ('single_operator', 'operator_pool') THEN
    RAISE EXCEPTION 'Modo de atribuicao invalido.';
  END IF;

  IF p_assignment_mode = 'single_operator' AND p_default_operator_id IS NULL THEN
    RAISE EXCEPTION 'Canal com operador unico exige operador padrao.';
  END IF;

  IF p_assignment_mode = 'operator_pool' AND array_length(v_operator_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'Canal com equipe exige ao menos um operador.';
  END IF;

  IF p_default_operator_id IS NOT NULL
     AND NOT p_default_operator_id = ANY(v_operator_ids) THEN
    v_operator_ids := array_append(v_operator_ids, p_default_operator_id);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(v_operator_ids) AS operator_candidate(user_id)
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.chat_members cm
      WHERE cm.chat_id = p_channel_id
        AND cm.user_id = operator_candidate.user_id
    )
  ) THEN
    RAISE EXCEPTION 'Todos os operadores precisam ser membros do canal.';
  END IF;

  UPDATE public.chats
  SET metadata = COALESCE(metadata, '{}'::JSONB)
      || jsonb_build_object(
        'assignment_mode', p_assignment_mode,
        'operator_ids', COALESCE(to_jsonb(v_operator_ids), '[]'::JSONB),
        'default_operator_id',
          CASE
            WHEN p_assignment_mode = 'single_operator'
            THEN p_default_operator_id::TEXT
            ELSE NULL
          END,
        'operator_count', COALESCE(array_length(v_operator_ids, 1), 0)
      )
  WHERE id = p_channel_id;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_workflow_operators(UUID, TEXT, UUID[], UUID) TO authenticated;
