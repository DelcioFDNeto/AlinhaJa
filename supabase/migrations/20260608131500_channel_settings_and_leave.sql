-- Migration: 20260608131500_channel_settings_and_leave.sql
-- Description: Add DELETE policy to channel_members for leaving channels and RPC for channel updates.

-- 1. Add DELETE policy on channel_members (allows leaving channel)
DROP POLICY IF EXISTS "Deletar propria participacao" ON public.channel_members;
CREATE POLICY "Deletar propria participacao" ON public.channel_members
  FOR DELETE
  USING (user_id = auth.uid());

-- 2. Create RPC function for updating channel info securely
CREATE OR REPLACE FUNCTION public.update_channel_info(
  p_channel_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_metadata JSONB DEFAULT '{}'::JSONB,
  p_posting_permission TEXT DEFAULT 'everyone'
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para atualizar este workspace.';
  END IF;

  UPDATE public.channels
  SET
    name = p_name,
    description = p_description,
    metadata = p_metadata,
    posting_permission = p_posting_permission,
    updated_at = NOW()
  WHERE id = p_channel_id;
END;
$$;

-- 3. Grant EXECUTE permissions to authenticated users
GRANT EXECUTE ON FUNCTION public.update_channel_info(UUID, TEXT, TEXT, JSONB, TEXT) TO authenticated;
