-- ============================================================
-- CORREÇÃO CRÍTICA: guarda de administrador que falhava aberta
--
-- PROBLEMA
-- As RPCs administrativas checavam o papel do chamador assim:
--
--   SELECT role_level INTO v_caller_role FROM public.users WHERE id = auth.uid();
--   IF v_caller_role NOT IN ('super_admin', 'admin') THEN RAISE ...
--
-- Quando o chamador NÃO tem linha em `public.users` — o caso do papel
-- `anon`, e também de conta removida, pendente ou inativa — o SELECT não
-- devolve linha e `v_caller_role` fica NULL. Em SQL, `NULL NOT IN (...)`
-- não é TRUE: é NULL. O `IF` não dispara, nenhuma exceção é levantada e a
-- execução segue para o UPDATE. Como as funções são SECURITY DEFINER, o
-- UPDATE roda como dono e ignora RLS.
--
-- Pior, em `admin_update_user_role` a trava de promoção tinha o mesmo vício:
--   IF p_new_role = 'super_admin' AND v_caller_role != 'super_admin'
-- vira `TRUE AND NULL` = NULL, então nem a promoção a super_admin barrava.
--
-- Somando a isso, o Postgres concede EXECUTE a PUBLIC por padrão em toda
-- função nova. As RPCs eram, portanto, alcançáveis com a chave `anon` — que
-- é pública por natureza, embarcada no bundle web publicado.
--
-- VERIFICADO EM 20/08/2026, com a chave anon, contra os três bancos:
--   AlinhaJá DEV e PROD  → admin_toggle_user_status, admin_update_user_role
--                          e admin_update_user retornaram 200 com corpo vazio
--                          (execução bem-sucedida). admin_reject_user passou
--                          da guarda e só abortou por um erro de coluna.
--   Fluxy                → as quatro passaram, e admin_reject_user COMPLETOU
--                          (inclui `DELETE FROM auth.users`). Lá também o
--                          admin_update_user_password passa da guarda.
--
-- `admin_update_user_password` entra aqui mesmo tendo `auth.uid() IS NULL`:
-- essa checagem cobre o anônimo, mas NÃO o usuário autenticado cuja linha em
-- `users` sumiu ou está inativa — nesse caso v_caller_role volta a ser NULL e
-- o `NOT IN` volta a deixar passar.
--
-- SOLUÇÃO (duas camadas, porque uma só não cobre todos os chamadores)
--   1. `fn_assert_admin()`: guarda única, NULL-safe, que também exige conta
--      ativa. Substitui a checagem copiada em cada função — copiar de novo é
--      justamente como o vício se espalhou.
--   2. REVOKE EXECUTE de PUBLIC/anon: corta o `anon` antes da função rodar.
--
-- BÔNUS: `admin_reject_user` referenciava `candidato.usuario_id`, coluna que
-- não existe em nenhum dos três bancos (a tabela tem `created_by`,
-- `updated_by`, `deleted_by` e `responsavel_id`). A função abortava com 42703
-- SEMPRE — rejeitar um cadastro estava quebrado no AlinhaJá.
-- ============================================================

