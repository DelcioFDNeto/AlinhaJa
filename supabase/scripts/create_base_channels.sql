-- ============================================================================
-- SEED: canais principais do workspace Fluxy
-- ============================================================================
-- Requer a migration:
--   20260512180000_unified_workflow_channel_seed.sql
--
-- Atualiza/cria os canais base, recria as etapas operacionais atuais e preserva
-- operadores ja configurados no canal.
-- ============================================================================

DO $$
BEGIN
  IF to_regprocedure('public.seed_base_workflow_channels(boolean, boolean)') IS NULL THEN
    RAISE EXCEPTION 'Aplique a migration 20260512180000_unified_workflow_channel_seed.sql antes de executar este script.';
  END IF;
END $$;

SELECT *
FROM public.seed_base_workflow_channels(
  TRUE,  -- p_reset_statuses
  TRUE   -- p_preserve_operator_config
);
