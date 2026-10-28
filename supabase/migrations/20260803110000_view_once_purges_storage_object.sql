-- ============================================================
-- Visualização única passa a destruir o ARQUIVO (achado de segurança 1.2)
--
-- PROBLEMA
-- A 036_add_video_and_view_once.sql apagava apenas a linha em
-- public.messages. O objeto continuava no Storage e, como o bucket
-- chat-media é público, permanecia baixável para sempre na mesma URL.
-- Ou seja: o app prometia ao usuário que a mídia foi destruída e ela não
-- era. Uma garantia falsa é pior que não ter o recurso.
--
-- CORREÇÃO
-- A RPC passa a remover também o registro em storage.objects, o que torna
-- o arquivo inacessível pela Storage API (tanto pela URL pública quanto
-- por URL assinada). A função devolve o path removido para que o cliente
-- possa disparar o purge físico via storage.remove().
--
-- Vale para mensagens apagadas por qualquer caminho? Não — esta migration
-- trata só o view-once. A limpeza de mídia órfã de mensagens comuns entra
-- junto com a retenção (item de backlog "Governança de conteúdo").
-- ============================================================

-- ── 1. Helper: extrai o path do objeto a partir da URL armazenada ──
-- Aceita tanto URL pública quanto assinada (descarta a query string).
-- Retorna NULL se a URL não pertencer ao bucket informado.
--   https://<ref>.supabase.co/storage/v1/object/public/chat-media/chats/<id>/<uuid>.webp
--     → chats/<id>/<uuid>.webp
CREATE OR REPLACE FUNCTION public.storage_path_from_url(
  p_url    text,
  p_bucket text DEFAULT 'chat-media'
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_url IS NULL OR p_bucket IS NULL THEN NULL
    WHEN position('/' || p_bucket || '/' in p_url) = 0 THEN NULL
    ELSE NULLIF(
      split_part(
        substring(
          p_url
          from position('/' || p_bucket || '/' in p_url) + length(p_bucket) + 2
        ),
        '?', 1
      ),
      ''
    )
  END;
$$;

COMMENT ON FUNCTION public.storage_path_from_url(text, text) IS
  'Converte uma URL do Supabase Storage no path interno do objeto (sem query string).';

-- ── 2. RPC de view-once: apaga a mensagem E o objeto ──────────
-- Muda o tipo de retorno (void → text), então precisa de DROP antes.
DROP FUNCTION IF EXISTS public.mark_view_once_opened(uuid);

CREATE FUNCTION public.mark_view_once_opened(p_message_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_media_url text;
  v_path      text;
BEGIN
  -- Só apaga se for realmente view-once e se quem chama for membro do chat.
  -- RETURNING captura a URL antes da linha sumir.
  DELETE FROM public.messages m
   WHERE m.id = p_message_id
     AND (m.metadata->>'is_view_once')::boolean = true
     AND EXISTS (
       SELECT 1 FROM public.chat_members cm
        WHERE cm.chat_id = m.chat_id
          AND cm.user_id = auth.uid()
     )
  RETURNING m.media_url INTO v_media_url;

  -- Nada apagado (id inexistente, não era view-once, ou quem chamou não é
  -- membro): sai em silêncio, como antes.
  IF v_media_url IS NULL THEN
    RETURN NULL;
  END IF;

  v_path := public.storage_path_from_url(v_media_url, 'chat-media');
  IF v_path IS NULL THEN
    RETURN NULL;
  END IF;

  -- Remover o metadado já torna o objeto irrecuperável pela Storage API:
  -- tanto /object/public quanto /object/sign resolvem por storage.objects.
  -- O purge físico do backing store fica a cargo do cliente
  -- (storage.remove), que recebe este path como retorno.
  DELETE FROM storage.objects
   WHERE bucket_id = 'chat-media'
     AND name = v_path;

  RETURN v_path;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_view_once_opened(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_view_once_opened(uuid) TO authenticated;

COMMENT ON FUNCTION public.mark_view_once_opened(uuid) IS
  'Consome uma mídia de visualização única: apaga a mensagem e o objeto no Storage. Devolve o path removido.';
