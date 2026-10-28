-- ============================================================
-- Correcao 2026-09-04: concessao de SELECT em must_change_password
--
-- PROBLEMA
-- A migration 20260903140000 revogou SELECT da tabela users como um todo
-- e concedeu SELECT apenas nas colunas existentes a epoca (excluindo
-- cpf, data_nascimento, sexo e phone).
-- A migration 20260903140100 adicionou a coluna must_change_password,
-- mas nao concedeu privilegio de SELECT explicito para authenticated.
-- No login, ao consultar is_active, must_change_password, o PostgREST
-- abortava com erro 42501 (permission denied for table users).
--
-- SOLUCAO
-- Concede explicitamente SELECT na coluna must_change_password para a role
-- authenticated e notifica o PostgREST para recarregar o catalogo.
-- ============================================================

GRANT SELECT (must_change_password) ON public.users TO authenticated;

NOTIFY pgrst, 'reload schema';