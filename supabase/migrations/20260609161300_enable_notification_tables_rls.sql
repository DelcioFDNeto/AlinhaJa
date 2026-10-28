-- Habilitar RLS nas tabelas de notificações (caso ainda não estejam habilitadas)
ALTER TABLE public.user_notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_notification_settings ENABLE ROW LEVEL SECURITY;

-- Criar política para user_notification_preferences
CREATE POLICY "Permitir tudo para o próprio usuário" ON public.user_notification_preferences
    FOR ALL
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Criar política para user_notification_settings
CREATE POLICY "Permitir tudo para o próprio usuário" ON public.user_notification_settings
    FOR ALL
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
