-- =====================================================
-- Migration 022: Adicionar 'meeting' ao enum content_type
-- =====================================================
-- O tipo content_type original não inclui 'meeting',
-- impedindo a inserção/consulta de mensagens de reunião.

ALTER TYPE content_type ADD VALUE IF NOT EXISTS 'meeting';
