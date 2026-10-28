-- ============================================================
-- Auditoria de segurança de 16/09/2026
--
-- Achados corrigidos aqui (a parte das Edge Functions está no mesmo commit):
--
--   1. RPCs SECURITY DEFINER que confiavam num p_user_id do cliente:
--        mark_messages_as_read(p_chat_id, p_user_id)
--        mark_all_chats_as_read(p_user_id)
--        log_user_activity(p_user_id, ...)
--      Qualquer usuário logado falsificava recibos de leitura em conversas
--      de terceiros e registrava atividade em nome de outra pessoa
--      (integridade da trilha de auditoria).
--
--   2. RPCs de workflow sem guarda nenhuma:
--        update_workflow_status — mudava o status de qualquer card e gravava
--          qualquer autor no histórico. O app não chama: EXECUTE revogado.
--        get_workflow_cards — listava cards de qualquer canal. O app não
--          chama: EXECUTE revogado.
--        get_workflow_metrics — contagens e soma de valores de qualquer
--          canal. Passa a SECURITY INVOKER: a RLS de workflow_cards
--          ("Membros veem cards do canal") decide o que entra na conta.
--
--   3. meeting_transcriptions aceitava INSERT de qualquer um em qualquer
--      reunião (WITH CHECK (true)). O webhook usa service_role e não depende
--      de policy; para usuários, só a própria fala em reunião visível.
--
--   4. RPCs administrativas sem limite de organização: um admin redefinia
--      senha, papel, status ou excluía usuários de OUTRA organização.
--      Nova guarda fn_assert_same_org(); o dono da plataforma continua
--      global, como no console de plataforma.
--
-- Nota sobre REVOKE: o Supabase concede EXECUTE a `anon` e `authenticated`
-- por default privileges, não só a PUBLIC. `REVOKE ... FROM PUBLIC` sozinho
-- deixa o `anon` com acesso — por isso os REVOKEs abaixo nomeiam os papéis.
-- ============================================================

-- ── 1.1 mark_messages_as_read ────────────────────────────────
CREATE OR REPLACE FUNCTION public.mark_messages_as_read(p_chat_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Mesmo contrato de mark_messages_as_delivered: só o próprio usuário
  -- confirma as suas leituras, e só em conversa da qual é membro.
  IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não é permitido confirmar leituras de outro usuário';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.chat_members cm
    WHERE cm.chat_id = p_chat_id AND cm.user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'Sem acesso a esta conversa';
  END IF;

  UPDATE public.messages
  SET
      status = 'read',
      read_by = array_append(ARRAY(SELECT DISTINCT e FROM unnest(read_by) e), p_user_id)
  WHERE
      chat_id = p_chat_id
      AND sender_id != p_user_id
      AND NOT (read_by @> ARRAY[p_user_id]);
END;
$$;

REVOKE ALL ON FUNCTION public.mark_messages_as_read(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(uuid, uuid) TO authenticated;

-- ── 1.2 mark_all_chats_as_read ───────────────────────────────
CREATE OR REPLACE FUNCTION public.mark_all_chats_as_read(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não é permitido confirmar leituras de outro usuário';
  END IF;

  UPDATE public.chat_members
  SET last_read_at = NOW()
  WHERE user_id = p_user_id;

  UPDATE public.messages
  SET status = 'read'
  WHERE chat_id IN (SELECT chat_id FROM public.chat_members WHERE user_id = p_user_id)
  AND sender_id != p_user_id
  AND status != 'read';
END;
$$;

REVOKE ALL ON FUNCTION public.mark_all_chats_as_read(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_all_chats_as_read(uuid) TO authenticated;

-- ── 1.3 log_user_activity ────────────────────────────────────
-- A assinatura fica igual (o app passa p_user_id), mas só o próprio usuário
-- registra — o mesmo que a policy de INSERT de user_activities já exige.
CREATE OR REPLACE FUNCTION public.log_user_activity(
    p_user_id UUID,
    p_activity_type TEXT,
    p_description TEXT DEFAULT NULL,
    p_target_id TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não é permitido registrar atividade de outro usuário';
  END IF;

  INSERT INTO public.user_activities (user_id, activity_type, description, target_id)
  VALUES (p_user_id, p_activity_type, p_description, p_target_id);
END;
$$;

REVOKE ALL ON FUNCTION public.log_user_activity(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.log_user_activity(uuid, text, text, text) TO authenticated;

-- ── 2. RPCs de workflow ──────────────────────────────────────
-- Por OID: revoga toda sobrecarga viva, qualquer que seja a assinatura.
DO $do$
DECLARE
  v_fn TEXT;
BEGIN
  FOR v_fn IN
    SELECT p.oid::regprocedure::TEXT
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('update_workflow_status', 'get_workflow_cards')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_fn);
  END LOOP;
END
$do$;

ALTER FUNCTION public.get_workflow_metrics(uuid) SECURITY INVOKER;
REVOKE ALL ON FUNCTION public.get_workflow_metrics(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_workflow_metrics(uuid) TO authenticated;

-- ── 3. meeting_transcriptions ────────────────────────────────
DROP POLICY IF EXISTS "Service can insert transcriptions" ON public.meeting_transcriptions;
DROP POLICY IF EXISTS "Participantes inserem a propria transcricao" ON public.meeting_transcriptions;
CREATE POLICY "Participantes inserem a propria transcricao"
  ON public.meeting_transcriptions FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    -- O subselect roda sob a RLS de meetings ("Membros podem ver reuniões"):
    -- só passa anfitrião, quem chamou ou membro do chat/canal da reunião.
    AND EXISTS (
      SELECT 1 FROM public.meetings m
      WHERE m.id = meeting_transcriptions.meeting_id
    )
  );

-- ── 4. Guarda de organização das RPCs administrativas ────────
CREATE OR REPLACE FUNCTION public.fn_assert_same_org(p_target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- O dono da plataforma administra todas as organizações pelo console.
  IF public.fn_is_platform_owner() THEN
    RETURN;
  END IF;

  -- `users.organization_id` é NOT NULL e fn_current_org() vem da sessão.
  -- Alvo inexistente e alvo de outra organização caem no mesmo erro, sem
  -- revelar qual dos dois é o caso.
  IF NOT EXISTS (
    SELECT 1 FROM public.users t
    WHERE t.id = p_target_user_id
      AND t.organization_id = public.fn_current_org()
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não pertence à sua organização.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_assert_same_org(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_assert_same_org(UUID) TO authenticated;

-- ── 5. RPCs administrativas com a guarda ─────────────────────
-- Corpo idêntico ao de 20260820100000_fix_admin_rpc_null_role_bypass.sql,
-- com uma linha a mais logo após fn_assert_admin(). Assinaturas iguais:
-- CREATE OR REPLACE substitui sem criar sobrecarga.

-- ── 5.1 admin_toggle_user_status ──────────────────────────────
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
  PERFORM public.fn_assert_same_org(p_target_user_id);

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

-- ── 5.2 admin_update_user_role ────────────────────────────────
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
  PERFORM public.fn_assert_same_org(p_target_user_id);

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

-- ── 5.3 admin_update_user ─────────────────────────────────────
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
  PERFORM public.fn_assert_same_org(p_target_user_id);

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

-- ── 5.4 admin_update_user_password ────────────────────────────
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
  PERFORM public.fn_assert_same_org(p_target_user_id);

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

-- ── 5.5 admin_reject_user ─────────────────────────────────────
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
  PERFORM public.fn_assert_same_org(p_target_user_id);

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
