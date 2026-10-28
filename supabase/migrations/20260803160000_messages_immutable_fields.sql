-- ============================================================
-- Mensagem não pode trocar de dono nem de conversa (achado 1.7)
--
-- PROBLEMA
-- A policy de UPDATE em `messages` chama-se "Autor pode apagar (soft
-- delete) a mensagem", mas é apenas `USING (sender_id = auth.uid())`.
-- RLS opera na LINHA, não na coluna: o autor podia atualizar QUALQUER
-- campo via REST direto. Duas consequências reais:
--
--   1. Reescrever o conteúdo de uma mensagem antiga sem deixar rastro —
--      grave num canal de comunicação oficial, onde a mensagem é a prova
--      do que foi combinado.
--   2. Alterar `chat_id`, movendo a própria mensagem para uma conversa
--      de que não participa.
--
-- POR QUE UM TRIGGER E NÃO WITH CHECK
-- `WITH CHECK` só enxerga a linha NOVA; não consegue comparar com a
-- antiga e portanto não sabe dizer se a coluna mudou. A verificação
-- OLD vs NEW exige trigger.
--
-- O QUE CONTINUA PERMITIDO
-- Soft delete (`deleted_at`), recibos (`status`, `read_by`), contadores
-- de thread e edição de conteúdo — esta última agora carimbada.
-- As RPCs de leitura (mark_messages_as_read/_as_delivered) são
-- SECURITY DEFINER e seguem funcionando: o trigger só barra troca de
-- identidade/roteamento, que nenhuma delas faz.
-- ============================================================

-- ── 1. Carimbo de edição ─────────────────────────────────────
-- O MessageModel já lê `edited_at` (message_model.dart), mas a coluna
-- nunca foi criada — o campo chegava sempre nulo. Criando agora, a UI
-- pode exibir "editada" sem nenhuma outra mudança de contrato.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

COMMENT ON COLUMN public.messages.edited_at IS
  'Preenchido automaticamente pelo trigger quando o conteúdo é alterado.';

-- ── 2. Guarda de imutabilidade ───────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_messages_guard_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Identidade e roteamento são imutáveis para qualquer chamador,
  -- inclusive service_role: não existe caso de uso legítimo para
  -- mudar de quem é a mensagem ou em qual conversa ela está.
  IF NEW.chat_id IS DISTINCT FROM OLD.chat_id THEN
    RAISE EXCEPTION 'Mensagem não pode mudar de conversa (chat_id imutável)';
  END IF;

  -- Multi-tenant: mensagem não migra de empresa. A policy RESTRICTIVE
  -- tenant_isolation (20260713110000) já barra o caso pelo caminho da RLS,
  -- mas o trigger fecha também service_role e importações.
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION 'Mensagem não pode mudar de empresa (organization_id imutável)';
  END IF;

  IF NEW.sender_id IS DISTINCT FROM OLD.sender_id THEN
    RAISE EXCEPTION 'Mensagem não pode mudar de autor (sender_id imutável)';
  END IF;

  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Data de criação da mensagem é imutável';
  END IF;

  -- Edição de conteúdo fica registrada. Não bloqueamos a edição — ela é
  -- legítima — mas ela deixa de ser silenciosa.
  IF NEW.content IS DISTINCT FROM OLD.content
     AND OLD.deleted_at IS NULL THEN
    NEW.edited_at := NOW();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_guard_immutable ON public.messages;
CREATE TRIGGER trg_messages_guard_immutable
  BEFORE UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_messages_guard_immutable();

-- ── 3. Mesma proteção para mensagens de canal ────────────────
-- channel_messages tem a mesma exposição e o mesmo risco.
ALTER TABLE public.channel_messages
  ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.fn_channel_messages_guard_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.channel_id IS DISTINCT FROM OLD.channel_id THEN
    RAISE EXCEPTION 'Mensagem não pode mudar de canal (channel_id imutável)';
  END IF;

  -- Multi-tenant: idem messages (retrofit em 20260713111000).
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION 'Mensagem não pode mudar de empresa (organization_id imutável)';
  END IF;

  IF NEW.sender_id IS DISTINCT FROM OLD.sender_id THEN
    RAISE EXCEPTION 'Mensagem não pode mudar de autor (sender_id imutável)';
  END IF;

  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Data de criação da mensagem é imutável';
  END IF;

  IF NEW.content IS DISTINCT FROM OLD.content
     AND OLD.deleted_at IS NULL THEN
    NEW.edited_at := NOW();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_channel_messages_guard_immutable ON public.channel_messages;
CREATE TRIGGER trg_channel_messages_guard_immutable
  BEFORE UPDATE ON public.channel_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_channel_messages_guard_immutable();
