-- ============================================================
-- Quadro branco colaborativo
--
-- MODELO
-- Um quadro por mensagem: publicar o quadro na conversa cria a linha em
-- `whiteboards`, e o card na conversa é a porta de entrada. Cada traço é uma
-- linha em `whiteboard_strokes`, replicada por Realtime.
--
-- POR QUE TRAÇO E NÃO IMAGEM
-- Guardar só um PNG faria o quadro virar figura: ninguém apaga o traço de
-- alguém, ninguém continua o desenho depois, e quem chega atrasado não vê como
-- aquilo foi construído. Com traço por linha dá para desfazer por autor,
-- reabrir dias depois e continuar de onde parou.
-- ============================================================

-- ── 1. Quadros ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.whiteboards (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title           TEXT NOT NULL DEFAULT 'Quadro branco',
  created_by      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  -- Origem: um dos dois, como em message_actions. O quadro pertence à
  -- conversa onde foi criado e herda dela quem pode ver.
  chat_id         UUID REFERENCES public.chats(id) ON DELETE CASCADE,
  channel_id      UUID REFERENCES public.channels(id) ON DELETE CASCADE,

  -- `true` congela o quadro: vira registro, ninguém desenha mais.
  is_locked       BOOLEAN NOT NULL DEFAULT false,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_whiteboard_owner
    CHECK (num_nonnulls(chat_id, channel_id) = 1)
);

CREATE INDEX IF NOT EXISTS idx_whiteboards_chat ON public.whiteboards(chat_id);
CREATE INDEX IF NOT EXISTS idx_whiteboards_channel
  ON public.whiteboards(channel_id);

-- ── 2. Traços ────────────────────────────────────────────────
-- `points` guarda a polilinha já simplificada pelo cliente no formato
-- [{"x":12.5,"y":40.0}, ...], em coordenadas do quadro (não da tela), para o
-- desenho ficar igual em qualquer tamanho de aparelho.
CREATE TABLE IF NOT EXISTS public.whiteboard_strokes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  whiteboard_id   UUID NOT NULL REFERENCES public.whiteboards(id) ON DELETE CASCADE,
  author_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  points          JSONB NOT NULL,
  color           TEXT NOT NULL DEFAULT '#000000',
  width           REAL NOT NULL DEFAULT 3,

  -- 'pen' | 'highlighter' | 'eraser'
  tool            TEXT NOT NULL DEFAULT 'pen',

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_stroke_points CHECK (jsonb_typeof(points) = 'array'),
  CONSTRAINT chk_stroke_width CHECK (width > 0 AND width <= 64)
);

-- Ordem de desenho é a ordem de chegada: quem desenhou por cima fica por cima.
CREATE INDEX IF NOT EXISTS idx_strokes_board
  ON public.whiteboard_strokes(whiteboard_id, created_at);
CREATE INDEX IF NOT EXISTS idx_strokes_author
  ON public.whiteboard_strokes(author_id);

-- ── 3. Acesso ────────────────────────────────────────────────
-- Quem enxerga a conversa enxerga o quadro. Não há permissão RBAC separada:
-- o quadro é da conversa, e o convite para a conversa já é o convite para o
-- quadro.
CREATE OR REPLACE FUNCTION public.can_access_whiteboard(p_whiteboard_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.whiteboards w
    WHERE w.id = p_whiteboard_id
      AND (
        (w.chat_id IS NOT NULL AND public.is_chat_member(w.chat_id))
        OR (w.channel_id IS NOT NULL AND public.is_channel_member(w.channel_id))
      )
  );
$$;

GRANT EXECUTE ON FUNCTION public.can_access_whiteboard(UUID) TO authenticated;

ALTER TABLE public.whiteboards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whiteboard_strokes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Membros veem quadros da conversa"
  ON public.whiteboards FOR SELECT
  USING (
    (chat_id IS NOT NULL AND public.is_chat_member(chat_id))
    OR (channel_id IS NOT NULL AND public.is_channel_member(channel_id))
  );

CREATE POLICY "Membros criam quadros na conversa"
  ON public.whiteboards FOR INSERT
  WITH CHECK (
    created_by = auth.uid()
    AND (
      (chat_id IS NOT NULL AND public.is_chat_member(chat_id))
      OR (channel_id IS NOT NULL AND public.is_channel_member(channel_id))
    )
  );

-- Trancar/renomear é do autor do quadro.
CREATE POLICY "Autor administra o proprio quadro"
  ON public.whiteboards FOR UPDATE
  USING (created_by = auth.uid());

CREATE POLICY "Membros veem tracos do quadro"
  ON public.whiteboard_strokes FOR SELECT
  USING (public.can_access_whiteboard(whiteboard_id));

-- Todo mundo da conversa desenha — é o ponto do recurso —, mas o quadro
-- trancado não aceita traço novo de ninguém.
CREATE POLICY "Membros desenham no quadro aberto"
  ON public.whiteboard_strokes FOR INSERT
  WITH CHECK (
    author_id = auth.uid()
    AND public.can_access_whiteboard(whiteboard_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.whiteboards w
      WHERE w.id = whiteboard_id AND w.is_locked
    )
  );

-- Desfazer apaga o próprio traço; o autor do quadro pode limpar tudo.
CREATE POLICY "Autor apaga o proprio traco"
  ON public.whiteboard_strokes FOR DELETE
  USING (
    author_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.whiteboards w
      WHERE w.id = whiteboard_id AND w.created_by = auth.uid()
    )
  );

-- ── 4. Realtime ──────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'whiteboard_strokes'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.whiteboard_strokes;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'whiteboards'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.whiteboards;
  END IF;
END $$;

COMMENT ON TABLE public.whiteboard_strokes IS
  'Um traço por linha, em coordenadas do quadro. A ordem de created_at é a ordem de desenho.';

-- ============================================================
-- ADAPTAÇÃO MULTI-TENANT (AlinhaJá)
--
-- No app de origem o quadro herda o acesso da conversa e pronto. Aqui a conversa já é
-- isolada por empresa, então o quadro precisa carregar a mesma marca: sem
-- organization_id, um quadro criado por engano com chat_id de outra org
-- ficaria visível pela policy permissiva de membro.
--
-- Mesmo padrão do retrofit legado (20260713110000_retrofit_org_chat.sql):
-- coluna com DEFAULT da org inicial, índice, trigger de carimbo anti-spoofing
-- e policy RESTRICTIVE que faz AND com as permissivas acima.
-- ============================================================
DO $$
DECLARE
  t text;
  v_tables text[] := ARRAY['whiteboards', 'whiteboard_strokes'];
BEGIN
  FOREACH t IN ARRAY v_tables LOOP
    EXECUTE format(
      'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS organization_id uuid '
      'NOT NULL DEFAULT ''a0000000-0000-4000-8000-000000000001'' '
      'REFERENCES public.organizations(id)', t);
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_%s_organization ON public.%I(organization_id)',
      t, t);
    EXECUTE format('DROP TRIGGER IF EXISTS trg_force_org ON public.%I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_force_org BEFORE INSERT ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org()', t);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON public.%I AS RESTRICTIVE FOR ALL '
      'USING (organization_id = public.fn_current_org()) '
      'WITH CHECK (organization_id = public.fn_current_org())', t);
  END LOOP;
END $$;
