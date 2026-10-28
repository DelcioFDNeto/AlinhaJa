-- ============================================================
-- Migration 036: Add Video Content Type and View Once RPC
-- ============================================================

-- 1. Adicionar o tipo 'video' ao ENUM 'content_type'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid = 'content_type'::regtype AND enumlabel = 'video') THEN
    ALTER TYPE content_type ADD VALUE 'video';
  END IF;
END $$;

-- 2. Função RPC para excluir a mensagem "View Once" após ser lida
CREATE OR REPLACE FUNCTION public.mark_view_once_opened(
  p_message_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- A função deletará a mensagem apenas se ela tiver is_view_once == true.
  -- E apenas quem está lendo ou quem mandou deveria ter o direito, 
  -- mas para garantir que o destinatário pode forçar a deleção logo após ler:
  
  DELETE FROM public.messages
  WHERE id = p_message_id 
    AND (metadata->>'is_view_once')::boolean = true
    AND EXISTS (
      -- Garante que apenas um membro do chat está executando a deleção
      SELECT 1 FROM public.chat_members cm
      WHERE cm.chat_id = messages.chat_id AND cm.user_id = auth.uid()
    );
END;
$$;
