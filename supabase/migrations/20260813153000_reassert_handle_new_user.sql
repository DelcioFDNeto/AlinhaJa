-- ============================================================
-- Port ADAPTADO do Fluxy (20260810150000_fix_handle_new_user_trigger.sql)
--
-- PROBLEMA NO FLUXY
-- A `handle_new_user()` viva no banco havia derivado para uma versão
-- antiga que inseria na tabela legada `public.profiles`. Quem entrava
-- com uma conta de `auth.users` ausente de `public.users` nascia sem
-- linha de perfil, e daí caía tudo o que depende dela: permissões
-- (RBAC), resolução de organização e registro de token FCM.
--
-- O QUE MUDA AQUI
-- O histórico do AlinhaJá já aponta para `public.users` desde a
-- 20260713101000, então esta migration é sobretudo defensiva: reafirma
-- a definição correta caso o banco tenha derivado (drift não aparece no
-- diff de migrations) e traz a única melhoria real da versão do Fluxy:
--
--   full_name → COALESCE(metadata.full_name, NEW.email)
--
-- Antes o fallback era string vazia, e o usuário aparecia sem nome
-- nenhum nas listas até alguém editar o cadastro; agora aparece pelo
-- e-mail, que ao menos identifica a pessoa.
--
-- O QUE FOI DELIBERADAMENTE DEIXADO DE FORA
-- A migration do Fluxy também promovia a super_admin uma conta master
-- por e-mail fixo e semeava em `public.users` dois UUIDs fixos de
-- `auth.users`. São identidades do tenant do Fluxy: replicá-las aqui
-- criaria super_admins que não pertencem a este produto. (A promoção
-- por e-mail fixo foi removida de vez em 20261028120000.)
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
  -- DuBairro (org inicial) como fallback: mantém o single-tenant atual
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
