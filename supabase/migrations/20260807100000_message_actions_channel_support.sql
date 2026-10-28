-- ============================================================
-- message_actions passa a aceitar mensagens de canal
--
-- PROBLEMA
-- A tabela nasceu com `message_id UUID NOT NULL REFERENCES messages(id)`.
-- Mensagem de canal vive em `channel_messages`, tabela diferente — então
-- qualquer voto de enquete ou confirmação de anúncio disparado a partir de um
-- canal violava a chave estrangeira e falhava. O recurso aparecia na UI e não
-- gravava nada.
--
-- SOLUÇÃO
-- Uma coluna por origem, com CHECK garantindo exatamente uma preenchida. É o
-- padrão de "FK exclusiva" — mais simples de manter do que uma tabela
-- polimórfica sem integridade referencial.
--
-- ATENÇÃO
-- Este arquivo espelha o que já foi aplicado via MCP nos projetos do AlinhaJá.
-- Escrito para ser idempotente: rodar de novo em um banco já ajustado não faz
-- nada. O bloco de RLS ao final NÃO fazia parte daquela execução e é
-- obrigatório — sem ele o SELECT continua filtrando só por `messages` e o
-- resultado das enquetes de canal volta vazio mesmo gravando certo.
-- ============================================================

-- ── 1. Coluna de origem "canal" ──────────────────────────────
ALTER TABLE public.message_actions
  ADD COLUMN IF NOT EXISTS channel_message_id UUID
  REFERENCES public.channel_messages(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_msg_actions_channel_message
  ON public.message_actions(channel_message_id);

-- ── 2. message_id deixa de ser obrigatório ───────────────────
ALTER TABLE public.message_actions
  ALTER COLUMN message_id DROP NOT NULL;

-- ── 3. Exatamente uma origem por linha ───────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_message_or_channel_message'
      AND conrelid = 'public.message_actions'::regclass
  ) THEN
    ALTER TABLE public.message_actions
      ADD CONSTRAINT chk_message_or_channel_message
      CHECK (num_nonnulls(message_id, channel_message_id) = 1);
  END IF;
END $$;

-- ── 4. Unicidade por origem ──────────────────────────────────
-- A UNIQUE original (message_id, user_id, action_type) não serve para canal:
-- com message_id NULL o Postgres trata cada linha como distinta e o mesmo
-- usuário votaria várias vezes. Dois índices parciais resolvem.
--
-- Consequência para o cliente: índice parcial não pode ser alvo de
-- `on_conflict` via PostgREST (o Postgres exigiria o predicado do índice, que
-- a API REST não expõe). Por isso `setMessageAction` em
-- lib/core/ui/message_cards/message_action_providers.dart apaga antes de
-- inserir, em vez de usar UPSERT.
CREATE UNIQUE INDEX IF NOT EXISTS message_actions_chat_user_action_idx
  ON public.message_actions(message_id, user_id, action_type)
  WHERE message_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS message_actions_channel_user_action_idx
  ON public.message_actions(channel_message_id, user_id, action_type)
  WHERE channel_message_id IS NOT NULL;

-- ── 5. RLS: leitura também pelas mensagens de canal ──────────
-- A policy antiga só enxergava `messages`; para uma linha de canal
-- (message_id NULL) o EXISTS dava falso e o usuário não via nem o próprio
-- voto. As policies de INSERT/UPDATE/DELETE continuam válidas: checam
-- `auth.uid() = user_id` e não dependem da origem.
--
-- O ramo de canal reproduz textualmente o que foi aplicado nos projetos do
-- AlinhaJá, com JOIN direto em `channel_members`. `public.is_channel_member(
-- cm.channel_id)` daria o mesmo resultado em um hop a menos (a função é
-- SECURITY DEFINER e dispensa avaliar a RLS de channel_members); o JOIN
-- funciona porque a policy "Ver membros do mesmo canal" deixa o usuário
-- enxergar a própria linha de membership. Mantido igual ao banco para o
-- arquivo continuar sendo cópia fiel do que está em produção.
DROP POLICY IF EXISTS "Usuários veem ações das mensagens que tem acesso"
  ON public.message_actions;

CREATE POLICY "Usuários veem ações das mensagens que tem acesso"
  ON public.message_actions FOR SELECT
  USING (
    (
      message_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.messages m
        WHERE m.id = message_actions.message_id
          AND public.is_chat_member(m.chat_id)
      )
    )
    OR
    (
      channel_message_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.channel_messages cm
        JOIN public.channel_members cmb ON cmb.channel_id = cm.channel_id
        WHERE cm.id = message_actions.channel_message_id
          AND cmb.user_id = auth.uid()
      )
    )
  );

COMMENT ON COLUMN public.message_actions.channel_message_id IS
  'Origem alternativa a message_id: voto/confirmação sobre mensagem de canal.';
