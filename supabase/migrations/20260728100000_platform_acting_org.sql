-- ============================================================
-- Multi-tenant SaaS — "Empresa em atuação" (acting org) do dono da plataforma
-- Permite ao dono da plataforma (is_platform_owner) alternar o CONTEXTO de
-- organização com o MESMO login, sem trocar a org natal da própria conta.
--
-- Desenho:
--   • fn_current_org() passa a retornar COALESCE(acting, natal), mas o acting
--     só vale para is_platform_owner — usuário comum é 100% inalterado.
--   • A conta do dono continua "morando" na org natal (não polui a lista de
--     usuários do tenant visitado); só a VISIBILIDADE de dados muda.
--   • super_admin já ignora o RBAC (rbac_repository.getMyPermissions), então
--     o dono entra na empresa visitada com acesso total, sem cadastro nela.
--   • Política self-read garante que o dono leia o PRÓPRIO perfil mesmo quando
--     o acting aponta para outra org (senão a policy org-scoped o trancaria).
-- Ref: 20260708150000_fase0_multitenant_organizations.sql (fn_current_org),
--      20260713100000_platform_owner.sql (is_platform_owner / fn_is_platform_owner).
-- ============================================================

-- ── 1. Coluna de empresa em atuação ──────────────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS acting_organization_id UUID
    REFERENCES public.organizations(id);

-- ── 2. fn_current_org() honra o acting apenas para o dono ────
-- STABLE/SECURITY DEFINER (bypassa RLS de users). Lê is_platform_owner e
-- acting_organization_id da MESMA linha, sem chamar fn_is_platform_owner
-- (evita aninhamento desnecessário).
CREATE OR REPLACE FUNCTION public.fn_current_org()
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT COALESCE(
           CASE WHEN u.is_platform_owner THEN u.acting_organization_id END,
           u.organization_id)
  FROM public.users u
  WHERE u.id = auth.uid();
$$;

-- ── 3. Self-read: usuário sempre lê o próprio perfil ─────────
-- Permissiva (OR-combina com "Usuário lê qualquer perfil"). Necessária para o
-- dono ler-se enquanto atua noutra org; inofensiva para os demais (ler a si
-- mesmo é sempre legítimo).
DROP POLICY IF EXISTS "Usuário lê o próprio perfil" ON public.users;
CREATE POLICY "Usuário lê o próprio perfil"
  ON public.users FOR SELECT
  USING (id = auth.uid());

-- ── 4. RPC: alternar a empresa em atuação ────────────────────
-- p_org_id = NULL → volta para a org natal. Guardada por fn_is_platform_owner.
CREATE OR REPLACE FUNCTION public.platform_set_acting_org(p_org_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT public.fn_is_platform_owner() THEN
    RAISE EXCEPTION 'Apenas o dono da plataforma pode alternar de empresa';
  END IF;
  IF p_org_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_org_id) THEN
    RAISE EXCEPTION 'Empresa não encontrada';
  END IF;
  UPDATE public.users
     SET acting_organization_id = p_org_id
   WHERE id = auth.uid();
END;
$$;
REVOKE ALL ON FUNCTION public.platform_set_acting_org(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_set_acting_org(uuid) TO authenticated;
