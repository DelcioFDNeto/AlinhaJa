-- ==============================================================================
-- RESET OPERACIONAL + RESEED DE CANAIS
-- ==============================================================================
-- LEGADO: para execucao manual atual, prefira:
--   supabase/scripts/reset_and_seed_operational_data.sql
-- A fonte unica atual e a migration 20260512180000_unified_workflow_channel_seed.sql.
-- ==============================================================================
-- Limpa TODOS os dados transacionais preservando usuários, departamentos e
-- posições de trabalho. Depois recria os 5 canais principais com status configs.
-- ==============================================================================

-- ══════════════════════════════════════════════════════════════════════════════
-- PARTE 1: RESET OPERACIONAL
-- ══════════════════════════════════════════════════════════════════════════════

-- 1. Mensagens e ações de mensagem
TRUNCATE TABLE public.message_actions CASCADE;
TRUNCATE TABLE public.messages CASCADE;

-- 2. Workflow (cards + comentários)
TRUNCATE TABLE public.workflow_card_comments CASCADE;
TRUNCATE TABLE public.workflow_cards CASCADE;

-- 3. Workflow status config (será recriado no seed)
TRUNCATE TABLE public.workflow_status_config CASCADE;

-- 4. Reuniões e transcrições
TRUNCATE TABLE public.meeting_transcriptions CASCADE;
TRUNCATE TABLE public.meetings CASCADE;

-- 5. Chamadas
TRUNCATE TABLE public.calls CASCADE;

-- 6. Chats e membros (DMs, grupos, canais)
TRUNCATE TABLE public.chat_members CASCADE;
TRUNCATE TABLE public.chats CASCADE;

-- 7. Notificações e preferências por chat
TRUNCATE TABLE public.user_notification_preferences CASCADE;

-- 8. Tickets de suporte
TRUNCATE TABLE public.support_ticket_messages CASCADE;
TRUNCATE TABLE public.support_tickets CASCADE;

-- 9. Histórico de atividade
TRUNCATE TABLE public.user_activity_history CASCADE;

-- ══════════════════════════════════════════════════════════════════════════════
-- PARTE 2: SEED DOS CANAIS PRINCIPAIS
-- ══════════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_owner_id UUID := '00000000-0000-0000-0000-111111111111'; -- TI Administrador
  v_ch_contas UUID;
  v_ch_fat_moto UUID;
  v_ch_emplacamento UUID;
  v_ch_fat_os UUID;
  v_ch_avisos UUID;
  v_user RECORD;
