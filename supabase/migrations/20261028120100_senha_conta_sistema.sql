-- ============================================================
-- Senha da conta de sistema deixa de ser conhecida
--
-- PROBLEMA
-- 20260427150000_seed_system_user criava, em toda instalação, a conta
-- de sistema `00000000-0000-0000-0000-111111111111` (dona dos canais
-- semeados) com e-mail confirmado e uma senha escrita no próprio
-- código. A conta nasce bloqueada pela `handle_new_user()`, mas bastaria
-- alguém aprová-la para que qualquer pessoa com acesso ao código
-- entrasse nela.
--
-- O QUE MUDA
-- A senha passa a ser aleatória — ninguém a conhece — SOMENTE se a
-- conta ainda estiver bloqueada e com a senha original. Uma conta que
-- já foi liberada e esteja em uso não é tocada aqui, para não cortar o
-- acesso de quem a usa; nesse caso, troque a senha pelo painel.
-- ============================================================

DO $$
DECLARE
  v_trocadas INT;
BEGIN
  UPDATE auth.users
     SET encrypted_password =
           extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf', 10))
   WHERE id = '00000000-0000-0000-0000-111111111111'
     AND banned_until IS NOT NULL
     AND banned_until > NOW()
     AND encrypted_password = extensions.crypt('alinhaja25', encrypted_password);
  GET DIAGNOSTICS v_trocadas = ROW_COUNT;

  IF v_trocadas = 0 AND EXISTS (
    SELECT 1 FROM auth.users
     WHERE id = '00000000-0000-0000-0000-111111111111'
       AND (banned_until IS NULL OR banned_until <= NOW())
  ) THEN
    RAISE WARNING 'A conta de sistema 00000000-0000-0000-0000-111111111111 '
      'está liberada para login. Confirme que a senha não é a original.';
  END IF;
END $$;
