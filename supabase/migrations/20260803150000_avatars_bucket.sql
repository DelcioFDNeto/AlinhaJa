-- ============================================================
-- Bucket dedicado para avatares (pré-requisito do bucket privado)
--
-- POR QUE SEPARAR
-- Um bucket é público ou privado por inteiro. Enquanto os avatares
-- morarem em chat-media, tornar chat-media privado obrigaria a assinar
-- URL em 172 pontos de renderização espalhados por 43 arquivos — toda
-- lista, bolha, cabeçalho e tela de admin.
--
-- Foto de perfil não tem a mesma sensibilidade de uma mídia de DM ou de
-- um anexo com CPF/CNPJ: ela já é visível a toda a empresa por definição,
-- e o nome do arquivo carrega um UUID (não é enumerável). Separando, o
-- chat-media passa a conter só o que é de fato confidencial e o flip
-- para privado fica restrito à mídia de conversa.
--
-- MIGRAÇÃO DOS ARQUIVOS EXISTENTES
-- Trocar de bucket não é operação SQL: o path físico do objeto inclui o
-- bucket, então é preciso reenviar. Use o script one-off:
--   node scripts/migrate_avatars_bucket.js
-- Ele copia chat-media/avatars/* → avatars/* e atualiza users.avatar_url.
-- Rode-o DEPOIS desta migration e ANTES de 20260803140000 (etapa B).
-- ============================================================

-- ── 1. Bucket público, só imagem, 5 MB ───────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  5242880,  -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public            = EXCLUDED.public,
  file_size_limit   = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ── 2. Leitura pública ───────────────────────────────────────
-- Deliberado: é o que permite manter os 172 pontos de renderização
-- inalterados. O conteúdo é foto de perfil corporativa.
DROP POLICY IF EXISTS "Leitura pública de avatares" ON storage.objects;
CREATE POLICY "Leitura pública de avatares"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

-- ── 3. Escrita: cada um só mexe no próprio avatar ────────────
-- Convenção de nome: {userId}_{timestamp}.webp
-- A policy antiga em chat-media aceitava qualquer autenticado gravar
-- qualquer nome, o que permitia sobrescrever a foto de outra pessoa.
DROP POLICY IF EXISTS "Upload do próprio avatar" ON storage.objects;
CREATE POLICY "Upload do próprio avatar"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND storage.filename(name) LIKE auth.uid()::text || '\_%'
  );

DROP POLICY IF EXISTS "Update do próprio avatar" ON storage.objects;
CREATE POLICY "Update do próprio avatar"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND storage.filename(name) LIKE auth.uid()::text || '\_%'
  );

DROP POLICY IF EXISTS "Delete do próprio avatar" ON storage.objects;
CREATE POLICY "Delete do próprio avatar"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND storage.filename(name) LIKE auth.uid()::text || '\_%'
  );
