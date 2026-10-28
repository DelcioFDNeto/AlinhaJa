-- ============================================================================
-- SEEDER: Canais principais do workspace Fluxy
-- ============================================================================
-- LEGADO: mantido para historico de migration. A fonte unica atual e:
--   20260512180000_unified_workflow_channel_seed.sql
-- Para execucao manual use:
--   supabase/scripts/create_base_channels.sql
-- ============================================================================
-- Seed idempotente alinhado ao fluxo atual de workflow:
-- - canais com metadata completa
-- - assignment_mode/operator_ids para gestão de operadores por canal
-- - etapas sem aprovação
-- - status final configurado por is_final
-- - "Cancelado" é ação/desvio do card, não coluna seedada
-- ============================================================================

DO $$
DECLARE
  v_owner_id UUID;
  v_ch_contas UUID;
  v_ch_fat_moto UUID;
  v_ch_emplacamento UUID;
  v_ch_fat_os UUID;
  v_ch_avisos UUID;
  v_user RECORD;
BEGIN
  SELECT id
  INTO v_owner_id
  FROM public.users
  WHERE COALESCE(is_active, TRUE) = TRUE
  ORDER BY
    CASE role_level
      WHEN 'super_admin' THEN 1
      WHEN 'admin' THEN 2
      WHEN 'manager' THEN 3
      WHEN 'ti_admin' THEN 4
      ELSE 9
    END,
    created_at
  LIMIT 1;

  -- Criar canais se ainda não existirem.
  INSERT INTO public.chats (type, name, description, created_by, metadata)
  SELECT 'channel', 'Liberação Contas a Pagar',
         'Solicitações de contas a pagar. Operadores conferem, solicitantes respondem pendências e o financeiro conclui o pagamento.',
         v_owner_id,
         '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"conta_pagar","category":"financeiro","color":"#2E7D32","icon":"payments_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE NOT EXISTS (SELECT 1 FROM public.chats WHERE name = 'Liberação Contas a Pagar');

  INSERT INTO public.chats (type, name, description, created_by, metadata)
  SELECT 'channel', 'Liberação Fat Moto',
         'Solicitações de liberação/faturamento de motocicletas com conferência operacional e retorno ao solicitante quando necessário.',
         v_owner_id,
         '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"fat_moto","category":"financeiro","color":"#7B1FA2","icon":"two_wheeler","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE NOT EXISTS (SELECT 1 FROM public.chats WHERE name = 'Liberação Fat Moto');

  INSERT INTO public.chats (type, name, description, created_by, metadata)
  SELECT 'channel', 'Emplacamento',
         'Acompanhamento de emplacamento com dados do cliente, veículo, chassi, placa, filial, anexos e histórico de atendimento.',
         v_owner_id,
         '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"emplacamento","category":"operacional","color":"#1565C0","icon":"directions_car_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE NOT EXISTS (SELECT 1 FROM public.chats WHERE name = 'Emplacamento');

  INSERT INTO public.chats (type, name, description, created_by, metadata)
  SELECT 'channel', 'Faturamento OS/Peças',
         'Solicitações de faturamento de ordens de serviço e peças com conferência, correção e emissão final.',
         v_owner_id,
         '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"faturamento_os","category":"faturamento","color":"#E65100","icon":"receipt_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE NOT EXISTS (SELECT 1 FROM public.chats WHERE name = 'Faturamento OS/Peças');

  INSERT INTO public.chats (type, name, description, created_by, metadata)
  SELECT 'channel', 'Avisos Gerais',
         'Comunicados gerais da empresa. Avisos, reuniões e atualizações corporativas.',
         v_owner_id,
         '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"admins","card_type":"aviso","category":"informativo","color":"#C62828","icon":"campaign_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE NOT EXISTS (SELECT 1 FROM public.chats WHERE name = 'Avisos Gerais');

  -- Atualizar metadata/descrição dos canais-base existentes.
  UPDATE public.chats
  SET description = 'Solicitações de contas a pagar. Operadores conferem, solicitantes respondem pendências e o financeiro conclui o pagamento.',
      metadata = COALESCE(metadata, '{}'::jsonb) || '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"conta_pagar","category":"financeiro","color":"#2E7D32","icon":"payments_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE name = 'Liberação Contas a Pagar';

  UPDATE public.chats
  SET description = 'Solicitações de liberação/faturamento de motocicletas com conferência operacional e retorno ao solicitante quando necessário.',
      metadata = COALESCE(metadata, '{}'::jsonb) || '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"fat_moto","category":"financeiro","color":"#7B1FA2","icon":"two_wheeler","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE name = 'Liberação Fat Moto';

  UPDATE public.chats
  SET description = 'Acompanhamento de emplacamento com dados do cliente, veículo, chassi, placa, filial, anexos e histórico de atendimento.',
      metadata = COALESCE(metadata, '{}'::jsonb) || '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"emplacamento","category":"operacional","color":"#1565C0","icon":"directions_car_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE name = 'Emplacamento';

  UPDATE public.chats
  SET description = 'Solicitações de faturamento de ordens de serviço e peças com conferência, correção e emissão final.',
      metadata = COALESCE(metadata, '{}'::jsonb) || '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"faturamento_os","category":"faturamento","color":"#E65100","icon":"receipt_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE name = 'Faturamento OS/Peças';

  UPDATE public.chats
  SET description = 'Comunicados gerais da empresa. Avisos, reuniões e atualizações corporativas.',
      metadata = COALESCE(metadata, '{}'::jsonb) || '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"admins","card_type":"aviso","category":"informativo","color":"#C62828","icon":"campaign_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE name = 'Avisos Gerais';

  SELECT id INTO v_ch_contas FROM public.chats WHERE name = 'Liberação Contas a Pagar' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_ch_fat_moto FROM public.chats WHERE name = 'Liberação Fat Moto' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_ch_emplacamento FROM public.chats WHERE name = 'Emplacamento' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_ch_fat_os FROM public.chats WHERE name = 'Faturamento OS/Peças' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_ch_avisos FROM public.chats WHERE name = 'Avisos Gerais' ORDER BY created_at LIMIT 1;

  IF v_owner_id IS NOT NULL THEN
    INSERT INTO public.chat_members (chat_id, user_id, role) VALUES
      (v_ch_contas, v_owner_id, 'owner'),
      (v_ch_fat_moto, v_owner_id, 'owner'),
      (v_ch_emplacamento, v_owner_id, 'owner'),
      (v_ch_fat_os, v_owner_id, 'owner'),
      (v_ch_avisos, v_owner_id, 'owner')
    ON CONFLICT (chat_id, user_id) DO UPDATE SET role = EXCLUDED.role;
  END IF;

  FOR v_user IN
    SELECT id FROM public.users WHERE COALESCE(is_active, TRUE) = TRUE
  LOOP
    INSERT INTO public.chat_members (chat_id, user_id, role) VALUES
      (v_ch_contas, v_user.id, CASE WHEN v_user.id = v_owner_id THEN 'owner' ELSE 'member' END),
      (v_ch_fat_moto, v_user.id, CASE WHEN v_user.id = v_owner_id THEN 'owner' ELSE 'member' END),
      (v_ch_emplacamento, v_user.id, CASE WHEN v_user.id = v_owner_id THEN 'owner' ELSE 'member' END),
      (v_ch_fat_os, v_user.id, CASE WHEN v_user.id = v_owner_id THEN 'owner' ELSE 'member' END),
      (v_ch_avisos, v_user.id, CASE WHEN v_user.id = v_owner_id THEN 'owner' ELSE 'member' END)
    ON CONFLICT (chat_id, user_id) DO NOTHING;
  END LOOP;

  DELETE FROM public.workflow_status_config
  WHERE channel_id IN (
    v_ch_contas,
    v_ch_fat_moto,
    v_ch_emplacamento,
    v_ch_fat_os,
    v_ch_avisos
  );

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
    (v_ch_avisos, 'Arquivado', 2, '#6B7280', 'archive', TRUE);

  RAISE NOTICE 'Seed de canais aplicado com fluxo operacional atual.';
END $$;
