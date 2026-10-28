-- ============================================================
-- Anexos no quadro branco colaborativo
--
-- PROBLEMA
-- O quadro só aceitava traço. Numa reunião real o desenho quase sempre é
-- FEITO EM CIMA de alguma coisa: a foto da prateleira, a planta da loja, o
-- print do relatório. Sem anexo, o time desenha do zero uma coisa que já
-- existe em imagem — ou sai do quadro, manda a foto no chat e perde o
-- contexto.
--
-- MODELO
-- Um item por linha em `whiteboard_items`, no mesmo espaço lógico dos traços
-- (0..1000, ver 20260810110000_whiteboards.sql). O arquivo em si vai para o
-- bucket `chat-media` no prefixo da conversa dona do quadro
-- (`chats/{chatId|channelId}/...`), reaproveitando as policies de membership
-- da ETAPA A (20260803130000): quem não é membro não assina a URL, e não
-- existe caminho novo de storage para auditar.
--
-- POR QUE NÃO EMBUTIR A IMAGEM NO TRAÇO
-- Traço é vetor e nasce imutável; anexo é arquivo e se move. Guardar os dois
-- na mesma tabela obrigaria `points` a virar nullable e a ordem de desenho a
-- conviver com duas semânticas. Tabela própria mantém o `whiteboard_strokes`
-- do jeito que está — e o UPDATE (arrastar/redimensionar), que traço nunca
-- precisa, fica restrito a onde faz sentido.
-- ============================================================

-- ── 1. Itens ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.whiteboard_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  whiteboard_id   UUID NOT NULL REFERENCES public.whiteboards(id) ON DELETE CASCADE,
  author_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  -- 'image' desenha o arquivo no quadro; 'file' vira um cartão clicável.
  kind            TEXT NOT NULL DEFAULT 'image',

  -- URL como o app grava em `messages.media_url`: a pública do bucket. Vira
  -- URL assinada na hora de exibir (MediaUrlResolver), igual ao resto da
  -- mídia — nada aqui depende do bucket ser público.
  media_url       TEXT NOT NULL,

  -- Path dentro do bucket, guardado à parte para conseguir apagar o objeto
  -- quando o item sai do quadro. Extrair isso da URL na hora do delete
  -- funcionaria hoje e quebraria no dia em que a URL mudar de forma.
  storage_path    TEXT,

  file_name       TEXT,
  mime_type       TEXT,
  size_bytes      BIGINT,

  -- Geometria em coordenadas do quadro (0..1000), canto superior esquerdo.
  pos_x           REAL NOT NULL DEFAULT 0,
  pos_y           REAL NOT NULL DEFAULT 0,
  width           REAL NOT NULL DEFAULT 320,
  height          REAL NOT NULL DEFAULT 240,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_item_kind CHECK (kind IN ('image', 'file')),

  -- Sem teto, um arrasto com bug jogaria o anexo a milhões de unidades do
  -- quadro e ele sumiria para todo mundo. A folga negativa/acima de 1000 é
  -- de propósito: item meio para fora da borda é uso normal.
  CONSTRAINT chk_item_bounds CHECK (
    pos_x BETWEEN -2000 AND 3000 AND pos_y BETWEEN -2000 AND 3000
  ),
  CONSTRAINT chk_item_size CHECK (
    width BETWEEN 20 AND 3000 AND height BETWEEN 20 AND 3000
  )
);

-- Mesma regra dos traços: quem chegou depois fica por cima.
CREATE INDEX IF NOT EXISTS idx_wb_items_board
  ON public.whiteboard_items(whiteboard_id, created_at);
CREATE INDEX IF NOT EXISTS idx_wb_items_author
  ON public.whiteboard_items(author_id);

DROP TRIGGER IF EXISTS trg_wb_items_updated_at ON public.whiteboard_items;
CREATE TRIGGER trg_wb_items_updated_at
  BEFORE UPDATE ON public.whiteboard_items
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 1b. Coluna de tenant (AlinhaJá) ──────────────────────────
-- Mesmo retrofit aplicado a `whiteboards`/`whiteboard_strokes` no rodapé de
-- 20260810110000: sem organization_id, um anexo criado com o whiteboard_id
-- de outra org passaria pela policy permissiva de membro. Vem antes das
-- policies porque a trava de colunas imutáveis (seção 3) precisa preservar
-- esta coluna também.
ALTER TABLE public.whiteboard_items
  ADD COLUMN IF NOT EXISTS organization_id uuid
  NOT NULL DEFAULT 'a0000000-0000-4000-8000-000000000001'
  REFERENCES public.organizations(id);

