DROP POLICY IF EXISTS "TI admin pode atualizar todos os tickets" ON public.support_tickets;
DROP POLICY IF EXISTS "TI admin pode ver todos os tickets" ON public.support_tickets;

CREATE POLICY "TI admin pode ver todos os tickets"
ON public.support_tickets FOR SELECT
USING (fn_is_admin());

CREATE POLICY "TI admin pode atualizar todos os tickets"
ON public.support_tickets FOR UPDATE
USING (fn_is_admin());
