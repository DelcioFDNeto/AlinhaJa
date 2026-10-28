-- ============================================================
-- Migration 015: Limpeza de Colunas Legado
-- ============================================================
-- Remove colunas obsoletas que foram substituídas por FKs:
--   job_title    → (removida, nunca foi usada consistentemente)
--   department   → department_id (FK → departments)
--   job_function → job_position_id (FK → job_positions)
-- ============================================================

ALTER TABLE public.users DROP COLUMN IF EXISTS job_title;
ALTER TABLE public.users DROP COLUMN IF EXISTS department;
ALTER TABLE public.users DROP COLUMN IF EXISTS job_function;
