-- ==============================================================================
-- Migration 036: RPCs para Gestão de Canais e Workflow (AlinhaJá)
-- ==============================================================================

-- ==============================================================================
-- 1. RPC: Exclusão Total de Canal (Channel + Messages + Members + Workflow)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.delete_channel(p_channel_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- 1. Remove workflow cards relacionados ao canal
  DELETE FROM public.workflow_card_comments
  WHERE card_id IN (SELECT id FROM public.workflow_cards WHERE channel_id = p_channel_id);
  
  DELETE FROM public.workflow_card_history
  WHERE card_id IN (SELECT id FROM public.workflow_cards WHERE channel_id = p_channel_id);
  
  DELETE FROM public.workflow_cards
  WHERE channel_id = p_channel_id;
  
  -- 2. Remove configuração de status do workflow
  DELETE FROM public.workflow_status_config
  WHERE channel_id = p_channel_id;
  
  -- 3. Remove mensagens do canal
  DELETE FROM public.messages
  WHERE chat_id = p_channel_id;
  
  -- 4. Remove membros do canal
  DELETE FROM public.chat_members
  WHERE chat_id = p_channel_id;
  
  -- 5. Remove o canal
  DELETE FROM public.chats
  WHERE id = p_channel_id;
  
  RAISE NOTICE 'Canal % excluído com sucesso', p_channel_id;
END;
$$;

-- ==============================================================================
-- 2. RPC: Arquivar Canal (Mantém dados, remove membros)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.archive_channel(p_channel_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Remove todos os membros exceto o owner
  DELETE FROM public.chat_members
  WHERE chat_id = p_channel_id
    AND role != 'owner';
  
  -- Atualiza metadata para marcar como arquivado
  UPDATE public.chats
  SET metadata = metadata || '{"archived": true, "archived_at": "' || NOW()::TEXT || '"}'::jsonb
  WHERE id = p_channel_id;
  
  RAISE NOTICE 'Canal % arquivado', p_channel_id;
END;
$$;

-- ==============================================================================
-- 3. RPC: Adicionar Membro ao Canal
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.add_channel_member(
  p_channel_id UUID,
  p_user_id UUID,
  p_role TEXT DEFAULT 'member'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.chat_members (chat_id, user_id, role)
  VALUES (p_channel_id, p_user_id, p_role)
  ON CONFLICT (chat_id, user_id) DO UPDATE
  SET role = EXCLUDED.role;
  
  RAISE NOTICE 'Usuário % adicionado ao canal % como %', p_user_id, p_channel_id, p_role;
END;
$$;

-- ==============================================================================
-- 4. RPC: Remover Membro do Canal
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.remove_channel_member(
  p_channel_id UUID,
  p_user_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.chat_members
  WHERE chat_id = p_channel_id AND user_id = p_user_id;
  
  RAISE NOTICE 'Usuário % removido do canal %', p_user_id, p_channel_id;
END;
$$;

-- ==============================================================================
-- 5. RPC: Atualizar Status do Workflow Card
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.update_workflow_status(
  p_card_id UUID,
  p_new_status TEXT,
  p_user_id UUID,
  p_observations TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_old_status TEXT;
BEGIN
  SELECT status INTO v_old_status FROM public.workflow_cards WHERE id = p_card_id;
  
  UPDATE public.workflow_cards
  SET 
    status = p_new_status,
    updated_at = NOW()
  WHERE id = p_card_id;
  
  INSERT INTO public.workflow_card_history (card_id, user_id, action, field_changed, old_value, new_value, observations)
  VALUES (p_card_id, p_user_id, 'Status alterado', 'status', v_old_status, p_new_status, p_observations);
  
  RAISE NOTICE 'Card % status alterado de % para %', p_card_id, v_old_status, p_new_status;
END;
$$;

-- ==============================================================================
-- 6. GRANT de permissões para as funções
-- ==============================================================================

GRANT EXECUTE ON FUNCTION public.delete_channel(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_channel(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_channel_member(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_channel_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_workflow_status(UUID, TEXT, UUID, TEXT) TO authenticated;

-- Verificar criação
SELECT 
  'delete_channel' as function_name,
  proname as name
FROM pg_proc
WHERE proname = 'delete_channel'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');