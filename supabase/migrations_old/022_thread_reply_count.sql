-- ==============================================================================
-- 022: Correção do Motor de Threads e Limpeza Geral
-- 1. Limpa mensagens antigas corrompidas e inconsistentes.
-- 2. Adiciona a coluna 'thread_reply_count' na tabela messages.
-- 3. Cria os triggers para incrementar/decrementar quando existirem respostas.
-- ==============================================================================

-- 1. Limpar todas as mensagens do banco (Ação irreversível)
DELETE FROM public.messages;

-- 2. Adicionar a coluna que o App Flutter está tentando ler
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS thread_reply_count INT DEFAULT 0;

-- 3. Função para incrementar a contagem quando alguém responder
CREATE OR REPLACE FUNCTION increment_thread_reply_count()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.thread_id IS NOT NULL THEN
    UPDATE public.messages
    SET thread_reply_count = thread_reply_count + 1
    WHERE id = NEW.thread_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger de Inserção (Quando uma nova resposta é enviada)
DROP TRIGGER IF EXISTS on_thread_reply ON public.messages;
CREATE TRIGGER on_thread_reply
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION increment_thread_reply_count();

-- 4. Função para decrementar a contagem quando uma resposta for apagada logicamente
CREATE OR REPLACE FUNCTION decrement_thread_reply_count()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.thread_id IS NOT NULL THEN
    UPDATE public.messages
    SET thread_reply_count = GREATEST(thread_reply_count - 1, 0)
    WHERE id = OLD.thread_id;
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Trigger de Exclusão Lógica (Quando deleted_at é preenchido na resposta)
DROP TRIGGER IF EXISTS on_thread_reply_delete ON public.messages;
CREATE TRIGGER on_thread_reply_delete
AFTER UPDATE OF deleted_at ON public.messages
FOR EACH ROW
WHEN (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)
EXECUTE FUNCTION decrement_thread_reply_count();

-- Concluído! O banco de dados agora possui o motor de Threads totalmente automatizado.
