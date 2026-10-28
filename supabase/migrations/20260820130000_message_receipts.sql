-- ============================================================
-- "Informações da mensagem": quem recebeu e quem leu
--
-- PROBLEMA
-- Em grupo e em canal os checks da bolha são um resumo de todo mundo: dois
-- checks azuis significam "alguém leu", não "todos leram". Quem manda o aviso
-- de escala ou a instrução de fechamento de caixa precisa da lista nominal —
-- e hoje a única forma de ter isso é o anúncio com ciência (get_announcement_stats),
-- que é pesado demais para uma mensagem comum.
--
-- DE ONDE SAI A INFORMAÇÃO
-- Já existe recibo por pessoa nas duas tabelas de membro:
--   chat_members.last_read_at     (avançado por mark_messages_as_read)
--   channel_members.last_read_at  (avançado ao abrir o canal)
-- Uma mensagem foi lida por alguém quando o `last_read_at` daquele membro é
-- posterior ao `created_at` da mensagem. Isto é exatamente a regra que a
-- bolha e a lista de conversas já usam para o check azul — a tela nova só
-- deixa de agregar e passa a mostrar nome por nome.
--
-- O QUE FALTAVA: ENTREGA POR PESSOA
-- `messages.status` guarda 'delivered' para a mensagem inteira, sem dizer
-- para quem. Num grupo de 12 pessoas isso não responde "chegou em quantos
-- aparelhos?". Daí `last_delivered_at` por membro, carimbado no mesmo ponto
-- em que o app já confirmava a entrega (mark_messages_as_delivered, chamado
-- quando a lista de conversas carrega ou recebe mensagem nova).
--
-- LIMITE CONHECIDO, DE PROPÓSITO
-- `last_delivered_at` é um instante, não um log por mensagem: quem instalou o
-- app hoje aparece como "não recebeu" para as mensagens de ontem, o que é
-- verdade. Guardar uma linha por (mensagem × membro) daria precisão total e
-- multiplicaria o volume da tabela mais quente do banco por N membros — caro
-- demais para o ganho.
-- ============================================================

-- ── 1. Carimbo de entrega por membro ─────────────────────────
ALTER TABLE public.chat_members
  ADD COLUMN IF NOT EXISTS last_delivered_at TIMESTAMPTZ;

ALTER TABLE public.channel_members
  ADD COLUMN IF NOT EXISTS last_delivered_at TIMESTAMPTZ;

COMMENT ON COLUMN public.chat_members.last_delivered_at IS
  'Última vez que o app deste membro confirmou recebimento. Mensagem anterior a isto conta como entregue a ele.';
COMMENT ON COLUMN public.channel_members.last_delivered_at IS
  'Última vez que o app deste membro confirmou recebimento. Mensagem anterior a isto conta como entregue a ele.';