BEGIN

  -- ============================================================
  -- CRIAR CANAIS
  -- ============================================================

  INSERT INTO public.chats (type, name, description, created_by, metadata)
  VALUES ('channel', 'Liberação Contas a Pagar', 'Solicitações de contas a pagar. Operadores conferem, solicitantes respondem pendências e o financeiro conclui o pagamento.', v_owner_id, '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"conta_pagar","category":"financeiro","color":"#2E7D32","icon":"payments_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb)
  RETURNING id INTO v_ch_contas;

  INSERT INTO public.chats (type, name, description, created_by, metadata)
  VALUES ('channel', 'Liberação Fat Moto', 'Solicitações de liberação/faturamento de motocicletas com conferência operacional e retorno ao solicitante quando necessário.', v_owner_id, '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"fat_moto","category":"financeiro","color":"#7B1FA2","icon":"two_wheeler","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb)
  RETURNING id INTO v_ch_fat_moto;

  INSERT INTO public.chats (type, name, description, created_by, metadata)
  VALUES ('channel', 'Emplacamento', 'Acompanhamento de emplacamento com dados do cliente, veículo, chassi, placa, filial, anexos e histórico de atendimento.', v_owner_id, '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"emplacamento","category":"operacional","color":"#1565C0","icon":"directions_car_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb)
  RETURNING id INTO v_ch_emplacamento;

  INSERT INTO public.chats (type, name, description, created_by, metadata)
  VALUES ('channel', 'Faturamento OS/Peças', 'Solicitações de faturamento de ordens de serviço e peças com conferência, correção e emissão final.', v_owner_id, '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"faturamento_os","category":"faturamento","color":"#E65100","icon":"receipt_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb)
  RETURNING id INTO v_ch_fat_os;

  INSERT INTO public.chats (type, name, description, created_by, metadata)
  VALUES ('channel', 'Avisos Gerais', 'Comunicados gerais da empresa. Avisos, reuniões e atualizações corporativas.', v_owner_id, '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"admins","card_type":"aviso","category":"informativo","color":"#C62828","icon":"campaign_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb)
  RETURNING id INTO v_ch_avisos;

  RAISE NOTICE 'Canais criados: Contas=%, FatMoto=%, Emplacamento=%, FatOS=%, Avisos=%',
    v_ch_contas, v_ch_fat_moto, v_ch_emplacamento, v_ch_fat_os, v_ch_avisos;

  -- ============================================================
  -- ADICIONAR MEMBROS (Todos os usuários ativos)
  -- ============================================================

  -- Owner em todos os canais
  INSERT INTO public.chat_members (chat_id, user_id, role) VALUES
    (v_ch_contas, v_owner_id, 'owner'),
    (v_ch_fat_moto, v_owner_id, 'owner'),
    (v_ch_emplacamento, v_owner_id, 'owner'),
    (v_ch_fat_os, v_owner_id, 'owner'),
    (v_ch_avisos, v_owner_id, 'owner')
  ON CONFLICT (chat_id, user_id) DO NOTHING;

  -- Todos os outros usuários como membros
  FOR v_user IN SELECT id FROM public.users WHERE id != v_owner_id LOOP
    INSERT INTO public.chat_members (chat_id, user_id, role) VALUES
      (v_ch_contas, v_user.id, 'member'),
      (v_ch_fat_moto, v_user.id, 'member'),
      (v_ch_emplacamento, v_user.id, 'member'),
      (v_ch_fat_os, v_user.id, 'member'),
      (v_ch_avisos, v_user.id, 'member')
    ON CONFLICT (chat_id, user_id) DO NOTHING;
  END LOOP;

  -- ============================================================
  -- STATUS CONFIG DO WORKFLOW POR CANAL
  -- ============================================================

  -- ── Liberação Contas a Pagar ──
  INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final) VALUES
    (v_ch_contas, 'Solicitação aberta', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_contas, 'Em análise', 2, '#F59E0B', 'search', FALSE),
    (v_ch_contas, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_contas, 'Liberado para Pagamento', 4, '#06B6D4', 'payments', FALSE),
    (v_ch_contas, 'Pago', 5, '#059669', 'task_alt', TRUE);

  -- ── Liberação Fat Moto ──
  INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final) VALUES
    (v_ch_fat_moto, 'Solicitação criada', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_fat_moto, 'Em conferência', 2, '#F59E0B', 'search', FALSE),
    (v_ch_fat_moto, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_fat_moto, 'Liberado', 4, '#10B981', 'check_circle', FALSE),
    (v_ch_fat_moto, 'Pendente de ajuste', 5, '#F97316', 'warning', FALSE),
    (v_ch_fat_moto, 'Finalizado', 6, '#059669', 'task_alt', TRUE);

  -- ── Emplacamento ──
  INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final) VALUES
    (v_ch_emplacamento, 'Solicitação aberta', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_emplacamento, 'Documentação em análise', 2, '#F59E0B', 'fact_check', FALSE),
    (v_ch_emplacamento, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_emplacamento, 'Aguardando pagamento/taxa', 4, '#F43F5E', 'payments', FALSE),
    (v_ch_emplacamento, 'Em processamento', 5, '#6366F1', 'sync', FALSE),
    (v_ch_emplacamento, 'Pendência documental', 6, '#EF4444', 'error_outline', FALSE),
    (v_ch_emplacamento, 'Emplacado', 7, '#10B981', 'check_circle', TRUE);

  -- ── Faturamento OS/Peças ──
  INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final) VALUES
    (v_ch_fat_os, 'Aberto', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_fat_os, 'Em análise', 2, '#F59E0B', 'pending', FALSE),
    (v_ch_fat_os, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_fat_os, 'Em faturamento', 4, '#6366F1', 'sync', FALSE),
    (v_ch_fat_os, 'Aguardando correção', 5, '#F97316', 'warning', FALSE),
    (v_ch_fat_os, 'Faturado', 6, '#10B981', 'check_circle', TRUE);

  -- ── Avisos Gerais ──
  INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final) VALUES
    (v_ch_avisos, 'Ativo', 1, '#3B82F6', 'publish', FALSE),
    (v_ch_avisos, 'Arquivado', 2, '#6B7280', 'archive', TRUE);

  RAISE NOTICE '============================================================';
  RAISE NOTICE 'RESET + SEED COMPLETO! 5 Workspaces recriados com sucesso.';
  RAISE NOTICE '============================================================';

END $$;
