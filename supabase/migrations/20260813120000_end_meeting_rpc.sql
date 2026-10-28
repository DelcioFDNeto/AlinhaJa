-- ============================================================================
-- Encerrar reunião em uma única operação no servidor
-- ============================================================================
-- PROBLEMA
-- `CallService.endMeetingRoom` fazia três escritas separadas pelo cliente:
--   1. `meetings.status = 'ended'`            → funciona (a tabela tem policy
--                                                de UPDATE para participantes)
--   2. `messages.metadata.status = 'ended'`   → só funciona quando quem encerra
--                                                é o AUTOR do card, porque a
--                                                policy é `sender_id = auth.uid()`
--   3. `channel_messages.metadata` idem       → NUNCA funciona: a tabela tem RLS
--                                                com policies apenas de SELECT e
--                                                INSERT (ver 20260813110000)
--
-- O passo 3 afetava zero linhas sem levantar erro, e o cliente ainda logava
-- "Mensagem (channel_messages) atualizada para ended". O card do canal não
-- ficava preso em "ativo" — ele lê `meetings.status` direto —, mas o metadata
-- seguia dizendo o contrário do banco, e qualquer leitor do metadata (o card de
-- DM já é um) enxergaria a reunião como ativa.
--
-- SOLUÇÃO
-- Uma RPC `SECURITY DEFINER` que faz os três passos na mesma transação, com
-- autorização explícita — em vez de depender de três policies que concordam
-- por acidente.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.end_meeting_room(p_room_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_meeting RECORD;
  v_authorized BOOLEAN := FALSE;
  v_chat_updated INT := 0;
  v_channel_updated INT := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  SELECT id, host_id, chat_id, channel_id, status
  INTO v_meeting
  FROM public.meetings
  WHERE id = p_room_id;

  IF NOT FOUND THEN
    -- Reunião já removida: encerrar de novo não é erro para o cliente.
    RETURN jsonb_build_object('ok', TRUE, 'missing', TRUE);
  END IF;

  -- Quem pode encerrar para todos: o anfitrião, ou quem administra o
  -- workspace/conversa. Espelha os pontos de entrada da UI, que só oferecem
  -- "Encerrar" ao host (mirotalk_screen) ou ao autor do card (message_bubble).
  v_authorized := v_meeting.host_id = v_user_id;

  IF NOT v_authorized AND v_meeting.channel_id IS NOT NULL THEN
    v_authorized := public.can_manage_workspace(v_meeting.channel_id, 'manager');
  END IF;

  IF NOT v_authorized AND v_meeting.chat_id IS NOT NULL THEN
    v_authorized := EXISTS (
      SELECT 1 FROM public.chat_members cm
      WHERE cm.chat_id = v_meeting.chat_id
        AND cm.user_id = v_user_id
        AND cm.role::TEXT IN ('owner', 'admin')
    );
  END IF;

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Sem permissão para encerrar esta reunião.';
  END IF;

  IF v_meeting.status IS DISTINCT FROM 'ended' THEN
    UPDATE public.meetings
    SET status = 'ended',
        ended_at = NOW()
    WHERE id = p_room_id;
  END IF;

  -- Card em DM/grupo.
  IF v_meeting.chat_id IS NOT NULL THEN
    WITH touched AS (
      UPDATE public.messages
      SET metadata = COALESCE(metadata, '{}'::JSONB)
          || jsonb_build_object('status', 'ended')
      WHERE chat_id = v_meeting.chat_id
        AND content_type = 'meeting'
        AND metadata->>'room_id' = p_room_id::TEXT
        AND COALESCE(metadata->>'status', '') <> 'ended'
      RETURNING 1
    )
    SELECT COUNT(*) INTO v_chat_updated FROM touched;
  END IF;

  -- Card em canal/workspace.
  IF v_meeting.channel_id IS NOT NULL THEN
    WITH touched AS (
      UPDATE public.channel_messages
      SET metadata = COALESCE(metadata, '{}'::JSONB)
          || jsonb_build_object('status', 'ended')
      WHERE channel_id = v_meeting.channel_id
        AND content_type = 'meeting'
        AND metadata->>'room_id' = p_room_id::TEXT
        AND COALESCE(metadata->>'status', '') <> 'ended'
      RETURNING 1
    )
    SELECT COUNT(*) INTO v_channel_updated FROM touched;
  END IF;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'chat_cards_updated', v_chat_updated,
    'channel_cards_updated', v_channel_updated
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.end_meeting_room(UUID) TO authenticated;

-- O UPDATE de metadata filtra por `room_id`; sem índice ele varre a conversa.
CREATE INDEX IF NOT EXISTS idx_messages_meeting_room
  ON public.messages ((metadata->>'room_id'))
  WHERE content_type = 'meeting';

CREATE INDEX IF NOT EXISTS idx_channel_messages_meeting_room
  ON public.channel_messages ((metadata->>'room_id'))
  WHERE content_type = 'meeting';
