-- ============================================================
-- Migration: Habilitar Reuniões e Chamadas em Canais de Workflow
-- ============================================================
-- Adiciona channel_id nas tabelas meetings e calls, relaxa a
-- obrigatoriedade de chat_id, e atualiza RLS para channel_members.
-- ============================================================

-- ── 1. MEETINGS: Adicionar channel_id ──────────────────────────

ALTER TABLE public.meetings
ADD COLUMN IF NOT EXISTS channel_id UUID REFERENCES public.channels(id) ON DELETE CASCADE;

-- Relaxar NOT NULL de chat_id (meetings já era nullable)
-- chat_id em meetings já é YES nullable, nada a fazer.

-- CHECK: exatamente um dos dois deve ser preenchido
ALTER TABLE public.meetings
DROP CONSTRAINT IF EXISTS meetings_context_check;

ALTER TABLE public.meetings
ADD CONSTRAINT meetings_context_check
CHECK (
  (chat_id IS NOT NULL AND channel_id IS NULL)
  OR
  (chat_id IS NULL AND channel_id IS NOT NULL)
  OR
  (chat_id IS NULL AND channel_id IS NULL) -- reuniões standalone (host-only)
);

-- Índice para buscas por channel_id
CREATE INDEX IF NOT EXISTS idx_meetings_channel_id ON public.meetings(channel_id);

-- ── 2. CALLS: Adicionar channel_id ─────────────────────────────

ALTER TABLE public.calls
ADD COLUMN IF NOT EXISTS channel_id UUID REFERENCES public.channels(id) ON DELETE CASCADE;

-- Relaxar NOT NULL de chat_id em calls
ALTER TABLE public.calls
ALTER COLUMN chat_id DROP NOT NULL;

-- CHECK: exatamente um dos dois deve ser preenchido
ALTER TABLE public.calls
DROP CONSTRAINT IF EXISTS calls_context_check;

ALTER TABLE public.calls
ADD CONSTRAINT calls_context_check
CHECK (
  (chat_id IS NOT NULL AND channel_id IS NULL)
  OR
  (chat_id IS NULL AND channel_id IS NOT NULL)
);

-- Índice para buscas por channel_id
CREATE INDEX IF NOT EXISTS idx_calls_channel_id ON public.calls(channel_id);

-- ── 3. MEETINGS RLS: Atualizar policies para incluir channel_members ───

-- 3a. DROP policies legadas de SELECT
DROP POLICY IF EXISTS "Users can view meetings of their chats" ON public.meetings;
DROP POLICY IF EXISTS "Members can view video meetings of their chats" ON public.meetings;
DROP POLICY IF EXISTS "Users can read meetings they're in" ON public.meetings;

-- 3b. Criar policy unificada de SELECT
CREATE POLICY "Membros podem ver reuniões"
ON public.meetings FOR SELECT
USING (
  host_id = auth.uid()
  OR caller_id = auth.uid()
  OR chat_id IN (
    SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
  )
  OR channel_id IN (
    SELECT channel_id FROM public.channel_members WHERE user_id = auth.uid()
  )
);

-- 3c. DROP policies legadas de UPDATE
DROP POLICY IF EXISTS "Host can update meetings" ON public.meetings;
DROP POLICY IF EXISTS "Participants can update video meetings" ON public.meetings;

-- 3d. Criar policy unificada de UPDATE
CREATE POLICY "Participantes podem atualizar reuniões"
ON public.meetings FOR UPDATE
USING (
  host_id = auth.uid()
  OR caller_id = auth.uid()
  OR chat_id IN (
    SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
  )
  OR channel_id IN (
    SELECT channel_id FROM public.channel_members WHERE user_id = auth.uid()
  )
);

-- 3e. DROP e recriar policy de INSERT para aceitar channel_id
DROP POLICY IF EXISTS "Apenas cargos gerenciais podem criar reuniões" ON public.meetings;

CREATE POLICY "Apenas cargos gerenciais podem criar reuniões"
ON public.meetings FOR INSERT
WITH CHECK (
  host_id = auth.uid() AND
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role_level IN ('super_admin', 'admin', 'manager')
  )
);

-- ── 4. CALLS RLS: Atualizar policies para incluir channel_members ──────

-- 4a. DROP policies legadas
DROP POLICY IF EXISTS "Membros do chat podem ver o histórico de chamadas" ON public.calls;
DROP POLICY IF EXISTS "Membros do chat podem criar e atualizar chamadas" ON public.calls;
DROP POLICY IF EXISTS "Users can view calls of their chats" ON public.calls;
DROP POLICY IF EXISTS "Users can create calls in their chats" ON public.calls;
DROP POLICY IF EXISTS "Users can update calls of their chats" ON public.calls;

-- 4b. Criar policy unificada de SELECT
CREATE POLICY "Membros podem ver chamadas"
ON public.calls FOR SELECT
USING (
  caller_id = auth.uid()
  OR chat_id IN (
    SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
  )
  OR channel_id IN (
    SELECT channel_id FROM public.channel_members WHERE user_id = auth.uid()
  )
);

-- 4c. Criar policy de INSERT
CREATE POLICY "Membros podem criar chamadas"
ON public.calls FOR INSERT
WITH CHECK (
  caller_id = auth.uid()
  AND (
    chat_id IN (
      SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
    )
    OR channel_id IN (
      SELECT channel_id FROM public.channel_members WHERE user_id = auth.uid()
    )
  )
);

-- 4d. Criar policy de UPDATE
CREATE POLICY "Membros podem atualizar chamadas"
ON public.calls FOR UPDATE
USING (
  caller_id = auth.uid()
  OR chat_id IN (
    SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
  )
  OR channel_id IN (
    SELECT channel_id FROM public.channel_members WHERE user_id = auth.uid()
  )
);
