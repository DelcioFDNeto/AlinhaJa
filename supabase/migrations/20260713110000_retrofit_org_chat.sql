-- ============================================================
-- Retrofit multi-tenant 3a — CHAT
-- Adiciona organization_id + isolamento por empresa às tabelas de
-- chat legadas (herdadas do Fluxy, hoje sem tenancy).
--
-- Estratégia (uniforme a todo o retrofit legado):
--   1. organization_id NOT NULL DEFAULT DuBairro → linhas atuais
--      (todas DuBairro) ficam válidas; ZERO mudança de comportamento.
--   2. Índice por organization_id.
--   3. BEFORE INSERT: fn_tg_force_current_org() força a org do usuário
--      autenticado (impede spoofing e vence o DEFAULT); mantém o valor
--      para service_role (Edge Functions).
--   4. Policy RESTRICTIVE "tenant_isolation": AND-combina com as policies
--      permissivas existentes, cravando organization_id = fn_current_org()
--      sem reescrever a lógica de acesso atual.
-- ============================================================

-- ── Helper de trigger (definido uma vez; reusado por todo o retrofit) ─
CREATE OR REPLACE FUNCTION public.fn_tg_force_current_org()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  -- Usuário autenticado: força a própria org (anti-spoofing; vence DEFAULT).
  IF auth.uid() IS NOT NULL THEN
    NEW.organization_id := public.fn_current_org();
  END IF;
  -- service_role ou org indefinida: cai na org inicial (DuBairro).
  IF NEW.organization_id IS NULL THEN
    NEW.organization_id := 'a0000000-0000-4000-8000-000000000001';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_tg_force_current_org() FROM PUBLIC, anon;

-- ── Aplicação uniforme ao grupo de tabelas de chat ───────────
DO $$
DECLARE
  t text;
  v_tables text[] := ARRAY[
    'chats', 'chat_members', 'messages',
    'message_reactions',
    'message_actions', 'starred_messages'
  ];
BEGIN
  FOREACH t IN ARRAY v_tables LOOP
    -- 1. coluna
    EXECUTE format(
      'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS organization_id uuid '
      'NOT NULL DEFAULT ''a0000000-0000-4000-8000-000000000001'' '
      'REFERENCES public.organizations(id)', t);
    -- 2. índice
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_%s_organization ON public.%I(organization_id)',
      t, t);
    -- 3. trigger de carimbo
    EXECUTE format('DROP TRIGGER IF EXISTS trg_force_org ON public.%I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_force_org BEFORE INSERT ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org()', t);
    -- 4. isolamento por org (RESTRICTIVE = AND com as policies existentes)
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON public.%I AS RESTRICTIVE FOR ALL '
      'USING (organization_id = public.fn_current_org()) '
      'WITH CHECK (organization_id = public.fn_current_org())', t);
  END LOOP;
END $$;
