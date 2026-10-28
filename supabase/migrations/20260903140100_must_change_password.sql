-- ============================================================
-- Audit de segurança 2026-09-03: flag de troca obrigatória de senha
--
-- PROBLEMA
-- O seed cria usuários com senha padrão temporária. Sem uma
-- barreira no login, esses usuários podem operar indefinidamente com
-- a senha compartilhada — uma violação grave de controle de acesso.
--
-- SOLUÇÃO
-- Coluna must_change_password (default FALSE) marcada como TRUE pelo
-- seed. O login no app verifica essa flag e redireciona para a tela
-- de troca antes de permitir acesso ao sistema.
-- ============================================================

-- ── 1. Adiciona coluna ───────────────────────────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.users.must_change_password IS
  'TRUE quando o usuário foi criado por seed/admin com senha temporária e precisa trocar no primeiro login.';

-- ── 2. Marca todos os usuários existentes com senha de seed ──
-- Só marca quem nunca mudou a senha (last_sign_in_at IS NULL ou
-- confirmed_at coincide com created_at, indicando conta provisionada).
UPDATE public.users u
   SET must_change_password = true
  FROM auth.users a
 WHERE u.id = a.id
   AND a.last_sign_in_at IS NULL;

-- ── 3. RPC para o app marcar a senha como trocada ────────────
CREATE OR REPLACE FUNCTION public.mark_password_changed()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.users
     SET must_change_password = false
   WHERE id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.mark_password_changed() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_password_changed() TO authenticated;

COMMENT ON FUNCTION public.mark_password_changed() IS
  'Marca que o usuário trocou a senha provisória (chamado após updateUser com nova senha).';

-- ── 4. PostgREST ─────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
