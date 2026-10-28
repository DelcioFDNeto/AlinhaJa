-- ============================================================
-- Índices de busca  (U-02)
--
-- A tela de busca consulta com `ilike '%termo%'`. Curinga à esquerda
-- não usa índice btree, e não havia tsvector, pg_trgm ou GIN em
-- nenhuma das 172 migrations anteriores: toda busca era varredura
-- sequencial da tabela inteira.
--
-- Hoje passa despercebido. Centralizar a operação nos workspaces
-- multiplica mensagens e cards — é aí que a busca começa a demorar e a
-- pessoa volta para o WhatsApp.
--
-- ## Por que pg_trgm e não tsvector
-- `pg_trgm` com índice GIN acelera exatamente o `ilike '%termo%'` que
-- as telas já usam, sem reescrever consulta nem mudar a semântica da
-- busca (substring casa no meio da palavra; tsvector não casaria).
-- Um tsvector com dicionário português é o passo seguinte quando a
-- busca virar por relevância em vez de por ocorrência — aí a semântica
-- muda de propósito, e é decisão de produto, não de índice.
--
-- Índices GIN de trigrama são grandes e custam na escrita. Por isso os
-- de mensagem são PARCIAIS: só linhas com texto de verdade entram.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ── Mensagens de conversa (DM e grupo) ───────────────────────
CREATE INDEX IF NOT EXISTS idx_messages_content_trgm
  ON public.messages USING GIN (content gin_trgm_ops)
  WHERE content IS NOT NULL AND deleted_at IS NULL;

-- ── Mensagens de canal ───────────────────────────────────────
-- Fonte que a busca global ainda não lia (ver U-01): mensagem de canal
-- vive aqui, não em `messages`.
CREATE INDEX IF NOT EXISTS idx_channel_messages_content_trgm
  ON public.channel_messages USING GIN (content gin_trgm_ops)
  WHERE content IS NOT NULL;

-- ── Cards de workspace ───────────────────────────────────────
-- Título e descrição num índice só: a busca de card procura nos dois e
-- dois índices separados obrigariam a um OR que o planner resolveria
-- com bitmap de qualquer forma.
CREATE INDEX IF NOT EXISTS idx_workflow_cards_text_trgm
  ON public.workflow_cards
  USING GIN ((COALESCE(title, '') || ' ' || COALESCE(description, '')) gin_trgm_ops);

-- ── Apoio às consultas de escopo ─────────────────────────────
-- A busca filtra por canal/chat antes do texto; sem estes o filtro de
-- escopo também varre.
CREATE INDEX IF NOT EXISTS idx_channel_messages_channel_created
  ON public.channel_messages (channel_id, created_at DESC);

COMMENT ON INDEX public.idx_workflow_cards_text_trgm IS
  'Busca por substring em título+descrição do card. A expressão precisa ser '
  'repetida igual na consulta para o índice ser usado.';
