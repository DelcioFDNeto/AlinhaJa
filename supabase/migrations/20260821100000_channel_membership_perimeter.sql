-- ============================================================
-- Perímetro de membresia dos canais/workspaces  (F-01 + F-03)
--
-- ## O buraco (F-01)
-- A policy "Entrar em canal dedicado" permitia a QUALQUER usuário
-- autenticado inserir a própria linha em `channel_members` para
-- QUALQUER canal não arquivado. Somada à descoberta ampla (todo
-- autenticado enxergava todos os canais e seus ids) e ao SELECT de
-- `channel_messages`, que libera para quem é membro, o resultado era:
-- enumerar canais -> auto-inscrever-se -> ler todo o histórico, cards
-- do workflow, comentários, anexos e quadros brancos.
--
-- Isso tornava o fluxo de `channel_join_requests` decorativo: a tela
-- pedia aprovação, a API não.
--
-- ## Por que remover a policy não quebra nada
-- Nenhum caminho legítimo depende dela. Os três que gravam membresia
-- são SECURITY DEFINER e, como não há FORCE ROW LEVEL SECURITY em
-- lugar nenhum, rodam como dono da tabela e passam por cima da RLS:
--   * `create_workspace_from_preset` (criação, carimba o criador admin)
--   * `handle_channel_join_request_update` (trigger de aprovação)
--   * `add_channel_member` (admin adiciona, valida can_manage_workspace)
-- O app nunca faz INSERT direto — só SELECT, UPDATE de leitura e o
-- DELETE de "sair do canal".
--
-- Depois desta migration `channel_members` fica SEM policy de INSERT.
-- Isso é deliberado: negar por padrão e obrigar toda entrada a passar
-- por uma RPC que checa permissão. NÃO recrie uma policy de INSERT
-- aqui — se um fluxo novo precisar gravar membresia, exponha uma RPC.
--
-- ## Visibilidade (F-03)
-- Não existia canal privado: nome, descrição e lista de membros de todo
-- canal eram legíveis por qualquer autenticado da organização. Um
-- workspace "Jurídico" entregava, só pela existência, quem participa e
-- do que trata.
--
-- O default é 'public' de propósito: preserva exatamente o
-- comportamento atual para tudo que já existe. Tornar privado é uma
-- decisão por canal, tomada depois, sem risco de trancar ninguém fora
-- no momento do deploy.
--
-- O isolamento multi-tenant continua valendo por cima de tudo isto: a
-- policy `tenant_isolation` (RESTRICTIVE, de 20260713111000) combina
-- por AND com as permissivas abaixo.
-- ============================================================

-- ── 1. Coluna de visibilidade ────────────────────────────────
ALTER TABLE public.channels
  ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'public';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'channels_visibility_check'
  ) THEN
    ALTER TABLE public.channels
      ADD CONSTRAINT channels_visibility_check
      CHECK (visibility IN ('public', 'private'));
  END IF;
END $$;

COMMENT ON COLUMN public.channels.visibility IS
  'public = qualquer membro da organização descobre e pode solicitar entrada; '
  'private = só quem já é membro enxerga o canal, e a entrada é por convite '
  '(add_channel_member). Ver 20260821100000.';

CREATE INDEX IF NOT EXISTS idx_channels_visibility
  ON public.channels(visibility);

-- ── 2. Helper de descoberta ──────────────────────────────────
-- SECURITY DEFINER pelo mesmo motivo de `is_channel_member`: a policy
-- de channel_members precisa consultar `channels`, que tem RLS própria.
-- Sem isso as duas policies se chamariam em recursão infinita.
CREATE OR REPLACE FUNCTION public.channel_is_public(p_channel_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT c.visibility = 'public' FROM public.channels c WHERE c.id = p_channel_id),
    FALSE
  );
$$;

GRANT EXECUTE ON FUNCTION public.channel_is_public(UUID) TO authenticated;

COMMENT ON FUNCTION public.channel_is_public(UUID) IS
  'Canal é de descoberta aberta? SECURITY DEFINER para quebrar a recursão '
  'entre as policies de channels e channel_members.';

-- ── 3. F-01: fim da auto-inscrição ───────────────────────────
DROP POLICY IF EXISTS "Entrar em canal dedicado" ON public.channel_members;

-- ── 4. F-03: descoberta passa a respeitar a visibilidade ─────
DROP POLICY IF EXISTS "Todos autenticados podem ver canais" ON public.channels;
DROP POLICY IF EXISTS "Membros podem ver canais" ON public.channels;
CREATE POLICY "Descoberta de canal respeita visibilidade"
  ON public.channels
  FOR SELECT
  USING (
    visibility = 'public'
    OR public.is_channel_member(id)
  );

DROP POLICY IF EXISTS "Todos autenticados podem ver membros de canais" ON public.channel_members;
DROP POLICY IF EXISTS "Ver membros do mesmo canal" ON public.channel_members;
CREATE POLICY "Ver membros de canal visivel"
  ON public.channel_members
  FOR SELECT
  USING (
    -- a própria participação: sustenta a lista "meus canais", que lê
    -- channel_members antes de saber qualquer coisa sobre o canal
    user_id = auth.uid()
    OR public.is_channel_member(channel_id)
    OR public.channel_is_public(channel_id)
  );

-- ── 5. Trocar a visibilidade ─────────────────────────────────
-- RPC própria em vez de mais um parâmetro em `update_workspace`:
-- acrescentar parâmetro com DEFAULT ali criaria uma SOBRECARGA (assinatura
-- nova), não substituiria a função — e chamadas passariam a ser ambíguas.
-- Além disso, tornar um canal público é um ato de segurança que merece
-- entrada própria e auditada, não um campo a mais num formulário.
CREATE OR REPLACE FUNCTION public.set_channel_visibility(
  p_channel_id UUID,
  p_visibility TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old TEXT;
  v_new TEXT := LOWER(TRIM(COALESCE(p_visibility, '')));
BEGIN
  IF v_new NOT IN ('public', 'private') THEN
    RAISE EXCEPTION 'Visibilidade invalida: %. Use public ou private.', p_visibility;
  END IF;

  IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissao para alterar a visibilidade.';
  END IF;

  SELECT visibility INTO v_old FROM public.channels WHERE id = p_channel_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Canal nao encontrado.';
  END IF;

  IF v_old IS NOT DISTINCT FROM v_new THEN
    RETURN;
  END IF;

  UPDATE public.channels SET visibility = v_new WHERE id = p_channel_id;

  PERFORM public.fn_audit(
    'channel_visibility_changed',
    'channels',
    p_channel_id::TEXT,
    jsonb_build_object('old', v_old, 'new', v_new)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_channel_visibility(UUID, TEXT) TO authenticated;

-- ── 6. Solicitação de entrada só para canal que se enxerga ───
-- A policy permissiva original só exigia `auth.uid() = user_id`, sem
-- olhar o canal. RESTRICTIVE para combinar por AND sem reescrevê-la.
DROP POLICY IF EXISTS "Solicitacao exige canal descoberto" ON public.channel_join_requests;
CREATE POLICY "Solicitacao exige canal descoberto"
  ON public.channel_join_requests
  AS RESTRICTIVE
  FOR INSERT
  WITH CHECK (
    public.channel_is_public(channel_id)
  );
