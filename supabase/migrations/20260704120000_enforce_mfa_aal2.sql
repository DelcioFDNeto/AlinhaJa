-- ============================================================
-- MFA nativo (TOTP) — Enforcement de aal2 na RLS
-- ============================================================
--
-- Objetivo: tornar o 2FA REAL. Sessões que só passaram por senha (aal1)
-- não podem ler/escrever dados sensíveis; apenas sessões que completaram
-- o segundo fator (aal2) têm acesso. Isso fecha o vetor de acesso direto
-- via API REST com um JWT que ainda não cumpriu o 2FA.
--
-- Estratégia de ROLLOUT (anti-lockout):
--   A policy exige aal2 APENAS para usuários que já têm um fator TOTP
--   verificado. Quem ainda não configurou 2FA continua acessando com aal1,
--   evitando trancar a base inteira para fora durante a adoção.
--   Quando todos tiverem fator, remova a cláusula `OR NOT public.user_has_verified_mfa()`.
--
-- IMPORTANTE: tabelas do fluxo de autenticação (public.users, user_fcm_tokens,
--   organização) NÃO recebem esse gate, porque o app precisa lê-las ANTES de
--   completar o segundo fator (checagem de is_active no login/splash).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Helper SECURITY DEFINER
--    Evita exigir GRANT de SELECT em auth.mfa_factors para o role
--    `authenticated`. Retorna true se o usuário atual tem fator verificado.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.user_has_verified_mfa()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = auth, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.mfa_factors
    WHERE user_id = auth.uid()
      AND status = 'verified'
  );
$$;

GRANT EXECUTE ON FUNCTION public.user_has_verified_mfa() TO authenticated;

-- ------------------------------------------------------------
-- 2. Policy RESTRITIVA "require_aal2" nas tabelas de conteúdo sensível.
--    Restritiva = soma-se (AND) às policies existentes, sem substituí-las.
--    Idempotente: dropa antes de recriar. Pula tabelas inexistentes.
-- ------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
  target_tables TEXT[] := ARRAY[
    'messages',
    'channel_messages',
    'chats',
    'chat_members',
    'channels',
    'channel_members',
    'workflow_cards',
    'workflow_card_comments',
    'workflow_card_history',
    'support_tickets',
    'support_ticket_messages',
    'user_locations',
    'user_activity_history',
    'starred_messages',
    'calls',
    'meetings',
    'message_actions'
  ];
BEGIN
  FOREACH t IN ARRAY target_tables LOOP
    -- Só age se a tabela existir neste ambiente.
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE NOTICE 'Tabela public.% inexistente — pulando gate aal2.', t;
      CONTINUE;
    END IF;

    -- Garante RLS habilitada (necessário para policy restritiva valer).
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);

    EXECUTE format('DROP POLICY IF EXISTS "require_aal2" ON public.%I;', t);

    EXECUTE format($f$
      CREATE POLICY "require_aal2" ON public.%I
        AS RESTRICTIVE
        FOR ALL
        TO authenticated
        USING (
          (SELECT auth.jwt()->>'aal') = 'aal2'
          OR NOT public.user_has_verified_mfa()
        )
        WITH CHECK (
          (SELECT auth.jwt()->>'aal') = 'aal2'
          OR NOT public.user_has_verified_mfa()
        );
    $f$, t);

    RAISE NOTICE 'Gate aal2 aplicado em public.%', t;
  END LOOP;
END $$;

-- ============================================================
-- Reversão (manual, se necessário):
--   DO $$ DECLARE t TEXT; BEGIN
--     FOREACH t IN ARRAY ARRAY['messages','channel_messages', ...] LOOP
--       EXECUTE format('DROP POLICY IF EXISTS "require_aal2" ON public.%I;', t);
--     END LOOP;
--   END $$;
--   DROP FUNCTION IF EXISTS public.user_has_verified_mfa();
-- ============================================================
