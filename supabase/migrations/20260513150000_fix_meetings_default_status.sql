-- ============================================================
-- Migration: Corrigir default status da tabela meetings
-- ============================================================
-- Altera o valor padrão da coluna 'status' de 'ringing' para 'waiting'.
-- Isso alinha o banco de dados com a expectativa do código Flutter,
-- onde reuniões nascem no estado de 'waiting' (aguardando participantes).
-- ============================================================

ALTER TABLE public.meetings
ALTER COLUMN status SET DEFAULT 'waiting';

-- Atualiza qualquer reunião pendente que tenha ficado presa no status antigo de criação errôneo
UPDATE public.meetings
SET status = 'waiting'
WHERE status = 'ringing';
