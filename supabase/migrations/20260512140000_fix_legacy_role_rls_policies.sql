-- ============================================================
-- Migration: Corrigir RLS Policies que ainda referenciam roles legados
-- ============================================================
-- Remove referências a 'ti_admin', 'director', 'sysadmin' nas policies
-- de meetings, workflow e support_tickets.
-- Substitui por 'super_admin', 'admin', 'manager' conforme hierarquia v2.
-- ============================================================

-- ── 1. MEETINGS: Corrigir política de criação ──────────────────
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

-- ── 2. WORKFLOW: Corrigir política RLS de UPDATE nos cards ──────
DROP POLICY IF EXISTS "Responsável atualiza cards" ON public.workflow_cards;

CREATE POLICY "Responsável atualiza cards"
  ON public.workflow_cards FOR UPDATE
  USING (
    -- Regra 1: Usuário é o criador ou responsável
    assigned_to = auth.uid() OR
    requested_by = auth.uid() OR
    -- Regra 2: Usuário é um Gestor/Admin no sistema (role_level) e está no canal
    (
      EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid() AND u.role_level IN ('super_admin', 'admin', 'manager')
      ) AND EXISTS (
        SELECT 1 FROM public.chat_members cm
        WHERE cm.chat_id = channel_id AND cm.user_id = auth.uid()
      )
    )
  );

-- ── 3. SUPPORT TICKETS: Corrigir todas as policies legadas ─────
-- As policies originais da migration 006 usam 'ti_admin'/'director'.
-- A migration 016 corrigiu it_support_tickets, mas não support_tickets.

-- 3a. Tickets SELECT (TI admin)
DROP POLICY IF EXISTS "TI admin pode ver todos os tickets" ON public.support_tickets;
CREATE POLICY "TI admin pode ver todos os tickets"
  ON public.support_tickets FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN ('super_admin'))
  );

-- 3b. Tickets UPDATE (TI admin)
DROP POLICY IF EXISTS "TI admin pode atualizar todos os tickets" ON public.support_tickets;
CREATE POLICY "TI admin pode atualizar todos os tickets"
  ON public.support_tickets FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN ('super_admin'))
  );

-- 3c. Messages SELECT (TI admin)
DROP POLICY IF EXISTS "TI admin vê todas as mensagens do ticket" ON public.support_ticket_messages;
CREATE POLICY "TI admin vê todas as mensagens do ticket"
  ON public.support_ticket_messages FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN ('super_admin'))
  );

-- 3d. Messages INSERT (criador do ticket OU TI)
DROP POLICY IF EXISTS "Todos podem inserir mensagens em tickets visíveis" ON public.support_ticket_messages;
CREATE POLICY "Todos podem inserir mensagens em tickets visíveis"
  ON public.support_ticket_messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid() AND
    (
      -- O usuário é o criador do ticket
      EXISTS (SELECT 1 FROM public.support_tickets st WHERE st.id = ticket_id AND st.creator_id = auth.uid())
      OR 
      -- Ou o usuário é Super Admin (TI)
      EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN ('super_admin'))
    )
  );
