-- ============================================================
-- Correção 2026-09-04: approve_workflow_card quebrou sob search_path = ''
--
-- PROBLEMA
-- A migration 20260903170000 (Achado 07) varre pg_proc e aplica
--   ALTER FUNCTION ... SET search_path = ''
-- em toda função SECURITY DEFINER que ainda não fixava o caminho de busca.
-- Ela recriou qualificadas as três funções que referenciavam TABELAS sem
-- prefixo, mas approve_workflow_card quebra por outro caminho: um CAST para
-- um enum do schema public, dentro do corpo:
--
--   approval_status = CASE WHEN p_approve THEN 'approved'::workflow_approval_status
--                          ELSE 'rejected'::workflow_approval_status END
--
-- Nomes de tipo em cast são resolvidos na EXECUÇÃO, não na criação — ao
-- contrário dos tipos da lista de parâmetros, que viram OID no CREATE (é por
-- isso que create_workflow_card, com `p_card_type workflow_card_type` na
-- assinatura, continua funcionando). Com search_path vazio o cast não resolve
-- e a chamada aborta com:
--   ERROR: type "workflow_approval_status" does not exist (42704)
--
-- Efeito: aprovar ou rejeitar card de workflow parou de funcionar. O
-- ALTER FUNCTION não valida o corpo, então a 20260903170000 aplicou sem erro
-- e a falha só apareceu em runtime.
--
-- SOLUÇÃO
-- Recria a função com o enum qualificado como public.workflow_approval_status,
-- fixando search_path = '' na própria definição. Nada mais do corpo muda: as
-- três tabelas e auth.uid() já estavam qualificadas, e TEXT/NOW() vêm de
-- pg_catalog, que permanece no caminho de busca implícito.
-- ============================================================

CREATE OR REPLACE FUNCTION public.approve_workflow_card(
  p_card_id uuid,
  p_approve boolean,
  p_observations text DEFAULT NULL::text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id UUID;
  v_role_level TEXT;
  v_amount NUMERIC;
  v_threshold NUMERIC;
BEGIN
  v_user_id := auth.uid();

  -- Buscar o cargo global do usuário
  SELECT role_level::TEXT INTO v_role_level FROM public.users WHERE id = v_user_id;

  -- Regra RBAC Básica
  IF v_role_level = 'member' THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas líderes e gestores têm permissão para aprovar ou rejeitar cards.';
  END IF;

  -- Regra RBAC Financeira (Threshold)
  SELECT amount, approval_threshold INTO v_amount, v_threshold
  FROM public.workflow_cards WHERE id = p_card_id;

  IF v_threshold IS NOT NULL AND v_amount > v_threshold THEN
    IF v_role_level NOT IN ('director', 'admin', 'sysadmin') THEN
      RAISE EXCEPTION 'Acesso Negado: Operações acima de R$ % exigem aprovação da Diretoria.', v_threshold;
    END IF;
  END IF;

  UPDATE public.workflow_cards
  SET
    approval_status = CASE
                        WHEN p_approve THEN 'approved'::public.workflow_approval_status
                        ELSE 'rejected'::public.workflow_approval_status
                      END,
    approved_by = v_user_id,
    approval_date = NOW(),
    approval_observations = p_observations,
    updated_at = NOW()
  WHERE id = p_card_id;

  INSERT INTO public.workflow_card_history (card_id, user_id, action, new_value, observations)
  VALUES (
    p_card_id, v_user_id,
    CASE WHEN p_approve THEN 'Aprovado' ELSE 'Rejeitado' END,
    CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
    p_observations
  );

  RETURN TRUE;
END;
$function$;

-- Confirma o efeito em vez de confiar no CREATE: exercita o cast que quebrava.
DO $do$
BEGIN
  PERFORM 'approved'::public.workflow_approval_status;
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Enum public.workflow_approval_status não resolvível: %', SQLERRM;
END
$do$;

NOTIFY pgrst, 'reload schema';
