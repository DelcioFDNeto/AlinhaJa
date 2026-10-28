-- ============================================================
-- Multi-tenant Fase SaaS — Nível "Dono da Aplicação" (platform owner)
-- Cria o eixo de plataforma (ortogonal a role_level, como hr_role):
-- uma flag is_platform_owner + helper de RLS + RPCs de gestão de
-- tenants (criar empresa, criar 1º admin, ativar, configurar módulos,
-- listar). O dono da plataforma é o ÚNICO caminho cross-tenant.
-- Ref: docs/PLANO-IMPLEMENTACAO-RH.md seção 9 (Rumo ao SaaS).
-- ============================================================

-- ── 1. Flag de dono da plataforma ────────────────────────────
-- Ortogonal a role_level: o dono mantém super_admin na sua org natal;
-- a flag concede os poderes que atravessam organizações.
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_platform_owner BOOLEAN NOT NULL DEFAULT false;

-- Contas mestre da TI nascem como donas da plataforma.
UPDATE public.users
   SET is_platform_owner = true
 WHERE lower(email) IN ('delciofarias04@gmail.com');

-- ── 2. Helper de RLS (bypassa RLS de users via SECURITY DEFINER) ─
CREATE OR REPLACE FUNCTION public.fn_is_platform_owner()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_platform_owner = true
  );
$$;
REVOKE EXECUTE ON FUNCTION public.fn_is_platform_owner() FROM anon;

-- ── 3. organizations: dono da plataforma enxerga TODAS as orgs ─
-- Complementa a policy "Usuário lê a própria organização" (fase 0),
-- que restringe o usuário comum à própria org.
DROP POLICY IF EXISTS "Dono da plataforma lê todas as organizações" ON public.organizations;
CREATE POLICY "Dono da plataforma lê todas as organizações"
  ON public.organizations FOR SELECT
  USING (public.fn_is_platform_owner());

-- ── 4. Criar uma nova empresa (tenant) ───────────────────────
CREATE OR REPLACE FUNCTION public.platform_create_organization(
  p_name       text,
  p_slug       text,
  p_legal_name text DEFAULT NULL,
  p_cnpj       text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.fn_is_platform_owner() THEN
    RAISE EXCEPTION 'Apenas o dono da plataforma pode criar empresas';
  END IF;
  IF COALESCE(trim(p_name), '') = '' THEN
    RAISE EXCEPTION 'Informe o nome da empresa';
  END IF;
  p_slug := lower(trim(p_slug));
  IF p_slug !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$' THEN
    RAISE EXCEPTION 'Slug inválido (use apenas letras minúsculas, números e hífen)';
  END IF;

  INSERT INTO public.organizations (name, slug, legal_name, cnpj)
  VALUES (trim(p_name), p_slug, NULLIF(trim(p_legal_name), ''), NULLIF(trim(p_cnpj), ''))
  RETURNING id INTO v_id;

  -- Provisiona os perfis-padrão de RBAC da nova org (reusa autoprovision)
  PERFORM public.fn_setup_default_roles(v_id);
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Já existe uma empresa com este slug';
END;
$$;
REVOKE ALL ON FUNCTION public.platform_create_organization(text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_create_organization(text, text, text, text) TO authenticated;

-- ── 5. Criar o 1º admin de uma empresa (único caminho cross-tenant) ─
-- Espelha admin_create_user, mas com organization_id EXPLÍCITO e guard
-- de dono da plataforma (em vez do escopo fn_current_org).
CREATE OR REPLACE FUNCTION public.platform_create_org_admin(
  p_org_id    uuid,
  p_email     text,
  p_password  text,
  p_full_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_new_user_id uuid;
BEGIN
  IF NOT public.fn_is_platform_owner() THEN
    RAISE EXCEPTION 'Apenas o dono da plataforma pode criar o admin de uma empresa';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_org_id) THEN
    RAISE EXCEPTION 'Empresa não encontrada';
  END IF;

  v_new_user_id := gen_random_uuid();

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    phone, phone_confirmed_at, confirmation_token, recovery_token,
    email_change_token_new, email_change, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_new_user_id, 'authenticated', 'authenticated',
    lower(p_email),
    extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}',
    -- passa a org no metadata para o trigger handle_new_user já carimbar
    jsonb_build_object('full_name', p_full_name, 'organization_id', p_org_id::text),
    '', NULL, '', '', '', '', now(), now()
  );

  INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_new_user_id, v_new_user_id::text,
    jsonb_build_object('sub', v_new_user_id::text, 'email', lower(p_email),
                       'email_verified', true, 'phone_verified', false),
    'email', now(), now(), now()
  );

  -- Garante org + papel de admin da empresa (não é dono da plataforma)
  UPDATE public.users
     SET organization_id  = p_org_id,
         role_level        = 'admin',
         is_active         = true,
         is_platform_owner = false
   WHERE id = v_new_user_id;

  UPDATE auth.users SET banned_until = NULL WHERE id = v_new_user_id;

  -- Atribui o perfil RBAC padrão (admin → "Super Admin" da própria org)
  PERFORM public.fn_setup_default_roles(p_org_id);
  PERFORM public.fn_assign_default_rbac_role(v_new_user_id);

  RETURN v_new_user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.platform_create_org_admin(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_create_org_admin(uuid, text, text, text) TO authenticated;

-- ── 6. Ativar/desativar uma empresa ──────────────────────────
CREATE OR REPLACE FUNCTION public.platform_set_org_active(
  p_org_id uuid, p_active boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT public.fn_is_platform_owner() THEN
    RAISE EXCEPTION 'Apenas o dono da plataforma pode alterar o status de uma empresa';
  END IF;
  UPDATE public.organizations SET is_active = p_active WHERE id = p_org_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Empresa não encontrada';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.platform_set_org_active(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_set_org_active(uuid, boolean) TO authenticated;

-- ── 7. Configurar módulos habilitados por empresa ────────────
-- Grava em organizations.settings.modules (base dos módulos plugáveis).
CREATE OR REPLACE FUNCTION public.platform_set_org_modules(
  p_org_id uuid, p_modules jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT public.fn_is_platform_owner() THEN
    RAISE EXCEPTION 'Apenas o dono da plataforma pode configurar módulos';
  END IF;
  UPDATE public.organizations
     SET settings = jsonb_set(COALESCE(settings, '{}'::jsonb),
                              '{modules}', COALESCE(p_modules, '[]'::jsonb), true)
   WHERE id = p_org_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Empresa não encontrada';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.platform_set_org_modules(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_set_org_modules(uuid, jsonb) TO authenticated;

-- ── 8. Listar empresas + contagem de usuários (console) ──────
CREATE OR REPLACE FUNCTION public.platform_list_organizations()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.fn_is_platform_owner() THEN
    RAISE EXCEPTION 'Apenas o dono da plataforma pode listar empresas';
  END IF;
  SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb) INTO v_result
  FROM (
    SELECT o.id, o.name, o.slug, o.legal_name, o.cnpj, o.is_active,
           o.settings, o.created_at,
           (SELECT count(*) FROM public.users u
             WHERE u.organization_id = o.id) AS user_count
    FROM public.organizations o
    ORDER BY o.created_at
  ) t;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.platform_list_organizations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_list_organizations() TO authenticated;
