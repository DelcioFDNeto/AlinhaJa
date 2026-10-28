-- RH-4.1 — Headcount por status em uma unica query.
-- Espelha public.candidato_contagem_status (S041): antes o app fazia
-- uma count() por status (N round-trips); agora le a view agregada.
CREATE OR REPLACE VIEW public.funcionario_contagem_status
WITH (security_invoker = true) AS
SELECT organization_id, status, count(*) AS total
FROM public.funcionario
WHERE deleted_at IS NULL
GROUP BY organization_id, status;
