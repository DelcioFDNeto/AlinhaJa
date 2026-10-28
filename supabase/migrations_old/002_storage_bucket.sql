-- ============================================================
-- Chat BySabel — Supabase Storage
-- Executar APÓS o 001_initial_schema.sql
-- ============================================================
-- Seguro para rodar em banco novo.
-- ============================================================

-- 1. Cria o bucket público para mídias do chat (idempotente)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-media',
  'chat-media',
  true,
  26214400,  -- 25 MB em bytes
  ARRAY['image/jpeg','image/png','image/webp','image/gif',
        'audio/mpeg','audio/ogg','audio/wav','audio/m4a',
        'application/pdf','application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Leitura pública (necessário para NetworkImage no Flutter)
-- Drop + Create para evitar conflito em re-execuções
DROP POLICY IF EXISTS "Leitura pública das mídias" ON storage.objects;
CREATE POLICY "Leitura pública das mídias"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'chat-media');

-- 3. Upload apenas por usuários autenticados
DROP POLICY IF EXISTS "Upload autenticado de mídias" ON storage.objects;
CREATE POLICY "Upload autenticado de mídias"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'chat-media' AND
    auth.role() = 'authenticated'
  );

-- 4. Atualização (necessária para upserts do Storage)
DROP POLICY IF EXISTS "Update autenticado de mídias" ON storage.objects;
CREATE POLICY "Update autenticado de mídias"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'chat-media' AND
    auth.role() = 'authenticated'
  );

-- 5. Deleção apenas por usuários autenticados membros do chat
--    Convenção de path: chats/{chatId}/{uuid}.ext
DROP POLICY IF EXISTS "Deleção pelo membro do chat" ON storage.objects;
DROP POLICY IF EXISTS "Deleção pelo autor" ON storage.objects;
CREATE POLICY "Deleção pelo membro do chat"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'chat-media' AND
    auth.role() = 'authenticated' AND
    EXISTS (
      SELECT 1 FROM public.chat_members
      WHERE chat_id = (string_to_array(name, '/'))[2]::uuid
        AND user_id = auth.uid()
    )
  );
