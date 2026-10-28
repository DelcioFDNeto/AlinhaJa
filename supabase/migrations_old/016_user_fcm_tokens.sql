-- Criação da tabela de Tokens FCM para Push Notifications
CREATE TABLE IF NOT EXISTS public.user_fcm_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL, -- 'android', 'ios', 'web'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    UNIQUE(user_id, token) -- Um usuário não pode ter o mesmo token repetido
);

-- Habilitar RLS
ALTER TABLE public.user_fcm_tokens ENABLE ROW LEVEL SECURITY;

-- O usuário só pode visualizar seus próprios tokens
CREATE POLICY "Users can view own fcm tokens"
    ON public.user_fcm_tokens FOR SELECT
    USING (auth.uid() = user_id);

-- O usuário só pode inserir seus próprios tokens
CREATE POLICY "Users can insert own fcm tokens"
    ON public.user_fcm_tokens FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- O usuário só pode deletar seus próprios tokens (ex: no logout ou rotate)
CREATE POLICY "Users can delete own fcm tokens"
    ON public.user_fcm_tokens FOR DELETE
    USING (auth.uid() = user_id);

-- Opcional: Atualizar a data se o token for revisto
CREATE OR REPLACE FUNCTION update_user_fcm_tokens_updated_at()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = timezone('utc'::text, now());
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_fcm_tokens_modtime
BEFORE UPDATE ON public.user_fcm_tokens
FOR EACH ROW EXECUTE FUNCTION update_user_fcm_tokens_updated_at();

-- Dar GRANT às roles padrão do Supabase
GRANT ALL ON TABLE public.user_fcm_tokens TO authenticated;
GRANT ALL ON TABLE public.user_fcm_tokens TO service_role;
