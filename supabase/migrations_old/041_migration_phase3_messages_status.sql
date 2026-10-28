-- Execute os seguintes comandos no SQL Editor do seu projeto Supabase:

-- 1. Adicionar a coluna de status (sent, delivered, read) na tabela de mensagens
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS status text DEFAULT 'sent';

-- 2. Adicionar o array read_by para chats em grupo (Armazenará os IDs de quem ja visualizou)
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS read_by uuid[] DEFAULT '{}';

-- 3. Criar uma RPC super rápida para marcar mensagens como lidas sem onerar a banda do dispositivo móvil
CREATE OR REPLACE FUNCTION mark_messages_as_read(p_chat_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- 1) Atualiza diretamente todas mensagens NÃO lidas (onde sender != logado e logado ainda não tá no array)
  UPDATE public.messages
  SET 
      -- O status vira 'read' p/ 1:1. P/ grupos, pode ser util manter sent/read dependendo da maioria, mas 
      -- setamos read_by c/ array_append (cuidando pra n duplicar).
      status = 'read',
      read_by = array_append(ARRAY(SELECT DISTINCT e FROM unnest(read_by) e), p_user_id)
  WHERE 
      chat_id = p_chat_id 
      AND sender_id != p_user_id 
      AND NOT (read_by @> ARRAY[p_user_id]); -- Garante que nao dá update excessivo se ja leu
END;
$$;
