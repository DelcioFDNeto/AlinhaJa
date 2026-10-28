-- ============================================================
-- 013: Correção da Primary Key do chat_members para Streams
-- O Supabase Realtime (PostgresChanges) não lida bem com PKs compostas.
-- Esta migration adiciona um ID único dedicado à sincronização.
-- ============================================================

-- 1. Adicionar uma nova coluna sync_id gerada automaticamente
ALTER TABLE chat_members
ADD COLUMN sync_id UUID DEFAULT gen_random_uuid();

-- 2. Garantir que todo registro futuro tenha esse UUID único
ALTER TABLE chat_members
ADD CONSTRAINT chat_members_sync_id_key UNIQUE (sync_id);

-- Nota: A PK real da tabela continuará sendo (chat_id, user_id) para garantir
-- as FKs e regras de negócio de que um usuário não pode estar 2x no chat.
-- Usaremos o `sync_id` APENAS no filtro `.stream(primaryKey: ['sync_id'])` 
-- do Flutter para evitar crashes do Supabase Client.
