-- ============================================================
-- CPF, nascimento e sexo deixam de ser legíveis por toda a empresa
--                                                    (achado 1.5)
--
-- PROBLEMA
-- A policy "Usuário lê qualquer perfil" libera SELECT de public.users
-- para qualquer autenticado da org. RLS opera na LINHA, não na coluna,
-- então junto com nome e avatar iam `cpf`, `data_nascimento` e `sexo`.
-- Um colaborador comum fazia
--     GET /rest/v1/users?select=full_name,cpf,data_nascimento
-- e baixava a base de RH inteira numa requisição.
--
-- Não era só exposição de API: o app exibia isso. O card "Informações
-- Pessoais" da tela de info do chat mostrava nascimento, sexo e CPF de
-- qualquer colega, sem checagem de papel — e embora o CPF aparecesse
-- mascarado, o toque copiava o valor completo para a área de
-- transferência.
--
-- POR QUE PRIVILÉGIO DE COLUNA, E NÃO SEPARAR A TABELA
-- Separar (como funcionario_dados_sensiveis) seria arquiteturalmente
-- mais puro, mas obrigaria a reescrever handle_new_user e as várias
-- versões de admin_create_user espalhadas pelas migrations 001/002/003 —
-- risco alto de quebrar cadastro e criação de usuário para um ganho
-- equivalente. O privilégio de coluna corta o vazamento na mesma
-- profundidade (o PostgREST devolve 403) sem tocar em nenhuma escrita.
--
-- POR QUE AS ESCRITAS NÃO QUEBRAM
--   • handle_new_user e admin_create_user são SECURITY DEFINER: rodam
--     como o owner e ignoram grants de coluna.
--   • O usuário editando o próprio perfil continua funcionando porque
--     a policy de UPDATE já é `USING (auth.uid() = id)` — linha própria.
--     Grant de UPDATE nas colunas é mantido de propósito.
--
-- LEITURA LEGÍTIMA CONTINUA DISPONÍVEL, VIA RPC
--   • get_my_sensitive_profile()   → o próprio dono
--   • admin_list_users_pii()       → admin+ / RH
-- ============================================================

-- ── 1. Corta o SELECT amplo e devolve coluna a coluna ────────
-- A lista de colunas permitidas é derivada do catálogo em vez de
-- escrita à mão: assim uma coluna nova nasce liberada (comportamento
-- atual preservado) e não há risco de eu esquecer alguma e quebrar
-- queries existentes. Só as três sensíveis ficam de fora.
DO $$
DECLARE
  v_cols text;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO v_cols
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name   = 'users'
     AND column_name NOT IN ('cpf', 'data_nascimento', 'sexo');

  IF v_cols IS NULL THEN
    RAISE EXCEPTION 'Não foi possível ler as colunas de public.users';
  END IF;

  -- anon nunca precisou ler a tabela de funcionários.
  EXECUTE 'REVOKE ALL ON public.users FROM anon';

  -- Remove o SELECT de tabela inteira e reconcede sem as sensíveis.
  EXECUTE 'REVOKE SELECT ON public.users FROM authenticated';
  EXECUTE format('GRANT SELECT (%s) ON public.users TO authenticated', v_cols);
END $$;

-- INSERT/UPDATE seguem intactos: a RLS de linha própria já é o limite,
-- e é assim que o usuário edita o próprio CPF em Configurações.

-- ── 2. Leitura do próprio dado sensível ──────────────────────
CREATE OR REPLACE FUNCTION public.get_my_sensitive_profile()
RETURNS TABLE (
  cpf             text,
  data_nascimento date,
  sexo            text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT u.cpf, u.data_nascimento, u.sexo
    FROM public.users u
   WHERE u.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_my_sensitive_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_sensitive_profile() TO authenticated;

COMMENT ON FUNCTION public.get_my_sensitive_profile() IS
  'Dados pessoais sensíveis do próprio usuário autenticado (LGPD Art. 18, II).';

-- ── 3. Leitura pelo RH / administração ───────────────────────
-- Devolve em lote para não gerar N chamadas na listagem do painel.
CREATE OR REPLACE FUNCTION public.admin_list_users_pii()
RETURNS TABLE (
  user_id         uuid,
  cpf             text,
  data_nascimento date,
  sexo            text
)
LANGUAGE plpgsql
STABLE
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
  'CPF/nascimento/sexo dos usuários da org, apenas para admin+. Registra o acesso em rh_access_log.';

-- ── 4. PostgREST precisa reler o catálogo de privilégios ─────
NOTIFY pgrst, 'reload schema';
