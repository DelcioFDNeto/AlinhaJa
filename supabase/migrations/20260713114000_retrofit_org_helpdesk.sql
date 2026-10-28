-- ============================================================
-- Retrofit multi-tenant 3e — HELPDESK (tickets de suporte)
-- Mesmo padrão do 3a (ver 20260713110000_retrofit_org_chat.sql).
-- ============================================================
DO $$
DECLARE
  t text;
  v_tables text[] := ARRAY[
    'support_tickets', 'support_ticket_messages'
  ];
BEGIN
  FOREACH t IN ARRAY v_tables LOOP
    EXECUTE format(
      'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS organization_id uuid '
      'NOT NULL DEFAULT ''a0000000-0000-4000-8000-000000000001'' '
      'REFERENCES public.organizations(id)', t);
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_%s_organization ON public.%I(organization_id)',
      t, t);
    EXECUTE format('DROP TRIGGER IF EXISTS trg_force_org ON public.%I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_force_org BEFORE INSERT ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org()', t);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON public.%I AS RESTRICTIVE FOR ALL '
      'USING (organization_id = public.fn_current_org()) '
      'WITH CHECK (organization_id = public.fn_current_org())', t);
  END LOOP;
END $$;
