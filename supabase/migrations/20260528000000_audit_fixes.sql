-- 1. Create starred_messages table
CREATE TABLE public.starred_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    chat_message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    chat_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS for starred_messages
ALTER TABLE public.starred_messages ENABLE ROW LEVEL SECURITY;

-- Policy: Users can see only their own starred messages
CREATE POLICY "Users can view their own starred messages"
ON public.starred_messages FOR SELECT
USING (auth.uid() = user_id);

-- Policy: Users can insert their own starred messages
CREATE POLICY "Users can insert their own starred messages"
ON public.starred_messages FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Policy: Users can delete their own starred messages
CREATE POLICY "Users can delete their own starred messages"
ON public.starred_messages FOR DELETE
USING (auth.uid() = user_id);


-- 2. Add unread_count to channel_members
ALTER TABLE public.channel_members ADD COLUMN IF NOT EXISTS unread_count INT DEFAULT 0;


-- 3. Create Admin RPCs for User Management
-- These should ideally be executed with SECURITY DEFINER or proper checks,
-- but the app's RLS relies on the user being an admin (checked in RPCs or App).
-- We will enforce that the executing user is a super_admin or admin.

CREATE OR REPLACE FUNCTION archive_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Verify caller is admin or super_admin
    IF NOT EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND role_level IN ('admin', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'Access denied. Only admins can archive users.';
    END IF;

    UPDATE public.users SET is_active = false WHERE id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION reactivate_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Verify caller is admin or super_admin
    IF NOT EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND role_level IN ('admin', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'Access denied. Only admins can reactivate users.';
    END IF;

    UPDATE public.users SET is_active = true WHERE id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION delete_user_account(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Verify caller is super_admin
    IF NOT EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND role_level = 'super_admin'
    ) THEN
        RAISE EXCEPTION 'Access denied. Only super admins can permanently delete user accounts.';
    END IF;

    -- Deleting from auth.users cascades to public.users and all related tables (if constraints are ON DELETE CASCADE)
    DELETE FROM auth.users WHERE id = p_user_id;
END;
$$;
