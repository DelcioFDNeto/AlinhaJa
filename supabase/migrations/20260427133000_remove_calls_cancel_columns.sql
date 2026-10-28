-- Migration to remove any explicit 'Cancelado' columns from Kanban config
DELETE FROM public.workflow_status_config WHERE status ILIKE 'cancelado';
