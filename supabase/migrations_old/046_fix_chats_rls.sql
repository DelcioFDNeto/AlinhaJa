-- ============================================================
-- Migration 046: Fix RLS for channel creation
-- 
-- DESCRIPTION:
-- When creating a channel/chat using .insert().select(), Postgres
-- evaluates the SELECT policies before returning the inserted row.
-- Since the user hasn't been added to chat_members yet, the 
-- "Membros veem o chat" policy was evaluating to FALSE, causing
-- RLS violation error (42501).
--
-- FIX:
-- Allow the `created_by` user to SELECT the chat even before
-- they are explicitly added to `chat_members`.
-- ============================================================

DROP POLICY IF EXISTS "Membros veem o chat" ON public.chats;
DROP POLICY IF EXISTS "Membros e criadores veem o chat" ON public.chats;

CREATE POLICY "Membros e criadores veem o chat"
  ON public.chats FOR SELECT
  USING (
    created_by = auth.uid() OR
    public.is_chat_member(id)
  );
