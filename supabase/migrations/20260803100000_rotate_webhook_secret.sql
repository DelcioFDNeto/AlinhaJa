-- ============================================================
-- Rotação do webhook secret (achado de segurança 1.3)
--
-- CONTEXTO
-- A migration 20260710160001_seed_webhook_secret.sql semeou o valor
-- literal 'alinhaja_super_secret_webhook_key_2026' no Vault. Como ela está
-- versionada no Git, esse segredo deve ser considerado COMPROMETIDO:
-- qualquer pessoa com acesso ao repositório pode forjar chamadas às
-- Edge Functions e disparar push/e-mail em nome da empresa ou consumir
-- crédito de IA.
--
-- POR QUE ESTA MIGRATION NÃO GERA O SEGREDO SOZINHA
-- O valor precisa existir em DOIS lugares (Vault do banco + secrets das
-- Edge Functions). Se o banco rotacionasse sozinho, as functions ficariam
-- com o valor antigo e — agora que são fail-closed — passariam a rejeitar
-- tudo, derrubando push notifications até a intervenção manual.
-- Por isso aqui entregamos a ferramenta (RPC) e o diagnóstico; a troca é
-- feita na ordem do runbook abaixo, com zero downtime.
--
-- RUNBOOK DE ROTAÇÃO (nesta ordem)
--   1. Gere um segredo forte, fora do repositório:
--        openssl rand -hex 32
--   2. Publique nas Edge Functions aceitando os DOIS valores durante a janela:
--        npx supabase secrets set WEBHOOK_SECRET=<novo> \
--                                 WEBHOOK_SECRET_PREVIOUS=alinhaja_super_secret_webhook_key_2026
--        npx supabase functions deploy send-chat-notification send-call-notification \
--            rh-automations ai-chatbot rh-extract-cv send-workflow-notification \
--            send-module-notification webhook-receiver
--      (as 8 funções que leem WEBHOOK_SECRET neste repositório; conferir com
--       `grep -rl WEBHOOK_SECRET supabase/functions/` antes de rodar)
--   3. Troque no banco (SQL Editor, como super_admin):
--        SELECT public.rotate_webhook_secret('<novo>');
--   4. Confirme que voltou saudável:
--        SELECT public.webhook_secret_status();
--   5. Encerre a janela de rotação:
--        npx supabase secrets unset WEBHOOK_SECRET_PREVIOUS
--        npx supabase functions deploy ...   (mesmas funções do passo 2)
-- ============================================================

-- ── 1. Diagnóstico: o segredo ainda é o que vazou? ───────────
-- Não devolve o valor — só o veredito. Serve para health check e para
-- o aviso no fim desta migration.
CREATE OR REPLACE FUNCTION public.webhook_secret_status()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_secret text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.users
     WHERE id = auth.uid()
       AND role_level = 'super_admin'
       AND is_active
  ) THEN
    RAISE EXCEPTION 'Acesso restrito ao super_admin';
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_secret
      FROM vault.decrypted_secrets
     WHERE name = 'webhook_secret'
     LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;

  IF v_secret IS NULL OR v_secret = '' THEN
    RETURN 'AUSENTE — os triggers enviam header vazio e as Edge Functions '
        || 'fail-closed vão rejeitar. Rode rotate_webhook_secret().';
  END IF;

  IF v_secret = 'alinhaja_super_secret_webhook_key_2026' THEN
    RETURN 'COMPROMETIDO — valor versionado no Git. Rotacione seguindo o '
        || 'runbook de 20260803100000_rotate_webhook_secret.sql.';
  END IF;

  IF length(v_secret) < 32 THEN
    RETURN 'FRACO — menos de 32 caracteres. Use openssl rand -hex 32.';
  END IF;

  RETURN 'OK';
END;
$$;

REVOKE ALL ON FUNCTION public.webhook_secret_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.webhook_secret_status() TO authenticated;

-- ── 2. Rotação propriamente dita ─────────────────────────────
-- Recebe o valor já gerado fora do banco (passo 1 do runbook) para que
-- ele nunca precise ser escrito num arquivo versionado.
CREATE OR REPLACE FUNCTION public.rotate_webhook_secret(p_new_secret text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.users
     WHERE id = auth.uid()
       AND role_level = 'super_admin'
       AND is_active
  ) THEN
    RAISE EXCEPTION 'Apenas super_admin pode rotacionar o webhook secret';
  END IF;

  IF p_new_secret IS NULL OR length(p_new_secret) < 32 THEN
    RAISE EXCEPTION 'Segredo muito curto (mínimo 32 caracteres). Use: openssl rand -hex 32';
  END IF;

  IF p_new_secret = 'alinhaja_super_secret_webhook_key_2026' THEN
    RAISE EXCEPTION 'Esse é justamente o valor comprometido. Gere um novo.';
  END IF;

  SELECT id INTO v_id FROM vault.secrets WHERE name = 'webhook_secret' LIMIT 1;

  IF v_id IS NULL THEN
    PERFORM vault.create_secret(
      p_new_secret, 'webhook_secret', 'Chave para Webhooks internos');
  ELSE
    PERFORM vault.update_secret(v_id, p_new_secret);
  END IF;

  RETURN 'Segredo rotacionado. Confirme que WEBHOOK_SECRET das Edge Functions '
      || 'já tem o mesmo valor e então remova WEBHOOK_SECRET_PREVIOUS.';
END;
$$;

REVOKE ALL ON FUNCTION public.rotate_webhook_secret(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rotate_webhook_secret(text) TO authenticated;

-- ── 3. Aviso alto no apply ───────────────────────────────────
-- Se a base ainda estiver com o valor vazado, o db push grita.
DO $$
DECLARE
  v_secret text;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_secret
      FROM vault.decrypted_secrets
     WHERE name = 'webhook_secret'
     LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;

  IF v_secret = 'alinhaja_super_secret_webhook_key_2026' THEN
    RAISE WARNING '=====================================================';
    RAISE WARNING 'WEBHOOK SECRET COMPROMETIDO (valor versionado no Git).';
    RAISE WARNING 'Rotacione AGORA seguindo o runbook no cabeçalho de';
    RAISE WARNING '20260803100000_rotate_webhook_secret.sql';
    RAISE WARNING '=====================================================';
  END IF;
END $$;
