-- ============================================================
-- Multi-tenant SaaS — Enforcement server-side de entitlement de módulo
-- Fecha a brecha do gate só-cliente: além do RLS de isolamento por org
-- (tenant_isolation), as tabelas de dados dos módulos LICENCIÁVEIS passam
-- a exigir que a empresa tenha o módulo contratado em
-- organizations.settings.modules.
--
-- Segurança do desenho:
--   • Policy RESTRICTIVE → AND-combina com as policies existentes e NUNCA
--     concede acesso, só restringe. Impossível abrir dado por engano.
--   • service_role (Edge Functions: portal de carreiras, geração de alertas,
--     IA) bypassa RLS → fluxos automáticos seguem funcionando.
--   • candidato* não tem policy `anon` (intake do portal é via service_role),
--     então gating não quebra candidaturas públicas.
--   • Aplica APENAS onde a tabela existe E já tem RLS habilitada (defesa
--     contra drift repo↔banco); demais são puladas com RAISE NOTICE.
--
-- Baseline (Comunicação/Admin) não entra — não é licenciável.
-- Ref: 20260713100000_platform_owner.sql, 20260713120000_seed_org_modules.sql,
--      lib/core/modules/module_access_provider.dart (gate espelhado no cliente).
-- ============================================================

-- ── 1. Helper: a org do usuário logado contratou o módulo? ────
-- SECURITY DEFINER para ler organizations.settings mesmo sob RLS.
CREATE OR REPLACE FUNCTION public.fn_org_has_module(p_module_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organizations o
    WHERE o.id = public.fn_current_org()
      AND COALESCE(o.settings -> 'modules', '[]'::jsonb) ? p_module_id
  );
$$;
REVOKE EXECUTE ON FUNCTION public.fn_org_has_module(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_org_has_module(text) TO authenticated;

-- ── 2. Policy RESTRICTIVE de entitlement por tabela de módulo ─
-- Mapa módulo → tabelas de dados exclusivas. Logs/auditoria/infra
-- (rh_access_log, ia_usage_log, rh_portal_rate_limit) ficam de fora
-- de propósito (cross-cutting / só service_role).
DO $$
DECLARE
  v_map jsonb := '{
    "rh_banco_talentos": ["candidato","candidato_curriculo","candidato_formacao","candidato_experiencia","candidato_habilidade","candidato_historico","candidato_mensagem"],
    "rh_funcionarios":   ["funcionario","funcionario_dados_sensiveis","vinculo","periodo_experiencia"],
    "rh_documentos":     ["rh_documento"],
    "rh_onboarding":     ["onboarding_template","onboarding_template_item","onboarding_execucao","onboarding_item"],
    "rh_alertas":        ["rh_alerta"],
    "helpdesk":          ["support_tickets","support_ticket_messages"]
  }'::jsonb;
  v_mod text;
  v_tbl text;
BEGIN
  FOR v_mod IN SELECT jsonb_object_keys(v_map) LOOP
    FOR v_tbl IN SELECT jsonb_array_elements_text(v_map -> v_mod) LOOP
      IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = v_tbl AND c.relrowsecurity
      ) THEN
        EXECUTE format(
          'DROP POLICY IF EXISTS module_entitlement ON public.%I', v_tbl);
        EXECUTE format(
          'CREATE POLICY module_entitlement ON public.%I AS RESTRICTIVE FOR ALL '
          'USING (public.fn_org_has_module(%L)) '
          'WITH CHECK (public.fn_org_has_module(%L))', v_tbl, v_mod, v_mod);
        RAISE NOTICE 'entitlement aplicado: % -> public.%', v_mod, v_tbl;
      ELSE
        RAISE NOTICE 'SKIP (tabela ausente ou sem RLS): public.% (modulo %)',
          v_tbl, v_mod;
      END IF;
    END LOOP;
  END LOOP;
END $$;
