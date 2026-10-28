-- Remove a versão antiga do RPC que continha "p_job_function" que estava causando ambiguidade (PGRST203)
DROP FUNCTION IF EXISTS public.admin_create_user(text, text, text, uuid, public.user_role_level, text, text, text, text, date);
