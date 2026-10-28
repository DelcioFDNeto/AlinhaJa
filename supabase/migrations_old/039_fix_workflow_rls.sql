
-- ==============================================================================
-- FIX: Permitir que qualquer membro do canal atualize os cards (para que os Operadores possam assumir, arquivar e alterar status)
-- ==============================================================================

DROP POLICY IF EXISTS "Responsável atualiza cards" ON public.workflow_cards;

CREATE POLICY "Membros atualizam cards"
  ON public.workflow_cards FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.chat_members cm
      WHERE cm.chat_id = channel_id AND cm.user_id = auth.uid()
    )
  );
