-- ============================================================
-- Sucessão do admin de canal e avisos de recusa (16/09/2026 — v1.3.9)
--
-- 1. O último admin não sai sem escolher um sucessor
--    Qualquer membro podia apagar a própria participação. Quando era o único
--    admin, o canal ficava sem ninguém para aprovar pedidos, gerir membros ou
--    editar etapas. Agora a saída passa por `leave_channel`, que promove o
--    sucessor escolhido antes de remover quem sai. O DELETE direto do único
--    admin é recusado por policy restritiva.
--
-- 2. Pedido de entrada recusado avisa o solicitante
--    A recusa continua apagando o pedido (o usuário pode pedir de novo), mas
--    agora dispara um push para quem pediu.
--
-- 3. Cadastro pendente recusado avisa por e-mail
--    O cadastro pendente fica banido até a aprovação, então a pessoa nunca
--    teve login nem token de push: o aviso vai para o e-mail do cadastro.
--
-- Os avisos saem pela Edge Function `send-account-notification`, chamada com
-- o x-webhook-secret como os demais triggers de notificação.
-- ============================================================

-- ── 1. Disparo de aviso para a Edge Function ────────────────
CREATE OR REPLACE FUNCTION public.fn_notify_account_event(p_payload JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_base TEXT := public.get_edge_base_url();
BEGIN
  -- Mesmo projeto dos demais triggers de notificação deste fork.
  IF v_base = '' THEN
    v_base := 'https://gpeemngsxvqjflasdody.supabase.co';
  END IF;
  -- O segredo deve guardar a URL raiz (docs/SECRETS-RH.md); tolera quem
  -- gravou com /functions/v1 ou barra no fim.
  v_base := regexp_replace(v_base, '/+(functions/v1/*)?$', '');

  PERFORM net.http_post(
    url := v_base || '/functions/v1/send-account-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.get_webhook_secret()
    ),
    body := p_payload
  );
EXCEPTION WHEN OTHERS THEN
  -- O aviso é acessório: falhar aqui não pode desfazer a recusa ou a saída.
  RAISE WARNING 'Aviso de conta não enviado (%): %', p_payload->>'kind', SQLERRM;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_notify_account_event(JSONB) FROM PUBLIC, anon, authenticated;

-- ── 2. Único admin do canal ─────────────────────────────────
-- "Único" só importa quando há mais alguém no canal: o último membro que sai
-- sozinho não deixa ninguém sem administração.
CREATE OR REPLACE FUNCTION public.channel_member_is_sole_admin(
  p_channel_id UUID,
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.channel_members me
    WHERE me.channel_id = p_channel_id
      AND me.user_id = p_user_id
      AND me.role = 'admin'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.channel_members other
    WHERE other.channel_id = p_channel_id
      AND other.user_id <> p_user_id
      AND other.role = 'admin'
  )
  AND EXISTS (
    SELECT 1 FROM public.channel_members other
    WHERE other.channel_id = p_channel_id
      AND other.user_id <> p_user_id
  );
$$;