-- ── 1. Guarda única de administrador ─────────────────────────
CREATE OR REPLACE FUNCTION public.fn_assert_admin(p_acao TEXT)
RETURNS public.user_role_level
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role public.user_role_level;
BEGIN
  -- Fail-closed explícito: sem sessão não há papel a consultar.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  SELECT role_level INTO v_role
  FROM public.users
  WHERE id = auth.uid()
    AND COALESCE(is_active, true) = true;

  -- `IS NULL` ANTES do `NOT IN`: sem isso, ausência de linha vira NULL e o
  -- teste devolve NULL em vez de TRUE, deixando passar. É o bug original.
  IF v_role IS NULL OR v_role NOT IN ('super_admin', 'admin') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas Administradores podem %.', p_acao;
  END IF;

  RETURN v_role;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_assert_admin(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_assert_admin(TEXT) TO authenticated;

-- ── 2. Derruba TODAS as sobrecargas antes de recriar ─────────
-- Por que por OID em vez de `DROP FUNCTION IF EXISTS public.f(sig)`: o banco
-- do Fluxy tem versões ANTIGAS dessas RPCs (o `admin_update_user_password` de
-- lá ainda lê a coluna `role`, que não existe mais). Um DROP com assinatura
-- fixa vira no-op se a assinatura viva for outra, e aí o CREATE abaixo criaria
-- uma SOBRECARGA em vez de substituir — deixando a versão vulnerável no ar e,
-- de quebra, tornando a chamada ambígua para o PostgREST.
--
-- Sem CASCADE de propósito: se algo passar a depender destas funções, o DROP
-- deve falhar alto em vez de derrubar o dependente em silêncio.
DO $do$
DECLARE
  v_fn TEXT;
BEGIN
  FOR v_fn IN
    SELECT p.oid::regprocedure::TEXT
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'admin_toggle_user_status',
        'admin_update_user_role',
        'admin_update_user',
        'admin_reject_user',
        'admin_update_user_password'
      )
  LOOP
    EXECUTE format('DROP FUNCTION %s', v_fn);
  END LOOP;
END
$do$;

