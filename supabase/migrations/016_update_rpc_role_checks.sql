-- ============================================================
-- Migration 016: Corrigir TODAS as funções SQL para novos roles
-- ============================================================
-- Funções que verificavam 'ti_admin'/'director'/'staff' precisam
-- ser atualizadas para 'super_admin'/'admin'/'manager'/'member'.
-- ============================================================

-- ── 1. admin_reject_user ──────────────────────────────────────
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

  DELETE FROM auth.users WHERE id = p_target_user_id;
END;
$$;

-- ── 2. admin_update_user_role ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_update_user_role(
  p_target_user_id UUID,
  p_new_role TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  SELECT role_level INTO v_caller_role
  FROM public.users WHERE id = auth.uid();

  IF v_caller_role NOT IN ('super_admin', 'admin') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas Administradores podem alterar níveis de acesso.';
  END IF;

  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode alterar seu próprio nível de acesso.';
  END IF;

  -- Somente super_admin pode promover para super_admin
  IF p_new_role = 'super_admin' AND v_caller_role != 'super_admin' THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas o Super Admin pode promover a este nível.';
  END IF;

  IF p_new_role NOT IN ('super_admin', 'admin', 'manager', 'member') THEN
    RAISE EXCEPTION 'Role inválido: %. Valores aceitos: super_admin, admin, manager, member', p_new_role;
  END IF;

  UPDATE public.users
  SET role_level = p_new_role::public.user_role_level
  WHERE id = p_target_user_id;
END;
$$;

-- ── 3. RLS policies do it_support_tickets (se a tabela existir) ──
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'it_support_tickets') THEN
    EXECUTE 'DROP POLICY IF EXISTS "Admins podem ver todos os tickets" ON public.it_support_tickets';
    EXECUTE 'DROP POLICY IF EXISTS "Admins podem atualizar tickets" ON public.it_support_tickets';
    EXECUTE 'DROP POLICY IF EXISTS "Admins podem deletar tickets" ON public.it_support_tickets';

    EXECUTE '
      CREATE POLICY "Admins podem ver todos os tickets"
        ON public.it_support_tickets FOR SELECT
        USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN (''super_admin'', ''admin'')))
    ';
    EXECUTE '
      CREATE POLICY "Admins podem atualizar tickets"
        ON public.it_support_tickets FOR UPDATE
        USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN (''super_admin'', ''admin'')))
    ';
    EXECUTE '
      CREATE POLICY "Admins podem deletar tickets"
        ON public.it_support_tickets FOR DELETE
        USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN (''super_admin'', ''admin'')))
    ';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'it_support_ticket_replies') THEN
    EXECUTE 'DROP POLICY IF EXISTS "Admins podem ver todas as respostas" ON public.it_support_ticket_replies';
    EXECUTE '
      CREATE POLICY "Admins podem ver todas as respostas"
        ON public.it_support_ticket_replies FOR SELECT
        USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role_level IN (''super_admin'', ''admin'')))
    ';
  END IF;
END $$;
