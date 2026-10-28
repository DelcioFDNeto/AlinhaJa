-- ============================================================
-- Trilha de auditoria de workspace e canal  (F-04 + F-05)
--
-- ## F-04a — histórico do card só existia dentro de uma RPC
-- `workflow_card_history` era escrito exclusivamente por
-- `update_workflow_card_status`. Não havia trigger. Como o app altera
-- responsável, fixação e arquivamento por UPDATE direto na tabela
-- (workflow_provider.dart:590, 618, 658), essas operações não geravam
-- histórico NEM NO USO NORMAL — justamente "quem assumiu, quando e quem
-- reatribuiu", que é a pergunta de auditoria numa operação financeira.
--
-- A correção é por trigger, não por disciplina de chamada: assim
-- nenhum caminho de escrita escapa, nem hoje nem numa tela futura.
--
-- Para não duplicar a linha que a RPC já grava, o trigger ignora
-- `status` — esse campo continua sendo responsabilidade da RPC, que
-- registra o motivo (`observations`) junto.
--
-- ## F-04b — entrada e saída de canal não deixavam rastro
-- `audit_log` (imutável, append-only) cobria só users, messages e
-- location_tracking_settings. Membresia de canal passa a ser auditada
-- pelo mesmo `fn_audit`.
--
-- ## F-05 — as regras finas da RPC eram contornáveis
-- `update_workflow_card_status` valida o que a RLS não valida: o status
-- precisa existir na configuração do workspace, só o responsável ou um
-- gestor muda, e o solicitante nunca opera o próprio card. Mas a policy
-- de UPDATE deixava o responsável alterar QUALQUER coluna — inclusive
-- `status` — direto na tabela, pulando tudo isso.
--
-- Fecha-se por privilégio de coluna: revoga-se UPDATE amplo e concede-se
-- de volta coluna a coluna, menos `status`. A RPC é SECURITY DEFINER e
-- roda como dona da tabela, então segue funcionando.
-- ============================================================

-- ── 1. F-04a: histórico do card por diferença de colunas ─────
CREATE OR REPLACE FUNCTION public.fn_tg_workflow_card_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  IF NEW.assigned_to IS DISTINCT FROM OLD.assigned_to THEN
    INSERT INTO public.workflow_card_history
      (card_id, user_id, action, field_changed, old_value, new_value)
    VALUES (
      NEW.id, v_actor,
      CASE
        WHEN OLD.assigned_to IS NULL THEN 'Card assumido'
        WHEN NEW.assigned_to IS NULL THEN 'Responsavel removido'
        ELSE 'Card reatribuido'
      END,
      'assigned_to',
      OLD.assigned_to::TEXT, NEW.assigned_to::TEXT
    );
  END IF;

  IF NEW.is_archived IS DISTINCT FROM OLD.is_archived THEN
    INSERT INTO public.workflow_card_history
      (card_id, user_id, action, field_changed, old_value, new_value)
    VALUES (
      NEW.id, v_actor,
      CASE WHEN NEW.is_archived THEN 'Card arquivado' ELSE 'Card desarquivado' END,
      'is_archived',
      OLD.is_archived::TEXT, NEW.is_archived::TEXT
    );
  END IF;

  IF NEW.priority IS DISTINCT FROM OLD.priority THEN
    INSERT INTO public.workflow_card_history
      (card_id, user_id, action, field_changed, old_value, new_value)
    VALUES (NEW.id, v_actor, 'Prioridade alterada', 'priority',
            OLD.priority::TEXT, NEW.priority::TEXT);
  END IF;

  IF NEW.due_date IS DISTINCT FROM OLD.due_date THEN
    INSERT INTO public.workflow_card_history
      (card_id, user_id, action, field_changed, old_value, new_value)
    VALUES (NEW.id, v_actor, 'Prazo alterado', 'due_date',
            OLD.due_date::TEXT, NEW.due_date::TEXT);
  END IF;

  -- `status` de propósito fora: quem registra é
  -- update_workflow_card_status, que grava o motivo junto. Duplicar
  -- aqui produziria duas linhas por mudança.
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_workflow_card_history ON public.workflow_cards;
CREATE TRIGGER trg_workflow_card_history
  AFTER UPDATE ON public.workflow_cards
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_workflow_card_history();

COMMENT ON FUNCTION public.fn_tg_workflow_card_history() IS
  'Histórico de card por diferença de colunas. Existe para que nenhum caminho '
  'de escrita escape — o app altera responsável e arquivamento por UPDATE '
  'direto, sem passar por RPC. Ignora `status`, gravado por '
  'update_workflow_card_status com o motivo.';

-- ── 2. F-04b: membresia de canal no audit_log ────────────────
CREATE OR REPLACE FUNCTION public.fn_audit_channel_membership()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.fn_audit(
      'channel_member_added',
      'channel_members',
      NEW.channel_id::TEXT,
      jsonb_build_object('user_id', NEW.user_id, 'role', NEW.role)
    );
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    PERFORM public.fn_audit(
      'channel_member_removed',
      'channel_members',
      OLD.channel_id::TEXT,
      jsonb_build_object('user_id', OLD.user_id, 'role', OLD.role)
    );
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.role IS DISTINCT FROM OLD.role THEN
    PERFORM public.fn_audit(
      'channel_member_role_changed',
      'channel_members',
      NEW.channel_id::TEXT,
      jsonb_build_object('user_id', NEW.user_id,
                         'old_role', OLD.role, 'new_role', NEW.role)
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_channel_membership ON public.channel_members;
CREATE TRIGGER trg_audit_channel_membership
  AFTER INSERT OR UPDATE OR DELETE ON public.channel_members
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_channel_membership();

-- ── 3. F-05: `status` só muda pela RPC ───────────────────────
-- Privilégio por coluna: sem UPDATE em `status`, um PATCH direto na
-- tabela é recusado pelo Postgres antes mesmo da RLS. A RPC é SECURITY
-- DEFINER e roda como dona da tabela, então não é afetada.
--
-- A concessão é "todas as colunas MENOS status", derivada do catálogo —
-- e não uma lista fixa. `workflow_cards` tem dezenas de campos
-- específicos por tipo de card (supplier, amount, os_number, plate,
-- chassis_number...) e uma allowlist escrita à mão quebraria a edição
-- de card no dia em que alguém acrescentasse um campo novo.
DO $$
DECLARE
  v_col TEXT;
BEGIN
  REVOKE UPDATE ON public.workflow_cards FROM authenticated;

  FOR v_col IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'workflow_cards'
      AND column_name <> 'status'
  LOOP
    EXECUTE format(
      'GRANT UPDATE (%I) ON public.workflow_cards TO authenticated', v_col);
  END LOOP;
END $$;

COMMENT ON TABLE public.workflow_cards IS
  'Cards de workspace. `status` NÃO tem privilégio de UPDATE para authenticated: '
  'a mudança de etapa passa obrigatoriamente por update_workflow_card_status, '
  'que valida etapa configurada, papel e a regra de o solicitante não operar o '
  'próprio card. Ver 20260821120000.';
