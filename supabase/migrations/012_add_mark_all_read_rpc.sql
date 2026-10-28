-- ============================================================
-- Migration: Adicionar função para marcar todas conversas como lidas
-- Executar no SQL Editor do Supabase Dashboard
-- ============================================================

-- Função para marcar todas as conversas do usuário como lidas
CREATE OR REPLACE FUNCTION mark_all_chats_as_read(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Marca todas as conversas do usuário como lidas
  UPDATE public.chat_members
  SET last_read_at = NOW()
  WHERE user_id = p_user_id;
  
  -- Marca todas as mensagens não lidas de todos os chats do usuário
  UPDATE public.messages
  SET status = 'read'
  WHERE chat_id IN (SELECT chat_id FROM chat_members WHERE user_id = p_user_id)
  AND sender_id != p_user_id
  AND status != 'read';
END;
$$;
