-- ============================================================
-- Audit de segurança 2026-09-03: phone deixa de ser legível por
-- toda a empresa
--
-- PROBLEMA
-- A migration 20260803170000 revogou SELECT de cpf, data_nascimento
-- e sexo, mas esqueceu phone. Qualquer autenticado fazia:
--     GET /rest/v1/users?select=full_name,phone
-- e baixava o telefone pessoal de toda a organização.
--
-- Viola o princípio de minimização de dados (LGPD Art. 6°, III).
--
-- SOLUÇÃO
-- Mesmo padrão da migration anterior: revogar SELECT de tabela
-- inteira, reconceder coluna a coluna excluindo as sensíveis.
-- RPCs admin_list_users_pii() e get_my_sensitive_profile() já
-- cobrem leitura legítima de cpf/nascimento/sexo; adicionamos
-- phone nelas também.
--
-- POR QUE `email` FICA DE FORA DESTE REVOKE
-- GRANT de coluna não é sensível a linha: revogar `email` bloquearia
-- também a leitura do PRÓPRIO e-mail, e o bootstrap do app depende
-- disso — currentUserProvider carrega a sessão com
-- UserModel.selectWithOrg, que inclui `email`. Não existe forma de
-- revogar a coluna e manter o dono da linha enxergando o próprio
-- dado. Como o e-mail corporativo também é a identidade de login,
-- exibida por projeto no diretório interno, ele permanece concedido;
-- o limite continua sendo a RLS de organização.
-- ============================================================

-- ── 1. Reaplica o grant sem phone ────────────────────────────
DO $$
DECLARE
  v_cols text;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO v_cols
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name   = 'users'
     AND column_name NOT IN ('cpf', 'data_nascimento', 'sexo', 'phone');

  IF v_cols IS NULL THEN
    RAISE EXCEPTION 'Não foi possível ler as colunas de public.users';
  END IF;

  EXECUTE 'REVOKE SELECT ON public.users FROM authenticated';
  EXECUTE format('GRANT SELECT (%s) ON public.users TO authenticated', v_cols);
END $$;

-- ── 2. Atualiza get_my_sensitive_profile para incluir phone ──
-- DROP antes do CREATE: mudar o RETURNS TABLE é mudar o tipo de retorno,
-- e CREATE OR REPLACE recusa isso ("cannot change return type of existing
-- function", 42P13). Sem o DROP esta migration aborta inteira.
DROP FUNCTION IF EXISTS public.get_my_sensitive_profile();

CREATE FUNCTION public.get_my_sensitive_profile()
RETURNS TABLE (
  cpf             text,
  data_nascimento date,
  sexo            text,
  phone           text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT u.cpf, u.data_nascimento, u.sexo, u.phone
    FROM public.users u
   WHERE u.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_my_sensitive_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_sensitive_profile() TO authenticated;

COMMENT ON FUNCTION public.get_my_sensitive_profile() IS
  'Dados pessoais sensíveis do próprio usuário autenticado, incluindo phone (LGPD Art. 18, II).';

-- ── 3. Atualiza admin_list_users_pii para incluir phone ──────
-- Mesma razão do DROP acima. E VOLATILE, não STABLE: a função grava em
-- rh_access_log e o PostgreSQL recusa INSERT em função não-volátil
-- ("INSERT is not allowed in a non-volatile function", 0A000) — foi
-- exatamente o bug corrigido pela 20260813152000, que não pode voltar.
-- A org-alvo continua vindo de fn_current_org(), que honra a "empresa em
-- atuação" do dono da plataforma (20260728100000); ler organization_id da
-- própria linha quebraria o console multi-empresa.
DROP FUNCTION IF EXISTS public.admin_list_users_pii();

CREATE FUNCTION public.admin_list_users_pii()
RETURNS TABLE (
  user_id         uuid,
  cpf             text,
  data_nascimento date,
  sexo            text,
  phone           text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
BEGIN
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

  INSERT INTO public.rh_access_log (organization_id, usuario_id, acao, detalhes)
  VALUES (v_org, auth.uid(), 'listou_pii_usuarios',
          jsonb_build_object('origem', 'admin_list_users_pii'));

  RETURN QUERY
    SELECT u.id, u.cpf, u.data_nascimento, u.sexo, u.phone
      FROM public.users u
     WHERE u.organization_id = v_org;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_users_pii() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_users_pii() TO authenticated;

COMMENT ON FUNCTION public.admin_list_users_pii() IS
  'CPF/nascimento/sexo/phone dos usuários da org, apenas para admin+. Registra o acesso em rh_access_log. VOLATILE por causa desse INSERT.';

-- ── 4. PostgREST precisa reler o catálogo de privilégios ─────
NOTIFY pgrst, 'reload schema';