-- ── 2. Entrega passa a carimbar o membro ─────────────────────
-- Mantém a definição de 20260802100000 (o UPDATE em `messages.status`, que
-- alimenta os checks da lista) e acrescenta o carimbo por pessoa. O app não
-- muda: já chama esta função ao abrir a lista de conversas.
CREATE OR REPLACE FUNCTION public.mark_messages_as_delivered(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Guard: a função é SECURITY DEFINER, então só o próprio usuário pode
  -- confirmar as suas entregas.
  IF p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não é permitido confirmar entregas de outro usuário';
  END IF;

  UPDATE public.messages m
  SET status = 'delivered'
  WHERE m.sender_id <> p_user_id
    AND m.status = 'sent'
    AND m.deleted_at IS NULL
    AND m.chat_id IN (
      SELECT cm.chat_id
      FROM public.chat_members cm
      WHERE cm.user_id = p_user_id
    );

  -- O carimbo por membro é o que permite dizer QUEM recebeu. Vale para chat
  -- e canal na mesma chamada: o app abre as duas listas na mesma sessão e
  -- exigir uma segunda chamada só criaria uma janela em que o canal fica
  -- para trás.
  --
  -- A janela de 30s não é economia de escrita: `chat_members` está na
  -- publicação de Realtime e o app escuta essa tabela para o check azul
  -- (chat_provider._subscribeMembersRealtime). Sem o guard, cada mensagem
  -- nova reescreveria TODAS as linhas de membership do usuário e dispararia
  -- um evento por conversa aberta — tráfego proporcional a
  -- (mensagens × conversas) para um dado que muda de segundo em segundo.
  --
  -- Efeito colateral aceito: a entrega tem precisão de meio minuto. Mensagem
  -- que chega logo após um carimbo pode aparecer como "não recebida" por até
  -- 30s. Para um recibo cuja fonte já é "última vez que o app apareceu", meio
  -- minuto não muda nenhuma decisão de quem lê a tela.
  UPDATE public.chat_members
  SET last_delivered_at = NOW()
  WHERE user_id = p_user_id
    AND (last_delivered_at IS NULL
         OR last_delivered_at < NOW() - INTERVAL '30 seconds');

  UPDATE public.channel_members
  SET last_delivered_at = NOW()
  WHERE user_id = p_user_id
    AND (last_delivered_at IS NULL
         OR last_delivered_at < NOW() - INTERVAL '30 seconds');
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_messages_as_delivered(uuid) TO authenticated;

-- ── 3. Recibos de uma mensagem ───────────────────────────────
-- `p_scope` diz em qual tabela procurar: 'chat' (DM/grupo) ou 'channel'.
-- Um RPC só, e não dois, porque a UI é a mesma folha nos dois casos — dois
-- RPCs virariam duas verdades sobre o que é "lido".
CREATE OR REPLACE FUNCTION public.get_message_receipts(
  p_message_id uuid,
  p_scope text DEFAULT 'chat'
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_id  uuid;
  v_sent_at    timestamptz;
  v_context_id uuid;
  v_result     json;
BEGIN
  IF p_scope NOT IN ('chat', 'channel') THEN
    RAISE EXCEPTION 'Escopo inválido: %', p_scope;
  END IF;

  -- 3.1 Localiza a mensagem e o contexto, já checando o acesso. A checagem
  -- vem antes de qualquer dado sair: sem ela, esta função SECURITY DEFINER
  -- devolveria a lista de membros de qualquer conversa para quem soubesse
  -- um id de mensagem.
  IF p_scope = 'chat' THEN
    SELECT m.sender_id, m.created_at, m.chat_id
      INTO v_sender_id, v_sent_at, v_context_id
      FROM public.messages m
     WHERE m.id = p_message_id;

    IF v_context_id IS NULL THEN
      RAISE EXCEPTION 'Mensagem não encontrada';
    END IF;

    IF NOT public.is_chat_member(v_context_id) THEN
      RAISE EXCEPTION 'Sem acesso a esta conversa';
    END IF;
  ELSE
    SELECT cm.sender_id, cm.created_at, cm.channel_id
      INTO v_sender_id, v_sent_at, v_context_id
      FROM public.channel_messages cm
     WHERE cm.id = p_message_id;

    IF v_context_id IS NULL THEN
      RAISE EXCEPTION 'Mensagem não encontrada';
    END IF;

    IF NOT public.is_channel_member(v_context_id) THEN
      RAISE EXCEPTION 'Sem acesso a este canal';
    END IF;
  END IF;

  -- 3.2 Classifica cada destinatário.
  --
  -- O remetente fica de fora: "o autor leu a própria mensagem" não é
  -- informação, e mantê-lo na lista estragaria as contagens do cabeçalho.
  WITH membros AS (
    SELECT
      u.id,
      u.full_name,
      u.avatar_url,
      mb.last_read_at,
      mb.last_delivered_at
    FROM (
      SELECT user_id, last_read_at, last_delivered_at
        FROM public.chat_members
       WHERE p_scope = 'chat' AND chat_id = v_context_id
      UNION ALL
      SELECT user_id, last_read_at, last_delivered_at
        FROM public.channel_members
       WHERE p_scope = 'channel' AND channel_id = v_context_id
    ) mb
    JOIN public.users u ON u.id = mb.user_id
    WHERE mb.user_id IS DISTINCT FROM v_sender_id
  ),
  classificados AS (
    SELECT
      id,
      full_name,
      avatar_url,
      CASE
        WHEN last_read_at IS NOT NULL AND last_read_at >= v_sent_at
          THEN 'read'
        WHEN last_delivered_at IS NOT NULL AND last_delivered_at >= v_sent_at
          THEN 'delivered'
        ELSE 'pending'
      END AS estado,
      -- Instante mostrado ao lado do nome. Como o carimbo é o "última vez
      -- que abriu", ele nunca é anterior ao envio — mas também não é o
      -- momento exato em que a mensagem foi lida, e a UI diz "às HH:MM"
      -- sem prometer precisão maior do que essa.
      CASE
        WHEN last_read_at IS NOT NULL AND last_read_at >= v_sent_at
          THEN last_read_at
        WHEN last_delivered_at IS NOT NULL AND last_delivered_at >= v_sent_at
          THEN last_delivered_at
        ELSE NULL
      END AS em
    FROM membros
  )
  SELECT json_build_object(
    'message_id',       p_message_id,
    'scope',            p_scope,
    'sender_id',        v_sender_id,
    'sent_at',          v_sent_at,
    'recipient_count',  (SELECT COUNT(*) FROM classificados),
    'read_count',       (SELECT COUNT(*) FROM classificados WHERE estado = 'read'),
    'delivered_count',  (SELECT COUNT(*) FROM classificados WHERE estado = 'delivered'),
    'pending_count',    (SELECT COUNT(*) FROM classificados WHERE estado = 'pending'),
    'recipients', COALESCE(
      (
        SELECT json_agg(row_to_json(r) ORDER BY r.ordem, r.full_name)
        FROM (
          SELECT
            id AS user_id,
            full_name,
            avatar_url,
            estado AS state,
            em AS at,
            CASE estado WHEN 'read' THEN 0 WHEN 'delivered' THEN 1 ELSE 2 END
              AS ordem
          FROM classificados
        ) r
      ),
      '[]'::json
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_message_receipts(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_message_receipts(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.get_message_receipts(uuid, text) IS
  'Lista nominal de quem recebeu e leu uma mensagem de chat ou canal. Exige membership no contexto.';

-- O cabeçalho da folha faz três contagens sobre os membros do mesmo
-- contexto; sem índice por membro, cada abertura vira seq scan nas duas
-- tabelas de membership.
CREATE INDEX IF NOT EXISTS idx_chat_members_chat_read
  ON public.chat_members (chat_id, last_read_at);
CREATE INDEX IF NOT EXISTS idx_channel_members_channel_read
  ON public.channel_members (channel_id, last_read_at);
