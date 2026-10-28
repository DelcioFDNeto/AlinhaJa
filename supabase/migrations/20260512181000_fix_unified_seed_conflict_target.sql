-- ============================================================================
-- Fix workflow seed ON CONFLICT ambiguity
-- ============================================================================
-- In PL/pgSQL, the return column channel_id from seed_base_workflow_channels
-- can make ON CONFLICT (channel_id, status) ambiguous. Recreate the function
-- using the explicit unique constraint name.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.seed_base_workflow_channels(
  p_reset_statuses BOOLEAN DEFAULT TRUE,
  p_preserve_operator_config BOOLEAN DEFAULT TRUE
)
RETURNS TABLE(channel_name TEXT, channel_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id UUID;
  v_ch_contas UUID;
  v_ch_fat_moto UUID;
  v_ch_emplacamento UUID;
  v_ch_fat_os UUID;
  v_ch_avisos UUID;
BEGIN
  SELECT id
  INTO v_owner_id
  FROM public.users
  WHERE COALESCE(is_active, TRUE) = TRUE
  ORDER BY
    CASE role_level::TEXT
      WHEN 'super_admin' THEN 1
      WHEN 'admin' THEN 2
      WHEN 'manager' THEN 3
      WHEN 'ti_admin' THEN 4
      ELSE 9
    END,
    created_at
  LIMIT 1;

  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum usuario ativo encontrado para criar os canais base.';
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS pg_temp.base_workflow_channels (
    name TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    metadata JSONB NOT NULL
  ) ON COMMIT DROP;

  TRUNCATE TABLE pg_temp.base_workflow_channels;

  INSERT INTO pg_temp.base_workflow_channels (name, description, metadata) VALUES
    (
      'Liberação Contas a Pagar',
      'Solicitações de contas a pagar. Operadores conferem, solicitantes respondem pendências e o financeiro conclui o pagamento.',
      '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"conta_pagar","category":"financeiro","color":"#2E7D32","icon":"payments_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::JSONB
    ),
    (
      'Liberação Fat Moto',
      'Solicitações de liberação/faturamento de motocicletas com conferência operacional e retorno ao solicitante quando necessário.',
      '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"fat_moto","category":"financeiro","color":"#7B1FA2","icon":"two_wheeler","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::JSONB
    ),
    (
      'Emplacamento',
      'Acompanhamento de emplacamento com dados do cliente, veículo, chassi, placa, filial, anexos e histórico de atendimento.',
      '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"emplacamento","category":"operacional","color":"#1565C0","icon":"directions_car_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::JSONB
    ),
    (
      'Faturamento OS/Peças',
      'Solicitações de faturamento de ordens de serviço e peças com conferência, correção e emissão final.',
      '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"faturamento_os","category":"faturamento","color":"#E65100","icon":"receipt_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::JSONB
    ),
    (
      'Avisos Gerais',
      'Comunicados gerais da empresa. Avisos, reuniões e atualizações corporativas.',
      '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"admins","card_type":"aviso","category":"informativo","color":"#C62828","icon":"campaign_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::JSONB
    );

  INSERT INTO public.chats (type, name, description, created_by, metadata)
  SELECT 'channel'::chat_type, b.name, b.description, v_owner_id, b.metadata
  FROM pg_temp.base_workflow_channels b
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.chats c
    WHERE c.type = 'channel'::chat_type
      AND c.name = b.name
  );

  UPDATE public.chats c
  SET description = b.description,
      created_by = COALESCE(c.created_by, v_owner_id),
      metadata = COALESCE(c.metadata, '{}'::JSONB)
        || b.metadata
        || CASE
          WHEN p_preserve_operator_config THEN jsonb_build_object(
            'assignment_mode', COALESCE(NULLIF(c.metadata->>'assignment_mode', ''), b.metadata->>'assignment_mode'),
            'operator_ids', CASE
              WHEN jsonb_typeof(c.metadata->'operator_ids') = 'array' THEN c.metadata->'operator_ids'
              ELSE COALESCE(b.metadata->'operator_ids', '[]'::JSONB)
            END,
            'default_operator_id', CASE
              WHEN c.metadata ? 'default_operator_id' THEN c.metadata->'default_operator_id'
              ELSE COALESCE(b.metadata->'default_operator_id', 'null'::JSONB)
            END,
            'operator_count', CASE
              WHEN jsonb_typeof(c.metadata->'operator_count') = 'number' THEN c.metadata->'operator_count'
              ELSE COALESCE(b.metadata->'operator_count', '0'::JSONB)
            END
          )
          ELSE '{}'::JSONB
        END
  FROM pg_temp.base_workflow_channels b
  WHERE c.type = 'channel'::chat_type
    AND c.name = b.name;

  SELECT id INTO v_ch_contas
  FROM public.chats
  WHERE type = 'channel'::chat_type AND name = 'Liberação Contas a Pagar'
  ORDER BY created_at
  LIMIT 1;

  SELECT id INTO v_ch_fat_moto
  FROM public.chats
  WHERE type = 'channel'::chat_type AND name = 'Liberação Fat Moto'
  ORDER BY created_at
  LIMIT 1;

  SELECT id INTO v_ch_emplacamento
  FROM public.chats
  WHERE type = 'channel'::chat_type AND name = 'Emplacamento'
  ORDER BY created_at
  LIMIT 1;

  SELECT id INTO v_ch_fat_os
  FROM public.chats
  WHERE type = 'channel'::chat_type AND name = 'Faturamento OS/Peças'
  ORDER BY created_at
  LIMIT 1;

  SELECT id INTO v_ch_avisos
  FROM public.chats
  WHERE type = 'channel'::chat_type AND name = 'Avisos Gerais'
  ORDER BY created_at
  LIMIT 1;

  INSERT INTO public.chat_members (chat_id, user_id, role)
  SELECT ch.channel_id, v_owner_id, 'owner'::member_role
  FROM (VALUES (v_ch_contas), (v_ch_fat_moto), (v_ch_emplacamento), (v_ch_fat_os), (v_ch_avisos)) ch(channel_id)
  WHERE ch.channel_id IS NOT NULL
  ON CONFLICT (chat_id, user_id) DO UPDATE SET role = 'owner'::member_role;

  INSERT INTO public.chat_members (chat_id, user_id, role)
  SELECT ch.channel_id, u.id, 'member'::member_role
  FROM (VALUES (v_ch_contas), (v_ch_fat_moto), (v_ch_emplacamento), (v_ch_fat_os), (v_ch_avisos)) ch(channel_id)
  CROSS JOIN public.users u
  WHERE ch.channel_id IS NOT NULL
    AND u.id <> v_owner_id
    AND COALESCE(u.is_active, TRUE) = TRUE
  ON CONFLICT (chat_id, user_id) DO NOTHING;

  IF p_reset_statuses THEN
    DELETE FROM workflow_status_config wsc
    WHERE wsc.channel_id IN (
      v_ch_contas,
      v_ch_fat_moto,
      v_ch_emplacamento,
      v_ch_fat_os,
      v_ch_avisos
    );
  END IF;

  INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final) VALUES
    (v_ch_contas, 'Novo', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_contas, 'Em análise', 2, '#F59E0B', 'search', FALSE),
    (v_ch_contas, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_contas, 'Liberado para Pagamento', 4, '#06B6D4', 'payments', FALSE),
    (v_ch_contas, 'Pago', 5, '#059669', 'task_alt', TRUE),

    (v_ch_fat_moto, 'Solicitação criada', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_fat_moto, 'Em conferência', 2, '#F59E0B', 'search', FALSE),
    (v_ch_fat_moto, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_fat_moto, 'Liberado', 4, '#10B981', 'check_circle', FALSE),
    (v_ch_fat_moto, 'Pendente de ajuste', 5, '#F97316', 'warning', FALSE),
    (v_ch_fat_moto, 'Finalizado', 6, '#059669', 'task_alt', TRUE),

    (v_ch_emplacamento, 'Solicitação aberta', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_emplacamento, 'Documentação em análise', 2, '#F59E0B', 'fact_check', FALSE),
    (v_ch_emplacamento, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_emplacamento, 'Aguardando pagamento/taxa', 4, '#F43F5E', 'payments', FALSE),
    (v_ch_emplacamento, 'Em processamento', 5, '#6366F1', 'sync', FALSE),
    (v_ch_emplacamento, 'Pendência documental', 6, '#EF4444', 'error_outline', FALSE),
    (v_ch_emplacamento, 'Emplacado', 7, '#10B981', 'task_alt', TRUE),

    (v_ch_fat_os, 'Aberto', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_fat_os, 'Em análise', 2, '#F59E0B', 'search', FALSE),
    (v_ch_fat_os, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_fat_os, 'Em faturamento', 4, '#6366F1', 'sync', FALSE),
    (v_ch_fat_os, 'Aguardando correção', 5, '#F97316', 'warning', FALSE),
    (v_ch_fat_os, 'Faturado', 6, '#10B981', 'task_alt', TRUE),

    (v_ch_avisos, 'Ativo', 1, '#3B82F6', 'publish', FALSE),
    (v_ch_avisos, 'Arquivado', 2, '#6B7280', 'archive', TRUE)
  ON CONFLICT ON CONSTRAINT workflow_status_config_channel_id_status_key DO UPDATE
  SET status_order = EXCLUDED.status_order,
      color = EXCLUDED.color,
      icon = EXCLUDED.icon,
      is_final = EXCLUDED.is_final;

  RETURN QUERY
  SELECT b.name, c.id
  FROM pg_temp.base_workflow_channels b
  JOIN public.chats c
    ON c.type = 'channel'::chat_type
   AND c.name = b.name
  ORDER BY b.name, c.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.seed_base_workflow_channels(BOOLEAN, BOOLEAN) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.seed_base_workflow_channels(BOOLEAN, BOOLEAN) TO service_role;
