-- Migration: Adiciona callee_id e answered_by à tabela calls
-- Permite rastrear quem foi chamado e quem atendeu.

-- 1. Adiciona coluna callee_id (quem recebeu a chamada)
ALTER TABLE public.calls
  ADD COLUMN callee_id UUID REFERENCES public.users(id) ON DELETE SET NULL;

-- 2. Adiciona coluna answered_by (quem atendeu a chamada)
ALTER TABLE public.calls
  ADD COLUMN answered_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

-- 3. Torna chat_id nullable (chamadas podem ser em canais ou DMs)
ALTER TABLE public.calls
  ALTER COLUMN chat_id DROP NOT NULL;

-- 4. Índices para consultas de histórico por destinatário
CREATE INDEX IF NOT EXISTS idx_calls_callee_id ON public.calls(callee_id);
CREATE INDEX IF NOT EXISTS idx_calls_answered_by ON public.calls(answered_by);
