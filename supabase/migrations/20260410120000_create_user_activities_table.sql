-- Migration: Criar tabela e RPC de log_user_activity para resolver o erro 404

-- 1. Cria a tabela user_activities
CREATE TABLE IF NOT EXISTS public.user_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL,
    description TEXT,
    target_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ativa RLS (Row Level Security)
ALTER TABLE public.user_activities ENABLE ROW LEVEL SECURITY;

-- Políticas de segurança: 
-- Usuários podem inserir logs da própria conta, mas apenas administradores podem ler todos os logs.
DROP POLICY IF EXISTS "Users can insert own activities" ON public.user_activities;
CREATE POLICY "Users can insert own activities" 
ON public.user_activities FOR INSERT 
TO authenticated 
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can read own activities" ON public.user_activities;
CREATE POLICY "Users can read own activities" 
ON public.user_activities FOR SELECT 
TO authenticated 
USING (auth.uid() = user_id);

-- 2. Cria a função RPC log_user_activity
CREATE OR REPLACE FUNCTION public.log_user_activity(
    p_user_id UUID,
    p_activity_type TEXT,
    p_description TEXT DEFAULT NULL,
    p_target_id TEXT DEFAULT NULL
) 
RETURNS VOID 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.user_activities (user_id, activity_type, description, target_id)
    VALUES (p_user_id, p_activity_type, p_description, p_target_id);
END;
$$;
