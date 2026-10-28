-- Migration: Adiciona política de DELETE para mensagens
-- Permite que o autor da mensagem possa deletá-la permanentemente

-- Adiciona política de DELETE para mensagens
DROP POLICY IF EXISTS "Autor pode deletar mensagem" ON messages;

CREATE POLICY "Autor pode deletar mensagem"
  ON messages FOR DELETE
  USING (sender_id = auth.uid());
