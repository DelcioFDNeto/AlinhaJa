-- ============================================================
-- Assistente IA — usuário-bot + webhook de resposta automática
--
-- • Cria um usuário de sistema "Assistente IA" com UUID fixo. Como
--   public.users.id é FK de auth.users(id), o bot PRECISA existir em
--   auth.users. Ele nunca autentica (senha desabilitada).
-- • O trigger handle_new_user (AFTER INSERT ON auth.users) cria o
--   perfil em public.users automaticamente; aqui só o ativamos.
-- • Um trigger em public.messages dispara a Edge Function ai-chatbot
--   (via pg_net + x-webhook-secret) apenas quando o bot é membro do
--   chat e o remetente não é o próprio bot — a Edge Function decide se
--   responde (DM: sempre; grupo: só se mencionado/respondido).
--
-- Chave da Groq do bot é GLOBAL (Supabase Secret GROQ_API_KEY), não BYOK.
-- ============================================================

-- ── 1. Usuário-bot (idempotente) ─────────────────────────────
DO $$
DECLARE
  v_bot uuid := '00000000-0000-4000-a000-000000000001';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_bot) THEN
    INSERT INTO auth.users (
      instance_id, id, aud, role, email,
      encrypted_password, email_confirmed_at,
      created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      v_bot,
      'authenticated',
      'authenticated',
      'assistente.ia@alinhaja.bot',
      'DISABLED-BOT-ACCOUNT-NO-LOGIN', -- não é hash bcrypt válido → login impossível
      now(),
      now(), now(),
      '{"provider":"system","providers":["system"]}'::jsonb,
      '{"full_name":"Assistente IA","is_bot":true}'::jsonb
    );
    -- o trigger handle_new_user já criou public.users a partir do insert acima
  END IF;

  -- Garante perfil visível/ativo (o trigger cria com is_active=false).
  UPDATE public.users
  SET full_name = 'Assistente IA', is_active = true, is_online = true
  WHERE id = v_bot;

  -- Bot nunca autentica: remove o banimento default de novos usuários.
  UPDATE auth.users SET banned_until = NULL WHERE id = v_bot;
END $$;

-- ── 2. Trigger de disparo do chatbot ─────────────────────────
CREATE OR REPLACE FUNCTION public.trg_ai_chatbot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_bot uuid := '00000000-0000-4000-a000-000000000001';
  v_url text := 'https://gpeemngsxvqjflasdody.supabase.co/functions/v1/ai-chatbot';
BEGIN
  -- Nunca reage às próprias mensagens (evita loop) nem a apagadas.
  IF NEW.sender_id = v_bot OR NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Só desperta a Edge Function se o bot participar deste chat.
  IF NOT EXISTS (
    SELECT 1 FROM public.chat_members
    WHERE chat_id = NEW.chat_id AND user_id = v_bot
  ) THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.get_webhook_secret()
    ),
    body := jsonb_build_object(
      'type', TG_OP,
      'record', row_to_json(NEW)
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ai_chatbot ON public.messages;
CREATE TRIGGER trg_ai_chatbot
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.trg_ai_chatbot();
