-- ============================================================
-- Moderação com caminho legítimo e auditado (achado 1.6)
--
-- PROBLEMA
-- moderation_screen.dart consulta `messages` sem filtro de conversa e
-- confia na RLS. Só que a policy é `is_chat_member(chat_id)` — então o
-- admin recebe APENAS as próprias conversas, acreditando estar moderando
-- a empresa. Não é vazamento: é o oposto, e é pior, porque produz uma
-- falsa sensação de controle. Na prática não existia nenhum caminho
-- para moderar conteúdo.
--
-- DESENHO
-- Uma RPC SECURITY DEFINER, restrita a admin+, que:
--   • exige justificativa por escrito (não há moderação anônima);
--   • registra CADA consulta em audit_log, com termo e escopo;
--   • devolve no máximo o que foi pedido, com teto rígido.
--
-- A RLS de `messages` continua intacta: afrouxá-la daria a todo admin
-- leitura silenciosa de qualquer DM. Aqui o acesso é possível, mas
-- nunca invisível — é o registro que torna o poder aceitável.
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_search_messages(
  p_justificativa text,
  p_termo         text DEFAULT NULL,
  p_chat_id       uuid DEFAULT NULL,
  p_autor_id      uuid DEFAULT NULL,
  p_desde         timestamptz DEFAULT NULL,
  p_ate           timestamptz DEFAULT NULL,
  p_limit         int DEFAULT 100
)
RETURNS TABLE (
  id           uuid,
  chat_id      uuid,
  sender_id    uuid,
  sender_name  text,
  content      text,
  content_type text,
  created_at   timestamptz,
  deleted_at   timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org   uuid;
  v_limit int := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
BEGIN
  -- Multi-tenant: papel pela linha do usuário, escopo por fn_current_org().
  -- O dono da plataforma modera a empresa em que está atuando, nunca a base
  -- inteira (20260728100000_platform_acting_org.sql).
  IF NOT EXISTS (
    SELECT 1 FROM public.users u
     WHERE u.id = auth.uid()
       AND u.role_level IN ('super_admin', 'admin')
       AND u.is_active
  ) THEN
    RAISE EXCEPTION 'Acesso restrito a administradores';
  END IF;

  v_org := public.fn_current_org();

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Organização do usuário não resolvida';
  END IF;

  -- Justificativa obrigatória: é o que transforma a consulta em ato
  -- administrativo rastreável em vez de bisbilhotice.
  IF p_justificativa IS NULL OR length(trim(p_justificativa)) < 10 THEN
    RAISE EXCEPTION
      'Informe uma justificativa (mínimo 10 caracteres) para a consulta de moderação';
  END IF;

  -- Exige ao menos um critério: impede varredura geral da base.
  IF p_termo IS NULL AND p_chat_id IS NULL AND p_autor_id IS NULL THEN
    RAISE EXCEPTION
      'Informe ao menos um critério (termo, conversa ou autor)';
  END IF;

  PERFORM public.fn_audit(
    'moderation.search', 'message', NULL,
    jsonb_build_object(
      'justificativa', p_justificativa,
      'termo',         p_termo,
      'chat_id',       p_chat_id,
      'autor_id',      p_autor_id,
      'desde',         p_desde,
      'ate',           p_ate));

  RETURN QUERY
    SELECT m.id, m.chat_id, m.sender_id, s.full_name,
           m.content, m.content_type::text, m.created_at, m.deleted_at
      FROM public.messages m
      JOIN public.users s ON s.id = m.sender_id
     WHERE s.organization_id = v_org
       AND (p_termo    IS NULL OR m.content ILIKE '%' || p_termo || '%')
       AND (p_chat_id  IS NULL OR m.chat_id = p_chat_id)
       AND (p_autor_id IS NULL OR m.sender_id = p_autor_id)
       AND (p_desde    IS NULL OR m.created_at >= p_desde)
       AND (p_ate      IS NULL OR m.created_at <= p_ate)
     ORDER BY m.created_at DESC
     LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_search_messages(
  text, text, uuid, uuid, timestamptz, timestamptz, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_search_messages(
  text, text, uuid, uuid, timestamptz, timestamptz, int) TO authenticated;

COMMENT ON FUNCTION public.admin_search_messages(
  text, text, uuid, uuid, timestamptz, timestamptz, int) IS
  'Busca de moderação/eDiscovery. Exige admin+ e justificativa; registra cada consulta em audit_log.';

-- ── Remoção de conteúdo pela moderação ───────────────────────
-- O soft delete direto na tabela esbarra na RLS (só o autor atualiza).
-- Esta RPC dá ao admin o caminho explícito e auditado.
CREATE OR REPLACE FUNCTION public.admin_moderate_message(
  p_message_id    uuid,
  p_justificativa text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
BEGIN
  -- Multi-tenant: papel pela linha do usuário, escopo por fn_current_org().
  -- O dono da plataforma modera a empresa em que está atuando, nunca a base
  -- inteira (20260728100000_platform_acting_org.sql).
  IF NOT EXISTS (
    SELECT 1 FROM public.users u
     WHERE u.id = auth.uid()
       AND u.role_level IN ('super_admin', 'admin')
       AND u.is_active
  ) THEN
    RAISE EXCEPTION 'Acesso restrito a administradores';
  END IF;

  v_org := public.fn_current_org();

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Organização do usuário não resolvida';
  END IF;

  IF p_justificativa IS NULL OR length(trim(p_justificativa)) < 10 THEN
    RAISE EXCEPTION 'Informe uma justificativa (mínimo 10 caracteres)';
  END IF;

  UPDATE public.messages m
     SET deleted_at = NOW()
   WHERE m.id = p_message_id
     AND EXISTS (
       SELECT 1 FROM public.users s
        WHERE s.id = m.sender_id AND s.organization_id = v_org
     );

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mensagem não encontrada nesta organização';
  END IF;

  PERFORM public.fn_audit(
    'moderation.delete', 'message', p_message_id::text,
    jsonb_build_object('justificativa', p_justificativa));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_moderate_message(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_moderate_message(uuid, text) TO authenticated;
