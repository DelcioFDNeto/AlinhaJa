-- ============================================================
-- Port do Fluxy (20260810130000_fix_admin_list_users_pii_volatile.sql)
--
-- PROBLEMA
-- `admin_list_users_pii` foi declarada STABLE, mas grava o acesso em
-- `rh_access_log` (exigência de LGPD Art. 37). Função não-volátil não
-- pode executar INSERT: o PostgreSQL aborta com
-- "INSERT is not allowed in a non-volatile function (SQLSTATE 0A000)"
-- e a listagem de PII no Painel Administrativo quebra por inteiro.
--
-- SOLUÇÃO
-- STABLE → VOLATILE. O corpo multi-tenant da 20260803170000 é mantido
-- na íntegra: papel verificado pela linha do usuário e org-alvo por
-- `fn_current_org()`, que honra a "empresa em atuação" do dono da
-- plataforma (20260728100000).
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_list_users_pii()
RETURNS TABLE (
  user_id         uuid,
  cpf             text,
  data_nascimento date,
  sexo            text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
BEGIN
  -- Multi-tenant: papel pela linha do usuário, org-alvo por fn_current_org()
  -- (honra a "empresa em atuação" do dono da plataforma — 20260728100000).
  IF NOT EXISTS (
    SELECT 1 FROM public.users u
     WHERE u.id = auth.uid()
       AND u.role_level IN ('super_admin', 'admin')
       AND u.is_active
  ) THEN
    RAISE EXCEPTION 'Acesso restrito a administradores';
  END IF;

  v_org := public.fn_current_org();

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Organização do usuário não resolvida';
  END IF;

  -- Registra o acesso: sem isto não há como responder a um titular
  -- "quem consultou meus dados" (LGPD Art. 37).
  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_org, auth.uid(), 'listou_pii_usuarios',
          jsonb_build_object('origem', 'admin_list_users_pii'));

  RETURN QUERY
    SELECT u.id, u.cpf, u.data_nascimento, u.sexo
      FROM public.users u
     WHERE u.organization_id = v_org;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_users_pii() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_users_pii() TO authenticated;

COMMENT ON FUNCTION public.admin_list_users_pii() IS
  'CPF/nascimento/sexo dos usuários da org, apenas para admin+. Registra o acesso em rh_access_log. VOLATILE por causa desse INSERT.';
