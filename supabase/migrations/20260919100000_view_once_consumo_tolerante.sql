-- =============================================================
-- Visualização única: o arquivo não pode impedir o consumo
-- =============================================================
-- PROBLEMA
-- mark_view_once_opened apagava a mensagem e, na MESMA transação, a linha
-- em storage.objects via SQL. O Supabase passou a recusar DELETE direto
-- nas tabelas do Storage ("Direct deletion from storage tables is not
-- allowed. Use the Storage API instead."). A exceção desfazia tudo: a
-- mensagem não era apagada e o app só registrava o erro no log — a mídia
-- "temporária" continuava na conversa, reabrível, para sempre.
--
-- CORREÇÃO
-- A exclusão da mensagem é o que importa e não depende do arquivo. A
-- remoção por SQL vira tentativa isolada (subtransação): se o Storage
-- recusar, a mensagem sai mesmo assim e o cliente — membro do chat, com a
-- policy "Deleção pelo membro do chat" — remove o objeto pela Storage API
-- com o path devolvido.
-- =============================================================

CREATE OR REPLACE FUNCTION public.mark_view_once_opened(p_message_id uuid)
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

  -- Tentativa isolada: se o Storage recusar o DELETE por SQL, só esta
  -- subtransação é desfeita — a mensagem continua apagada.
  BEGIN
    PERFORM set_config('storage.allow_delete_query', 'true', true);
    DELETE FROM storage.objects
     WHERE bucket_id = 'chat-media'
       AND name = v_path;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'view-once %: objeto % fica para a Storage API (%)',
      p_message_id, v_path, SQLERRM;
  END;

  RETURN v_path;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_view_once_opened(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_view_once_opened(uuid) TO authenticated;
