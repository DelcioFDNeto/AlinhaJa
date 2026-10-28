-- ============================================================
-- ETAPA A — Autorização por membership no bucket chat-media
--            (achado de segurança 1.1, parte 1 de 2)
--
-- PROBLEMA
-- A policy original era literalmente `USING (bucket_id = 'chat-media')`,
-- sem auth.uid() e sem membership, num bucket marcado public=true. Toda a
-- mídia do mensageiro — foto/áudio/PDF de DM privada, anexo de workflow com
-- CPF/CNPJ e boleto — ficava legível por qualquer pessoa na internet que
-- tivesse a URL. A RLS de `messages` (correta) era contornada pelo Storage.
--
-- POR QUE EM DUAS ETAPAS
-- Virar public=false com o app ainda montando URL pública quebraria toda a
-- mídia instantaneamente. Esta etapa apenas instala a autorização correta
-- (inócua enquanto o bucket for público, porque o endpoint /object/public
-- não passa por RLS). A etapa B (20260803140000) faz o flip, e só deve ser
-- aplicada depois que o app com URLs assinadas estiver publicado.
--
-- ONDE ISTO PASSA A VALER
-- Com o bucket privado, createSignedUrl() só assina se a SELECT abaixo
-- permitir. É este o ponto de decisão: quem não é membro não consegue
-- nem obter a URL assinada.
--
-- CONVENÇÕES DE PATH NO BUCKET (levantadas do código):
--   chats/{chatId|channelId}/{uuid}.ext  → DMs, grupos E canais
--       (MediaService recebe channelId no mesmo parâmetro `chatId`,
--        por isso o prefixo é o mesmo nos dois casos)
--   avatars/{userId}_{timestamp}.webp    → foto de perfil
--   workflow_attachments/{nome}.zip      → anexo de card (path PLANO,
--        sem id de canal; a autorização vem do card que referencia a URL)
-- ============================================================

-- ── 1. Leitura: só quem participa do contexto ────────────────
DROP POLICY IF EXISTS "Leitura pública das mídias" ON storage.objects;
DROP POLICY IF EXISTS "Leitura de mídia por membro do contexto" ON storage.objects;

CREATE POLICY "Leitura de mídia por membro do contexto"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'chat-media'
    AND auth.role() = 'authenticated'
    AND (
      -- Avatares: identificação básica, visível a qualquer autenticado.
      -- Mantidos legíveis de propósito — são renderizados em toda a UI
      -- (lista, bolha, admin) e travá-los por contexto não traria ganho
      -- real de privacidade, só quebraria a interface.
      (storage.foldername(name))[1] = 'avatars'

      -- Mídia de conversa: exige membership no chat OU no canal.
      -- O regex evita erro de cast quando o segundo segmento não é UUID.
      OR (
        (storage.foldername(name))[1] = 'chats'
        AND (storage.foldername(name))[2] ~*
            '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND (
          public.is_chat_member(((storage.foldername(name))[2])::uuid)
          OR public.is_channel_member(((storage.foldername(name))[2])::uuid)
        )
      )

      -- Anexos de workflow: o path é plano, então a autorização é
      -- derivada do card que referencia o arquivo. Custa um scan em
      -- workflow_cards por acesso, aceitável porque anexo de card é
      -- leitura rara (não é conteúdo de timeline).
      OR (
        (storage.foldername(name))[1] = 'workflow_attachments'
        AND EXISTS (
          SELECT 1
            FROM public.workflow_cards wc
           WHERE wc.attachments::text LIKE '%' || storage.filename(name) || '%'
             AND public.is_channel_member(wc.channel_id)
        )
      )
    )
  );

-- ── 2. Upload: autenticado E dono do contexto ────────────────
-- A policy antiga aceitava qualquer autenticado gravar em qualquer path,
-- inclusive dentro da pasta de um chat de que não participa.
DROP POLICY IF EXISTS "Upload autenticado de mídias" ON storage.objects;
DROP POLICY IF EXISTS "Upload de mídia por membro do contexto" ON storage.objects;

CREATE POLICY "Upload de mídia por membro do contexto"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'chat-media'
    AND auth.role() = 'authenticated'
    AND (
      -- Avatar: só na própria pasta e com o próprio id no nome.
      (
        (storage.foldername(name))[1] = 'avatars'
        AND storage.filename(name) LIKE auth.uid()::text || '\_%'
      )
      OR (
        (storage.foldername(name))[1] = 'chats'
        AND (storage.foldername(name))[2] ~*
            '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND (
          public.is_chat_member(((storage.foldername(name))[2])::uuid)
          OR public.is_channel_member(((storage.foldername(name))[2])::uuid)
        )
      )
      -- Anexo de workflow: qualquer autenticado pode subir o ZIP, porque
      -- o arquivo é gerado ANTES de o card existir (o path não tem como
      -- referenciar um card ainda não criado). A leitura continua restrita
      -- pela policy de SELECT acima.
      OR (storage.foldername(name))[1] = 'workflow_attachments'
    )
  );

-- ── 3. Update: mesma regra do insert ─────────────────────────
DROP POLICY IF EXISTS "Update autenticado de mídias" ON storage.objects;
DROP POLICY IF EXISTS "Update de mídia por membro do contexto" ON storage.objects;

CREATE POLICY "Update de mídia por membro do contexto"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'chat-media'
    AND auth.role() = 'authenticated'
    AND (
      (
        (storage.foldername(name))[1] = 'avatars'
        AND storage.filename(name) LIKE auth.uid()::text || '\_%'
      )
      OR (
        (storage.foldername(name))[1] = 'chats'
        AND (storage.foldername(name))[2] ~*
            '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND (
          public.is_chat_member(((storage.foldername(name))[2])::uuid)
          OR public.is_channel_member(((storage.foldername(name))[2])::uuid)
        )
      )
      OR (storage.foldername(name))[1] = 'workflow_attachments'
    )
  );
