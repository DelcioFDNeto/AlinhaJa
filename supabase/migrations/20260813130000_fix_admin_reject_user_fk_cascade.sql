-- ============================================================
-- Fix: admin_reject_user foreign key constraint handling
--
-- Ao rejeitar um usuário, chaves estrangeiras sem ON DELETE SET NULL
--/CASCADE na tabela `funcionario` e tabelas acessórias de RH/Workflow
-- impediam a exclusão do usuário no auth.users / public.users.
-- ============================================================

-- ── 1. Atualização dos Foreign Keys em public.funcionario ──────
ALTER TABLE public.funcionario DROP CONSTRAINT IF EXISTS funcionario_user_id_fkey;
ALTER TABLE public.funcionario ADD CONSTRAINT funcionario_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.funcionario DROP CONSTRAINT IF EXISTS funcionario_created_by_fkey;
ALTER TABLE public.funcionario ADD CONSTRAINT funcionario_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.funcionario DROP CONSTRAINT IF EXISTS funcionario_updated_by_fkey;
ALTER TABLE public.funcionario ADD CONSTRAINT funcionario_updated_by_fkey
  FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.funcionario DROP CONSTRAINT IF EXISTS funcionario_deleted_by_fkey;
ALTER TABLE public.funcionario ADD CONSTRAINT funcionario_deleted_by_fkey
  FOREIGN KEY (deleted_by) REFERENCES public.users(id) ON DELETE SET NULL;

-- ── 2. Atualização da RPC admin_reject_user ──────────────────
CREATE OR REPLACE FUNCTION public.admin_reject_user(
  p_target_user_id UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  SELECT role_level INTO v_caller_role
  FROM public.users
  WHERE id = auth.uid();

  IF v_caller_role NOT IN ('super_admin', 'admin') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas Administradores podem rejeitar cadastros.';
  END IF;

  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode rejeitar seu próprio cadastro.';
  END IF;

  -- Desvincula o usuário de tabelas com chaves RESTRICT/NO ACTION
  UPDATE public.funcionario 
    SET user_id = NULL, created_by = NULL, updated_by = NULL, deleted_by = NULL 
    WHERE user_id = p_target_user_id OR created_by = p_target_user_id OR updated_by = p_target_user_id OR deleted_by = p_target_user_id;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'candidato') THEN
    UPDATE public.candidato 
      SET usuario_id = NULL, responsavel_id = NULL, created_by = NULL, updated_by = NULL, deleted_by = NULL 
      WHERE usuario_id = p_target_user_id OR responsavel_id = p_target_user_id OR created_by = p_target_user_id OR updated_by = p_target_user_id OR deleted_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'vinculo') THEN
    UPDATE public.vinculo SET created_by = NULL WHERE created_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'rh_access_log') THEN
    UPDATE public.rh_access_log SET usuario_id = NULL WHERE usuario_id = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'workflow_cards') THEN
    UPDATE public.workflow_cards SET assigned_to = NULL, requested_by = NULL, approved_by = NULL WHERE assigned_to = p_target_user_id OR requested_by = p_target_user_id OR approved_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'workflow_card_history') THEN
    UPDATE public.workflow_card_history SET user_id = NULL WHERE user_id = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'chats') THEN
    UPDATE public.chats SET created_by = NULL WHERE created_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'location_tracking_settings') THEN
    UPDATE public.location_tracking_settings SET enabled_by = NULL WHERE enabled_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'titular_request') THEN
    UPDATE public.titular_request SET respondido_por = NULL WHERE respondido_por = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'fin_lancamento') THEN
    UPDATE public.fin_lancamento SET created_by = NULL WHERE created_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'fin_conta_bancaria') THEN
    UPDATE public.fin_conta_bancaria SET created_by = NULL WHERE created_by = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'rh_documento') THEN
    UPDATE public.rh_documento SET aceito_por = NULL WHERE aceito_por = p_target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'audit_log') THEN
    UPDATE public.audit_log SET actor_id = NULL WHERE actor_id = p_target_user_id;
  END IF;

  -- Remove o usuário do auth.users (desencadeia cascade para public.users)
  DELETE FROM auth.users WHERE id = p_target_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reject_user(UUID) TO authenticated;