CREATE INDEX IF NOT EXISTS idx_whiteboard_items_organization
  ON public.whiteboard_items(organization_id);

DROP TRIGGER IF EXISTS trg_force_org ON public.whiteboard_items;
CREATE TRIGGER trg_force_org BEFORE INSERT ON public.whiteboard_items
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org();

DROP POLICY IF EXISTS tenant_isolation ON public.whiteboard_items;
CREATE POLICY tenant_isolation ON public.whiteboard_items AS RESTRICTIVE FOR ALL
  USING (organization_id = public.fn_current_org())
  WITH CHECK (organization_id = public.fn_current_org());

-- ── 2. Acesso ────────────────────────────────────────────────
-- Herda da conversa, via can_access_whiteboard() (20260810110000).
ALTER TABLE public.whiteboard_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Membros veem anexos do quadro" ON public.whiteboard_items;
CREATE POLICY "Membros veem anexos do quadro"
  ON public.whiteboard_items FOR SELECT
  USING (public.can_access_whiteboard(whiteboard_id));

DROP POLICY IF EXISTS "Membros anexam no quadro aberto" ON public.whiteboard_items;
CREATE POLICY "Membros anexam no quadro aberto"
  ON public.whiteboard_items FOR INSERT
  WITH CHECK (
    author_id = auth.uid()
    AND public.can_access_whiteboard(whiteboard_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.whiteboards w
      WHERE w.id = whiteboard_id AND w.is_locked
    )
  );

-- Arrastar e redimensionar é colaborativo — o ponto do quadro é mexer junto —
-- mas só enquanto ele estiver aberto, e o trigger abaixo impede que o UPDATE
-- troque o arquivo ou o dono do anexo.
DROP POLICY IF EXISTS "Membros movem anexos do quadro aberto" ON public.whiteboard_items;
CREATE POLICY "Membros movem anexos do quadro aberto"
  ON public.whiteboard_items FOR UPDATE
  USING (
    public.can_access_whiteboard(whiteboard_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.whiteboards w
      WHERE w.id = whiteboard_id AND w.is_locked
    )
  )
  WITH CHECK (public.can_access_whiteboard(whiteboard_id));

-- Apagar é de quem anexou ou de quem é dono do quadro — mesma regra do traço.
DROP POLICY IF EXISTS "Autor apaga o proprio anexo" ON public.whiteboard_items;
CREATE POLICY "Autor apaga o proprio anexo"
  ON public.whiteboard_items FOR DELETE
  USING (
    author_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.whiteboards w
      WHERE w.id = whiteboard_id AND w.created_by = auth.uid()
    )
  );

-- ── 3. UPDATE só mexe em geometria ───────────────────────────
-- A policy de UPDATE precisa liberar qualquer membro (todo mundo arrasta), e
-- RLS não sabe distinguir COLUNA. Sem esta trava, um membro poderia trocar
-- `media_url` por um arquivo de outra conversa e carimbar o anexo como se
-- fosse de outra pessoa. O trigger devolve os campos imutáveis ao valor
-- antigo em vez de recusar, para não transformar arrasto simultâneo em erro
-- na tela.
CREATE OR REPLACE FUNCTION public.fn_tg_whiteboard_item_geometry_only()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  NEW.id            := OLD.id;
  NEW.whiteboard_id := OLD.whiteboard_id;
  NEW.author_id     := OLD.author_id;
  NEW.kind          := OLD.kind;
  NEW.media_url     := OLD.media_url;
  NEW.storage_path  := OLD.storage_path;
  NEW.file_name     := OLD.file_name;
  NEW.mime_type     := OLD.mime_type;
  NEW.size_bytes    := OLD.size_bytes;
  NEW.created_at    := OLD.created_at;
  NEW.organization_id := OLD.organization_id;
  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_tg_whiteboard_item_geometry_only()
  FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_wb_items_geometry_only ON public.whiteboard_items;
CREATE TRIGGER trg_wb_items_geometry_only
  BEFORE UPDATE ON public.whiteboard_items
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_whiteboard_item_geometry_only();

-- ── 4. Realtime ──────────────────────────────────────────────
DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'whiteboard_items'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.whiteboard_items;
  END IF;
END
$do$;

-- Sem REPLICA IDENTITY FULL o UPDATE do Realtime chega só com a PK, e o
-- arrasto de uma pessoa não moveria nada na tela das outras.
ALTER TABLE public.whiteboard_items REPLICA IDENTITY FULL;

COMMENT ON TABLE public.whiteboard_items IS
  'Imagens e arquivos posicionados no quadro, em coordenadas do quadro (0..1000). O arquivo mora no bucket chat-media, no prefixo da conversa dona do quadro.';