REVOKE ALL ON FUNCTION public.channel_member_is_sole_admin(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.channel_member_is_sole_admin(UUID, UUID) TO authenticated;

-- Vale só para o DELETE feito pelo próprio usuário via API. Funções
-- SECURITY DEFINER (excluir canal, remover membro, excluir conta) rodam como
-- dono da tabela e não passam por RLS.
DROP POLICY IF EXISTS "Unico admin nao sai sem sucessor" ON public.channel_members;
CREATE POLICY "Unico admin nao sai sem sucessor"
  ON public.channel_members
  AS RESTRICTIVE
  FOR DELETE
  USING (NOT public.channel_member_is_sole_admin(channel_id, user_id));

-- ── 3. Sair do canal ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.leave_channel(
  p_channel_id UUID,
  p_successor_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_channel_name TEXT;
  v_leaver_name TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.channel_members
    WHERE channel_id = p_channel_id AND user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'Você não participa deste canal.';
  END IF;

  IF public.channel_member_is_sole_admin(p_channel_id, v_uid) THEN
    -- Código estável: o app reconhece e abre a escolha do sucessor.
    IF p_successor_id IS NULL THEN
      RAISE EXCEPTION 'SUCCESSOR_REQUIRED: escolha quem vai administrar o canal antes de sair.';
    END IF;

    IF p_successor_id = v_uid OR NOT EXISTS (
      SELECT 1 FROM public.channel_members
      WHERE channel_id = p_channel_id AND user_id = p_successor_id
    ) THEN
      RAISE EXCEPTION 'O sucessor precisa ser outro membro do canal.';
    END IF;

    -- A troca de papel é auditada pelo trigger de membresia.
    UPDATE public.channel_members
    SET role = 'admin'
    WHERE channel_id = p_channel_id AND user_id = p_successor_id;

    SELECT name INTO v_channel_name FROM public.channels WHERE id = p_channel_id;
    SELECT full_name INTO v_leaver_name FROM public.users WHERE id = v_uid;

    PERFORM public.fn_notify_account_event(jsonb_build_object(
      'kind', 'channel_admin_transferred',
      'user_id', p_successor_id,
      'channel_id', p_channel_id,
      'channel_name', COALESCE(v_channel_name, 'Canal'),
      'actor_name', COALESCE(v_leaver_name, '')
    ));
  END IF;

  DELETE FROM public.channel_members
  WHERE channel_id = p_channel_id AND user_id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.leave_channel(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leave_channel(UUID, UUID) TO authenticated;

-- ── 4. Pedido de entrada recusado ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_notify_channel_join_rejected()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_channel_name TEXT;
BEGIN
  -- Recusa é a exclusão de um pedido pendente por outra pessoa. Ficam de fora:
  --   * o próprio usuário limpando o pedido dele;
  --   * exclusão em cascata do canal ou da conta (a linha-mãe já não existe
  --     quando o trigger roda — não houve recusa, e sim remoção).
  IF OLD.status IS DISTINCT FROM 'pending'
     OR auth.uid() IS NULL
     OR auth.uid() = OLD.user_id THEN
    RETURN OLD;
  END IF;

  SELECT name INTO v_channel_name FROM public.channels WHERE id = OLD.channel_id;
  IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.user_id) THEN
    RETURN OLD;
  END IF;

  PERFORM public.fn_notify_account_event(jsonb_build_object(
    'kind', 'channel_join_rejected',
    'user_id', OLD.user_id,
    'channel_id', OLD.channel_id,
    'channel_name', COALESCE(v_channel_name, 'Canal')
  ));
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_channel_join_rejected ON public.channel_join_requests;
CREATE TRIGGER trg_notify_channel_join_rejected
  AFTER DELETE ON public.channel_join_requests
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_channel_join_rejected();

-- ── 5. Cadastro pendente recusado: aviso por e-mail ─────────
-- Corpo idêntico ao de 20260916120000, com o aviso antes da exclusão.
CREATE OR REPLACE FUNCTION public.admin_reject_user(
  p_target_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT;
  v_full_name TEXT;
  v_never_signed_in BOOLEAN;
BEGIN
  PERFORM public.fn_assert_admin('rejeitar cadastros');
  PERFORM public.fn_assert_same_org(p_target_user_id);

  -- Aviso ao candidato recusado (v1.3.9). Vai antes da exclusão: depois dela
  -- não há mais e-mail nem nome para escrever. Só para quem nunca entrou —
  -- cadastro pendente fica banido até a aprovação, então nunca tem login.
  -- Conta antiga removida por este caminho não recebe "cadastro recusado".
  SELECT au.email, COALESCE(pu.full_name, ''), au.last_sign_in_at IS NULL
    INTO v_email, v_full_name, v_never_signed_in
  FROM auth.users au
  LEFT JOIN public.users pu ON pu.id = au.id
  WHERE au.id = p_target_user_id;

  IF v_email IS NOT NULL AND v_never_signed_in THEN
    PERFORM public.fn_notify_account_event(jsonb_build_object(
      'kind', 'signup_rejected',
      'email', v_email,
      'full_name', v_full_name
    ));
  END IF;

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
