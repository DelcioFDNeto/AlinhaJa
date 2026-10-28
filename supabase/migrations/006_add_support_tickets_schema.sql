-- CONSOLIDATED MIGRATIONS 044

-- ==============================================================================
-- Migration 043: IT Support Tickets (Helpdesk Isolado)
-- ==============================================================================

-- 1. ENUMS
-- ==============================================================================

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'support_ticket_status') THEN
    CREATE TYPE support_ticket_status AS ENUM ('new', 'in_progress', 'pending_vendor', 'resolved', 'cancelled');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'support_ticket_priority') THEN
    CREATE TYPE support_ticket_priority AS ENUM ('low', 'medium', 'high', 'urgent');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'support_ticket_category') THEN
    CREATE TYPE support_ticket_category AS ENUM ('software', 'hardware', 'network', 'external_access', 'general', 'other');
  END IF;
END $$;

-- 2. TABELAS PRINCIPAIS
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.support_tickets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  assigned_to     UUID REFERENCES public.users(id) ON DELETE SET NULL,
  title           TEXT NOT NULL,
  description     TEXT NOT NULL,
  category        support_ticket_category NOT NULL DEFAULT 'other',
  priority        support_ticket_priority NOT NULL DEFAULT 'medium',
  status          support_ticket_status NOT NULL DEFAULT 'new',
  device_info     TEXT,
  attachments     JSONB DEFAULT '[]',
  resolved_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_creator ON public.support_tickets(creator_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON public.support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_assigned ON public.support_tickets(assigned_to);

DROP TRIGGER IF EXISTS support_tickets_updated_at ON public.support_tickets;
CREATE TRIGGER support_tickets_updated_at
  BEFORE UPDATE ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Trigger: setar resolved_at automaticamente quando o status muda para 'resolved'
CREATE OR REPLACE FUNCTION public.set_ticket_resolved_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'resolved' AND (OLD.status IS DISTINCT FROM 'resolved') THEN
    NEW.resolved_at = NOW();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS support_tickets_resolved_at ON public.support_tickets;
CREATE TRIGGER support_tickets_resolved_at
  BEFORE UPDATE ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.set_ticket_resolved_at();

-- 3. MENSAGENS DENTRO DO TICKET
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.support_ticket_messages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id       UUID NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  sender_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content         TEXT NOT NULL,
  attachments     JSONB DEFAULT '[]',
  is_internal     BOOLEAN DEFAULT FALSE, -- Apenas TI vê
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_msgs_ticket ON public.support_ticket_messages(ticket_id);

-- 4. ROW LEVEL SECURITY (RLS)
-- ==============================================================================
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_ticket_messages ENABLE ROW LEVEL SECURITY;

-- Tickets RLS:
-- Usuário comum vê seus próprios tickets. TI vê tudo.
CREATE POLICY "TI admin pode ver todos os tickets"
  ON public.support_tickets FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND (role_level = 'ti_admin' OR role_level = 'director'))
  );

CREATE POLICY "Usuário comum vê seus próprios tickets"
  ON public.support_tickets FOR SELECT
  USING (creator_id = auth.uid());

CREATE POLICY "Usuários podem criar tickets"
  ON public.support_tickets FOR INSERT
  WITH CHECK (creator_id = auth.uid());

CREATE POLICY "TI admin pode atualizar todos os tickets"
  ON public.support_tickets FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND (role_level = 'ti_admin' OR role_level = 'director'))
  );

CREATE POLICY "Usuário pode atualizar tickets abertos recém criados"
  ON public.support_tickets FOR UPDATE
  USING (creator_id = auth.uid() AND status = 'new');

-- Messages RLS:
CREATE POLICY "TI admin vê todas as mensagens do ticket"
  ON public.support_ticket_messages FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND (role_level = 'ti_admin' OR role_level = 'director'))
  );

CREATE POLICY "Criador do ticket vê as respostas não-internas"
  ON public.support_ticket_messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.support_tickets st 
      WHERE st.id = ticket_id AND st.creator_id = auth.uid()
    )
    AND is_internal = FALSE
  );

CREATE POLICY "Todos podem inserir mensagens em tickets visíveis"
  ON public.support_ticket_messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid() AND
    (
      -- O usuário é o criador
      EXISTS (SELECT 1 FROM public.support_tickets st WHERE st.id = ticket_id AND st.creator_id = auth.uid())
      OR 
      -- Ou o usuário é TI
      EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND (role_level = 'ti_admin' OR role_level = 'director'))
    )
  );

-- 5. REALTIME
-- ==============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'support_tickets'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE support_tickets;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'support_ticket_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE support_ticket_messages;
  END IF;
END $$;

