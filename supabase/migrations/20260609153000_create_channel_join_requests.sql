-- ==============================================================================
-- Migration: Create Channel Join Requests Table
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.channel_join_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  channel_id uuid NOT NULL REFERENCES public.channels(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT channel_join_requests_pkey PRIMARY KEY (id),
  CONSTRAINT channel_join_requests_unique UNIQUE (channel_id, user_id)
);

-- Enable RLS
ALTER TABLE public.channel_join_requests ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Users can select own requests" ON public.channel_join_requests;
DROP POLICY IF EXISTS "Admins can select channel requests" ON public.channel_join_requests;
DROP POLICY IF EXISTS "Users can insert own requests" ON public.channel_join_requests;
DROP POLICY IF EXISTS "Admins can update channel requests" ON public.channel_join_requests;
DROP POLICY IF EXISTS "Admins can delete channel requests" ON public.channel_join_requests;

-- Policy: Users can select their own requests
CREATE POLICY "Users can select own requests" ON public.channel_join_requests
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Policy: Admins/Creator can select requests for their channels
CREATE POLICY "Admins can select channel requests" ON public.channel_join_requests
  FOR SELECT TO authenticated USING (
    exists (
      select 1 from public.channels c
      where c.id = channel_id and c.created_by = auth.uid()
    ) or exists (
      select 1 from public.channel_members cm
      where cm.channel_id = channel_id and cm.user_id = auth.uid() and cm.role = 'admin'
    ) or exists (
      select 1 from public.users u
      where u.id = auth.uid() and u.role_level in ('admin', 'super_admin')
    )
  );

-- Policy: Users can insert their own requests
CREATE POLICY "Users can insert own requests" ON public.channel_join_requests
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- Policy: Admins/Creator can update requests (approve/reject)
CREATE POLICY "Admins can update channel requests" ON public.channel_join_requests
  FOR UPDATE TO authenticated USING (
    exists (
      select 1 from public.channels c
      where c.id = channel_id and c.created_by = auth.uid()
    ) or exists (
      select 1 from public.channel_members cm
      where cm.channel_id = channel_id and cm.user_id = auth.uid() and cm.role = 'admin'
    ) or exists (
      select 1 from public.users u
      where u.id = auth.uid() and u.role_level in ('admin', 'super_admin')
    )
  ) WITH CHECK (
    status IN ('approved', 'rejected')
  );

-- Policy: Admins/Creator can delete requests
CREATE POLICY "Admins can delete channel requests" ON public.channel_join_requests
  FOR DELETE TO authenticated USING (
    exists (
      select 1 from public.channels c
      where c.id = channel_id and c.created_by = auth.uid()
    ) or exists (
      select 1 from public.channel_members cm
      where cm.channel_id = channel_id and cm.user_id = auth.uid() and cm.role = 'admin'
    ) or exists (
      select 1 from public.users u
      where u.id = auth.uid() and u.role_level in ('admin', 'super_admin')
    )
  );

-- Trigger function to automatically add user to channel_members on approval
CREATE OR REPLACE FUNCTION public.handle_channel_join_request_update()
RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status = 'pending' THEN
    -- Insert into channel_members if not already there
    INSERT INTO public.channel_members (channel_id, user_id, role)
    VALUES (NEW.channel_id, NEW.user_id, 'viewer')
    ON CONFLICT (channel_id, user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger
DROP TRIGGER IF EXISTS on_channel_join_request_update ON public.channel_join_requests;
CREATE TRIGGER on_channel_join_request_update
  AFTER UPDATE ON public.channel_join_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_channel_join_request_update();

-- Add to Realtime publication
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'channel_join_requests'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.channel_join_requests;
    END IF;
END
$$;
