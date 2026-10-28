-- =============================================================
-- fn_is_admin volta a ser STABLE
-- =============================================================
-- A migration do Financeiro (20260726100000) recriou fn_is_admin() sem
-- STABLE, e a função passou a VOLATILE (o padrão). Numa política de RLS uma
-- função VOLATILE é reavaliada a cada linha e impede o planner de otimizar
-- — e fn_is_admin está em dezenas de políticas (RBAC, painel admin, SMTP,
-- financeiro, leitura de perfis). O corpo não muda.
-- =============================================================

ALTER FUNCTION public.fn_is_admin() STABLE;
