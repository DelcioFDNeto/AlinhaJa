-- Migration: Adicionar 'store_leader' ao ENUM user_role_level
-- Segurança: COMMIT não é necessário no Supabase free, mas ALTER TYPE não roda
-- dentro de transações padrão do PostgreSQL em algumas versões se não for feito separadamente.

ALTER TYPE public.user_role_level ADD VALUE IF NOT EXISTS 'store_leader' AFTER 'manager';