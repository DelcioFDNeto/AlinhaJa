-- ============================================================
-- Remove a conta mestre do cadastro de usuários
--
-- PROBLEMA
-- `handle_new_user()` promovia a super_admin ATIVO quem se cadastrasse
-- com um e-mail fixo no código. A regra valia em toda instalação do
-- produto — nuvem, servidor próprio de cliente e qualquer distribuidor
-- futuro — e o cadastro pelo app (`/signup`) é aberto:
--
--   • para o cliente e para quem adquirir o produto, era uma conta do
--     fornecedor com acesso total, invisível na configuração;
--   • numa instalação com confirmação automática de e-mail (comum
--     enquanto o SMTP não está pronto), qualquer pessoa que se
--     cadastrasse com aquele endereço entrava como super_admin.
--
-- O QUE MUDA
-- Todo cadastro nasce como antes de qualquer aprovação: `member`,
-- inativo e bloqueado até um administrador liberar. O resto da função é
-- idêntico à versão de 20260813153000.
--
-- CONTAS EXISTENTES
-- A função só roda na criação de usuários. Quem já é super_admin
-- continua sendo; nada é revogado por esta migration.
--
-- COMO CRIAR O PRIMEIRO ADMINISTRADOR AGORA
-- Na instalação, de forma explícita e registrada, com
-- `supabase/scripts/promover_super_admin.sql` (ver runbook, etapa 14).
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_role user_role_level := 'member';
  v_is_active BOOLEAN := false;
  v_branch_id UUID := NULL;
  v_department_id TEXT := NULL;
  v_job_position_id TEXT := NULL;
  v_phone TEXT := NULL;
  v_cpf TEXT := NULL;
  v_branch_str TEXT;
  v_org_str TEXT;
  -- Org inicial como fallback: mantém o comportamento single-tenant atual
  v_org UUID := 'a0000000-0000-4000-8000-000000000001';
BEGIN
  -- Extrai metadados do signup
  v_branch_str := NEW.raw_user_meta_data ->> 'branch_id';
  IF v_branch_str IS NOT NULL AND v_branch_str != '' THEN
    BEGIN
      v_branch_id := v_branch_str::UUID;
    EXCEPTION WHEN invalid_text_representation THEN
      v_branch_id := NULL;
    END;
  END IF;

  -- organization_id explícito (onboarding assistido / signup por empresa)
  v_org_str := NEW.raw_user_meta_data ->> 'organization_id';
  IF v_org_str IS NOT NULL AND v_org_str != '' THEN
    BEGIN
      v_org := v_org_str::UUID;
    EXCEPTION WHEN invalid_text_representation THEN
      v_org := 'a0000000-0000-4000-8000-000000000001';
    END;
  END IF;

  v_department_id := NEW.raw_user_meta_data ->> 'department_id';
  v_job_position_id := NEW.raw_user_meta_data ->> 'job_position_id';
  v_phone := NEW.raw_user_meta_data ->> 'phone';
  v_cpf := NEW.raw_user_meta_data ->> 'cpf';

  INSERT INTO public.users (
    id, full_name, avatar_url, role_level, is_active,
    branch_id, department_id, job_position_id,
    phone, cpf, email, organization_id
  )
  VALUES (
    NEW.id,
    -- Fallback no e-mail em vez de '': sem nome no metadata, a pessoa
    -- ficava anônima em todas as listas até alguém editar o cadastro.
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.email),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
    v_role,
    v_is_active,
    v_branch_id,
    v_department_id,
    v_job_position_id,
    v_phone,
    v_cpf,
    NEW.email,
    v_org
  )
  ON CONFLICT (id) DO NOTHING;

  IF v_is_active = false THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;
