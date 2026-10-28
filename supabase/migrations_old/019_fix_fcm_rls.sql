-- ============================================================
-- 020: Fix FCM Token RLS — Adicionar política de UPDATE
-- Sem ela, o upsert no Flutter falha com erro RLS 42501.
-- ============================================================

-- Adiciona policy de UPDATE que estava faltando
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_fcm_tokens'
          AND policyname = 'Users can update own fcm tokens'
    ) THEN
        CREATE POLICY "Users can update own fcm tokens"
            ON public.user_fcm_tokens FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END
$$;