-- ── 3. admin_toggle_user_status ──────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_toggle_user_status(
  p_target_user_id UUID,
  p_is_active BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.fn_assert_admin('arquivar contas');

  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode alterar o próprio status.';
  END IF;

  UPDATE public.users SET is_active = p_is_active WHERE id = p_target_user_id;

  IF p_is_active = FALSE THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = p_target_user_id;
  ELSE
    UPDATE auth.users SET banned_until = NULL WHERE id = p_target_user_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_toggle_user_status(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_toggle_user_status(UUID, BOOLEAN) TO authenticated;

-- ── 4. admin_update_user_role ────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_update_user_role(
  p_target_user_id UUID,
  p_new_role TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  v_caller_role := public.fn_assert_admin('alterar níveis de acesso');

  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode alterar seu próprio nível de acesso.';
  END IF;

  -- Com v_caller_role garantidamente não-nulo, este AND volta a ser decidível.
  IF p_new_role = 'super_admin' AND v_caller_role <> 'super_admin' THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas o Super Admin pode promover a este nível.';
  END IF;

  IF p_new_role NOT IN ('super_admin', 'admin', 'manager', 'member') THEN
    RAISE EXCEPTION 'Role inválido: %. Valores aceitos: super_admin, admin, manager, member', p_new_role;
  END IF;

  UPDATE public.users
  SET role_level = p_new_role::public.user_role_level
  WHERE id = p_target_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_user_role(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_user_role(UUID, TEXT) TO authenticated;

-- ── 5. admin_update_user ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_update_user(
  p_target_user_id UUID,
  p_full_name TEXT,
  p_branch_id UUID,
  p_role_level TEXT,
  p_department_id TEXT DEFAULT NULL,
  p_job_position_id TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  v_caller_role := public.fn_assert_admin('editar perfis');

  IF p_role_level = 'super_admin' AND v_caller_role <> 'super_admin' THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas o Super Admin pode promover a este nível.';
  END IF;

  UPDATE public.users
  SET
    full_name = p_full_name,
    branch_id = p_branch_id,
    role_level = p_role_level::public.user_role_level,
    department_id = p_department_id,
    job_position_id = p_job_position_id,
    updated_at = NOW()
  WHERE id = p_target_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_user(UUID, TEXT, UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_user(UUID, TEXT, UUID, TEXT, TEXT, TEXT) TO authenticated;

-- ── 6. admin_update_user_password ────────────────────────────
-- `search_path` inclui auth e extensions: a função cifra a senha com
-- extensions.crypt e escreve em auth.users.
CREATE OR REPLACE FUNCTION public.admin_update_user_password(
  p_target_user_id UUID,
  p_new_password TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
BEGIN
  PERFORM public.fn_assert_admin('redefinir senhas');

  IF p_new_password IS NULL OR length(trim(p_new_password)) < 6 THEN
    RAISE EXCEPTION 'A senha deve ter no mínimo 6 caracteres.';
  END IF;

  UPDATE auth.users
  SET encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf', 10)),
      updated_at = NOW()
  WHERE id = p_target_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuário não encontrado em auth.users.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_user_password(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_user_password(UUID, TEXT) TO authenticated;

-- ── 7. admin_reject_user ─────────────────────────────────────
-- Mesma guarda + correção do nome de coluna em `candidato`.
CREATE OR REPLACE FUNCTION public.admin_reject_user(
  p_target_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.fn_assert_admin('rejeitar cadastros');

  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode rejeitar seu próprio cadastro.';
  END IF;

  -- Desvincula o usuário de tabelas com chaves RESTRICT/NO ACTION
  UPDATE public.funcionario
    SET user_id = NULL, created_by = NULL, updated_by = NULL, deleted_by = NULL
    WHERE user_id = p_target_user_id OR created_by = p_target_user_id OR updated_by = p_target_user_id OR deleted_by = p_target_user_id;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'candidato') THEN
    -- `usuario_id` não existe nesta tabela e derrubava a função inteira.
    -- `candidato_usuario_id` fica de fora de propósito: aponta para
    -- `candidato_usuario`, o login do portal do candidato, não para `users`.
    UPDATE public.candidato
      SET responsavel_id = NULL, created_by = NULL, updated_by = NULL, deleted_by = NULL
      WHERE responsavel_id = p_target_user_id OR created_by = p_target_user_id OR updated_by = p_target_user_id OR deleted_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'vinculo') THEN
    UPDATE public.vinculo SET created_by = NULL WHERE created_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'rh_access_log') THEN
    UPDATE public.rh_access_log SET usuario_id = NULL WHERE usuario_id = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'workflow_cards') THEN
    UPDATE public.workflow_cards SET assigned_to = NULL, requested_by = NULL, approved_by = NULL WHERE assigned_to = p_target_user_id OR requested_by = p_target_user_id OR approved_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'workflow_card_history') THEN
    UPDATE public.workflow_card_history SET user_id = NULL WHERE user_id = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'chats') THEN
    UPDATE public.chats SET created_by = NULL WHERE created_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'location_tracking_settings') THEN
    UPDATE public.location_tracking_settings SET enabled_by = NULL WHERE enabled_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'titular_request') THEN
    UPDATE public.titular_request SET respondido_por = NULL WHERE respondido_por = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'fin_lancamento') THEN
    UPDATE public.fin_lancamento SET created_by = NULL WHERE created_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'fin_conta_bancaria') THEN
    UPDATE public.fin_conta_bancaria SET created_by = NULL WHERE created_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'rh_documento') THEN
    UPDATE public.rh_documento SET aceito_por = NULL WHERE aceito_por = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'audit_log') THEN
    UPDATE public.audit_log SET actor_id = NULL WHERE actor_id = p_target_user_id;
  END IF;

  -- Remove o usuário do auth.users (desencadeia cascade para public.users)
  DELETE FROM auth.users WHERE id = p_target_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reject_user(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_user(UUID) TO authenticated;

-- ── 8. approve_workflow_card ─────────────────────────────────
-- Mesma família de vício, forma diferente: a trava era `IF v_role_level =
-- 'member' THEN RAISE` — uma lista de NEGAÇÃO. Papel desconhecido (NULL) não
-- é igual a 'member', então passava. O app não chama mais esta RPC, então em
-- vez de reescrevê-la basta tirá-la do alcance do anônimo; se um dia voltar a
-- ser usada, a guarda de dentro precisa ser refeita nos moldes acima.
DO $do$
DECLARE
  v_fn TEXT;
BEGIN
  FOR v_fn IN
    SELECT p.oid::regprocedure::TEXT
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'approve_workflow_card'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_fn);
  END LOOP;
END
$do$;
