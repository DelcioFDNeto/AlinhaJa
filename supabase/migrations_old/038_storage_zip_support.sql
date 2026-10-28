-- ==============================================================================
-- Migration 038: Suporte ZIP no Storage + Ajustes Workflow
-- ==============================================================================
-- Adiciona MIME type application/zip ao bucket chat-media para permitir
-- upload de anexos comprimidos nos cards de workflow

-- 1. Adicionar application/zip e application/octet-stream ao bucket
UPDATE storage.buckets
SET allowed_mime_types = array_cat(
  allowed_mime_types,
  ARRAY['application/zip', 'application/x-zip-compressed', 'application/octet-stream']
)
WHERE id = 'chat-media'
  AND NOT ('application/zip' = ANY(allowed_mime_types));

-- 2. Aumentar file_size_limit para 50MB (ZIPs com múltiplos PDFs podem ser grandes)
UPDATE storage.buckets
SET file_size_limit = 52428800  -- 50 MB
WHERE id = 'chat-media';
