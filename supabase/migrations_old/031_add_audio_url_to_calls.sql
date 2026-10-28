-- =====================================================
-- Migration 031: Adicionar coluna audio_url para gravação de chamadas
-- =====================================================

-- Adicionar coluna audio_url na tabela calls
ALTER TABLE public.calls 
ADD COLUMN IF NOT EXISTS audio_url TEXT;

-- Adicionar coluna audio_url na tabela meetings
ALTER TABLE public.meetings 
ADD COLUMN IF NOT EXISTS audio_url TEXT;

-- Criar índices para performance
CREATE INDEX IF NOT EXISTS idx_calls_audio_url ON public.calls(audio_url);
CREATE INDEX IF NOT EXISTS idx_meetings_audio_url ON public.meetings(audio_url);
