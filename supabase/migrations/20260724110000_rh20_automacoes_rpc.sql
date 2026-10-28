-- Migration: RPCs para uso exclusivo da Edge Function (Service Role)

CREATE OR REPLACE FUNCTION public.rh_get_smtp_server(p_org_id UUID)
RETURNS TABLE (
  host TEXT, port INTEGER, username TEXT, from_email TEXT, from_name TEXT, password_decrypted TEXT
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Apenas a Edge Function (com service_role) ou Admins do banco podem chamar
  -- Em webhooks, não há JWT de usuário, mas o client é instanciado com service_role
  -- e a policy restringe acesso via postgREST se não tomar cuidado. 
  -- Ao usar service_role, ele ignora RLS.

  RETURN QUERY
  SELECT 
    c.host, c.port, c.username, c.from_email, c.from_name,
    pgp_sym_decrypt(c.password_encrypted, p_org_id::TEXT || '_alinha_ja_smtp_secret') AS password_decrypted
  FROM public.org_smtp_config c
  WHERE c.organization_id = p_org_id;
END;
$$;
