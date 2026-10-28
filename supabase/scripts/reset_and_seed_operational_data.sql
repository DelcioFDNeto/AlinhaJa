-- ============================================================================
-- RESET OPERACIONAL + RESEED DOS CANAIS BASE
-- ============================================================================
-- ATENCAO: remove dados transacionais do app:
-- mensagens, canais, membros, cards, reunioes, chamadas, notificacoes,
-- tickets e historicos operacionais.
--
-- Preserva usuarios e estrutura organizacional.
-- Requer a migration:
--   20260512180000_unified_workflow_channel_seed.sql
-- ============================================================================

DO $$
BEGIN
  IF to_regprocedure('public.reset_operational_data(boolean)') IS NULL THEN
    RAISE EXCEPTION 'Aplique a migration 20260512180000_unified_workflow_channel_seed.sql antes de executar este script.';
  END IF;
END $$;

SELECT public.reset_operational_data(TRUE);
