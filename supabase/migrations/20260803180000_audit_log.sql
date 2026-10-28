-- ============================================================
-- Registro das operações de tratamento (achado 2.4 — LGPD Art. 37)
--
-- PROBLEMA
-- `rh_access_log` cobre o módulo de RH. Fora dele nada era registrado:
-- promoção/rebaixamento de usuário, desativação de conta, exclusão de
-- mensagem por admin, ativação de rastreamento GPS de terceiro, export
-- de backup. `user_activity_history` não serve — é auto-declarado pelo
-- app e a policy só deixa o próprio usuário ler.
--
-- Sem isso não há como responder a um titular ou à ANPD "quem acessou o
-- quê, quando". É também o que sustenta a defesa de que existem medidas
-- de segurança (Art. 46).
--
-- DESENHO
-- Tabela append-only: sem policy de UPDATE/DELETE e com trigger que
-- barra os dois mesmo para quem tiver privilégio de tabela. Escrita
-- exclusivamente por fn_audit() (SECURITY DEFINER) — o app não insere
-- direto, então não consegue forjar nem omitir entrada.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.audit_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES public.organizations(id),
  actor_id        UUID REFERENCES public.users(id),
  action          TEXT NOT NULL,
  target_type     TEXT,
  target_id       TEXT,
  details         JSONB NOT NULL DEFAULT '{}',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_org_time
  ON public.audit_log(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor
  ON public.audit_log(actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_target
  ON public.audit_log(target_type, target_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_action
  ON public.audit_log(action, created_at DESC);

COMMENT ON TABLE public.audit_log IS
  'Registro imutável de operações sensíveis (LGPD Art. 37). Escrita apenas via fn_audit().';

-- ── 1. Imutabilidade ─────────────────────────────────────────
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.fn_audit_log_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'audit_log é append-only: % não é permitido', TG_OP;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_log_no_update ON public.audit_log;
CREATE TRIGGER trg_audit_log_no_update
  BEFORE UPDATE OR DELETE ON public.audit_log
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log_append_only();

-- Leitura: apenas admin+ da própria org. Ninguém escreve direto.
-- Multi-tenant: a org vem de fn_current_org(), não da linha do usuário, para
-- que o dono da plataforma em "empresa em atuação" leia a auditoria da
-- empresa visitada (20260728100000_platform_acting_org.sql).
DROP POLICY IF EXISTS "Admin lê auditoria da própria org" ON public.audit_log;
CREATE POLICY "Admin lê auditoria da própria org"
  ON public.audit_log FOR SELECT
  USING (
    organization_id = public.fn_current_org()
    AND EXISTS (
      SELECT 1 FROM public.users u
       WHERE u.id = auth.uid()
         AND u.role_level IN ('super_admin', 'admin')
         AND u.is_active
    )
  );

REVOKE INSERT, UPDATE, DELETE ON public.audit_log FROM authenticated, anon;

-- ── 2. Helper de escrita ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_audit(
  p_action      text,
  p_target_type text DEFAULT NULL,
  p_target_id   text DEFAULT NULL,
  p_details     jsonb DEFAULT '{}',
  p_actor_id    uuid  DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := COALESCE(p_actor_id, auth.uid());
  v_org   uuid;
BEGIN
  -- Multi-tenant: quando o ator é o próprio chamador, a entrada pertence à
  -- empresa EM ATUAÇÃO (fn_current_org) — é onde o ato aconteceu e onde o
  -- admin daquela empresa precisa enxergá-lo. Com p_actor_id explícito
  -- (auditoria em nome de terceiro) vale a org natal do ator.
  IF p_actor_id IS NULL OR p_actor_id = auth.uid() THEN
    v_org := public.fn_current_org();
  ELSE
    SELECT u.organization_id INTO v_org
      FROM public.users u WHERE u.id = v_actor;
  END IF;

  INSERT INTO public.audit_log
    (organization_id, actor_id, action, target_type, target_id, details)
  VALUES (v_org, v_actor, p_action, p_target_type, p_target_id,
          COALESCE(p_details, '{}'::jsonb));
EXCEPTION WHEN OTHERS THEN
  -- Auditoria nunca pode derrubar a operação auditada. Falha de log é
  -- registrada como warning; a ação segue.
  RAISE WARNING 'fn_audit falhou para a ação %: %', p_action, SQLERRM;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_audit(text, text, text, jsonb, uuid)
  FROM PUBLIC, anon;

-- ── 3. Gatilhos nas mudanças que importam ────────────────────
-- Promoção/rebaixamento e ativação/desativação de conta são as duas
-- alterações de `users` com impacto direto em quem enxerga o quê.
CREATE OR REPLACE FUNCTION public.fn_audit_users_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.role_level IS DISTINCT FROM OLD.role_level THEN
    PERFORM public.fn_audit(
      'user.role_changed', 'user', NEW.id::text,
      jsonb_build_object('de', OLD.role_level, 'para', NEW.role_level));
  END IF;

  IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
    PERFORM public.fn_audit(
      CASE WHEN NEW.is_active THEN 'user.activated' ELSE 'user.deactivated' END,
      'user', NEW.id::text,
      jsonb_build_object('de', OLD.is_active, 'para', NEW.is_active));
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_users_changes ON public.users;
CREATE TRIGGER trg_audit_users_changes
  AFTER UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_users_changes();

-- Ativar rastreamento GPS de um funcionário é decisão sensível e
-- precisa de rastro de quem decidiu.
CREATE OR REPLACE FUNCTION public.fn_audit_tracking_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.is_enabled IS DISTINCT FROM OLD.is_enabled THEN
    PERFORM public.fn_audit(
      CASE WHEN NEW.is_enabled THEN 'gps.enabled' ELSE 'gps.disabled' END,
      'user', NEW.user_id::text,
      jsonb_build_object('intervalo_min', NEW.interval_minutes));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_tracking_changes ON public.location_tracking_settings;
CREATE TRIGGER trg_audit_tracking_changes
  AFTER INSERT OR UPDATE ON public.location_tracking_settings
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_tracking_changes();

-- Exclusão de mensagem (soft delete) por quem não é o autor: é o caso
-- de moderação e precisa aparecer na auditoria.
CREATE OR REPLACE FUNCTION public.fn_audit_message_moderation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.deleted_at IS NOT NULL
     AND OLD.deleted_at IS NULL
     AND auth.uid() IS DISTINCT FROM NEW.sender_id THEN
    PERFORM public.fn_audit(
      'message.moderated', 'message', NEW.id::text,
      jsonb_build_object('chat_id', NEW.chat_id, 'autor', NEW.sender_id));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_message_moderation ON public.messages;
CREATE TRIGGER trg_audit_message_moderation
  AFTER UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_message_moderation();

-- ── 4. Consulta pelo painel ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_audit_log(
  p_limit  int DEFAULT 200,
  p_action text DEFAULT NULL
)
RETURNS TABLE (
  id          uuid,
  actor_id    uuid,
  actor_name  text,
  action      text,
  target_type text,
  target_id   text,
  details     jsonb,
  created_at  timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
BEGIN
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

  RETURN QUERY
    SELECT a.id, a.actor_id, act.full_name, a.action,
           a.target_type, a.target_id, a.details, a.created_at
      FROM public.audit_log a
      LEFT JOIN public.users act ON act.id = a.actor_id
     WHERE a.organization_id = v_org
       AND (p_action IS NULL OR a.action = p_action)
     ORDER BY a.created_at DESC
     LIMIT LEAST(GREATEST(p_limit, 1), 1000);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_audit_log(int, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_audit_log(int, text) TO authenticated;
