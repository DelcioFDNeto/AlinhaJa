-- ============================================================
-- Migration 025: RPC para Rejeição de Cadastro de Usuário
-- ============================================================
-- Permite que ti_admin rejeite um cadastro pendente,
-- removendo o registro de public.users e auth.users.
-- SECURITY DEFINER bypassa RLS.
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_reject_user(
  p_target_user_id UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  -- 1. Verificar se quem chama é ti_admin
  SELECT role_level INTO v_caller_role
  FROM public.users
  WHERE id = auth.uid();

  IF v_caller_role IS DISTINCT FROM 'ti_admin' THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas a TI pode rejeitar cadastros.';
  END IF;

  -- 2. Não permite rejeitar a si mesmo
  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode rejeitar seu próprio cadastro.';
  END IF;

  -- 3. Deletar de auth.users (o CASCADE cuida de public.users automaticamente)
  DELETE FROM auth.users WHERE id = p_target_user_id;
END;
$$;
