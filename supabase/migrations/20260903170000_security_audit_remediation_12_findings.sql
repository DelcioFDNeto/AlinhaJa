-- ==============================================================================
-- Migration: 20260903170000_security_audit_remediation_12_findings.sql
-- Audit 03/09/2026 — Remediação dos 12 Apontamentos de Segurança, LGPD e Hardening
-- ==============================================================================

-- ── 1. [Achado 01] Remoção de política cross-tenant aberta em branches ────────
-- A policy branches_public_read (USING true) em 007_add_core_rpc_functions.sql
-- sobreviveu à fase multi-tenant e permitia leitura de todas as filiais.
DROP POLICY IF EXISTS branches_public_read ON public.branches;
DROP POLICY IF EXISTS "branches_public_read" ON public.branches;

-- Assegura que branches mantenha RLS habilitada
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;

-- ── 2. [Achados 05, 06, 08] Portal do Candidato: Hash, Validade e Sessões ──────
-- Adiciona expiração temporal ao token de verificação de e-mail (48h)
ALTER TABLE public.candidato_usuario 
  ADD COLUMN IF NOT EXISTS verification_token_expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '48 hours';

-- a) Signup com bcrypt custo 12 e validade de verificação de 48h
CREATE OR REPLACE FUNCTION public.rh_candidato_signup(p_nome TEXT, p_email TEXT, p_password TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_id UUID;
  v_verification UUID;
BEGIN
  INSERT INTO public.candidato_usuario (
    email,
    password_hash,
    nome,
    verification_token,
    verification_token_expires_at
  )
  VALUES (
    lower(trim(p_email)),
    extensions.crypt(p_password, extensions.gen_salt('bf', 12)),
    trim(p_nome),
    gen_random_uuid(),
    NOW() + INTERVAL '48 hours'
  )
  RETURNING id, verification_token INTO v_id, v_verification;
  
  -- Vincula candidaturas antigas automaticamente (mesmo e-mail)
  UPDATE public.candidato SET candidato_usuario_id = v_id
  WHERE lower(trim(email)) = lower(trim(p_email)) AND candidato_usuario_id IS NULL;
  
  RETURN v_verification;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_candidato_signup(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_candidato_signup(TEXT, TEXT, TEXT) TO service_role;

-- b) Login com re-hash automático para custo 12 e sessão de 7 dias
CREATE OR REPLACE FUNCTION public.rh_candidato_login(p_email TEXT, p_password TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user RECORD;
  v_token UUID;
BEGIN
  SELECT id, password_hash, email_verified INTO v_user
  FROM public.candidato_usuario WHERE email = lower(trim(p_email));
  
  IF v_user IS NULL OR v_user.password_hash <> extensions.crypt(p_password, v_user.password_hash) THEN
    RAISE EXCEPTION 'Credenciais inválidas';
  END IF;
  
  IF NOT v_user.email_verified THEN
    RAISE EXCEPTION 'E-mail não verificado';
  END IF;

  -- Re-hash transparente se a senha estiver em custo < 12 (Achado 05)
  IF substring(v_user.password_hash from '^\$2[aby]?\$(\d+)\$') IS NOT NULL
     AND substring(v_user.password_hash from '^\$2[aby]?\$(\d+)\$')::int < 12 THEN
    UPDATE public.candidato_usuario
       SET password_hash = extensions.crypt(p_password, extensions.gen_salt('bf', 12))
     WHERE id = v_user.id;
  END IF;

  -- Sessão encurtada de 30 para 7 dias (Achado 08)
  INSERT INTO public.candidato_sessao (candidato_usuario_id, expires_at)
  VALUES (v_user.id, NOW() + INTERVAL '7 days')
  RETURNING token INTO v_token;

  RETURN v_token;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_candidato_login(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_candidato_login(TEXT, TEXT) TO service_role;

-- c) Verificação com validação de expiração (Achado 08)
CREATE OR REPLACE FUNCTION public.rh_candidato_verify(p_token UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_id UUID;
BEGIN
  UPDATE public.candidato_usuario
     SET email_verified = true,
         verification_token = NULL,
         verification_token_expires_at = NULL
   WHERE verification_token = p_token
     AND (verification_token_expires_at IS NULL OR verification_token_expires_at >= NOW())
  RETURNING id INTO v_id;
  
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_candidato_verify(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_candidato_verify(UUID) TO service_role;

-- d) Validação de sessão ativa (não expirada)
CREATE OR REPLACE FUNCTION public.rh_candidato_get_user(p_session_token UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user JSONB;
BEGIN
  -- Limpa sessões expiradas
  DELETE FROM public.candidato_sessao WHERE expires_at < NOW();
  
  SELECT jsonb_build_object('id', u.id, 'email', u.email, 'nome', u.nome) INTO v_user
  FROM public.candidato_sessao s
  JOIN public.candidato_usuario u ON u.id = s.candidato_usuario_id
  WHERE s.token = p_session_token AND s.expires_at >= NOW();
  
  RETURN v_user;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_candidato_get_user(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_candidato_get_user(UUID) TO service_role;

-- e) Invalidação de sessões na troca de senha (Achado 08)
CREATE OR REPLACE FUNCTION public.rh_candidato_alterar_senha(
  p_session_token UUID,
  p_current_password TEXT,
  p_new_password TEXT
)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user_id UUID;
  v_hash TEXT;
BEGIN
  SELECT s.candidato_usuario_id, u.password_hash INTO v_user_id, v_hash
  FROM public.candidato_sessao s
  JOIN public.candidato_usuario u ON u.id = s.candidato_usuario_id
  WHERE s.token = p_session_token AND s.expires_at >= NOW();

  IF v_user_id IS NULL OR v_hash <> extensions.crypt(p_current_password, v_hash) THEN
    RETURN false;
  END IF;

  UPDATE public.candidato_usuario
     SET password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 12))
   WHERE id = v_user_id;

  -- Invalida todas as sessões anteriores após troca de senha
  DELETE FROM public.candidato_sessao WHERE candidato_usuario_id = v_user_id;

  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_candidato_alterar_senha(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_candidato_alterar_senha(UUID, TEXT, TEXT) TO service_role;

-- ── 3. [Achado 09] Limpeza de Avatar no Arquivamento e Exclusão (LGPD Art. 18) ──
CREATE OR REPLACE FUNCTION public.archive_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- Verify caller is admin or super_admin
    IF NOT EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND role_level IN ('admin', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'Access denied. Only admins can archive users.';
    END IF;

    UPDATE public.users 
       SET is_active = false,
           avatar_url = NULL 
     WHERE id = p_user_id;

    -- Remove o avatar do storage de objetos públicos (LGPD Art. 18)
    DELETE FROM storage.objects
     WHERE bucket_id = 'avatars'
       AND (name LIKE p_user_id::text || '%' OR name LIKE '%' || p_user_id::text || '%');
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_user_account(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- Verify caller is super_admin
    IF NOT EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND role_level = 'super_admin'
    ) THEN
        RAISE EXCEPTION 'Access denied. Only super admins can permanently delete user accounts.';
    END IF;

    -- Remove o avatar do storage antes de deletar
    DELETE FROM storage.objects
     WHERE bucket_id = 'avatars'
       AND (name LIKE p_user_id::text || '%' OR name LIKE '%' || p_user_id::text || '%');

    -- Deleting from auth.users cascades to public.users and all related tables
    DELETE FROM auth.users WHERE id = p_user_id;
END;
$$;

-- ── 4. [Achado 07] Hardening: SET search_path = '' e Qualificação de Funções ──
-- Qualificação explícita das 3 funções que possuíam identificadores não qualificados
-- e quebrariam sob search_path = '':

-- a) create_direct_chat (tabelas public.chat_members e public.chats)
CREATE OR REPLACE FUNCTION public.create_direct_chat(other_user_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_chat_id UUID;
BEGIN
  SELECT cm1.chat_id INTO v_chat_id
  FROM public.chat_members cm1
  INNER JOIN public.chat_members cm2 ON cm1.chat_id = cm2.chat_id
  INNER JOIN public.chats c ON c.id = cm1.chat_id
  WHERE cm1.user_id = auth.uid()
    AND cm2.user_id = other_user_id
    AND c.type = 'direct'
  LIMIT 1;

  IF v_chat_id IS NULL THEN
    INSERT INTO public.chats (type, created_by)
    VALUES ('direct', auth.uid())
    RETURNING id INTO v_chat_id;

    INSERT INTO public.chat_members (chat_id, user_id, role) VALUES
      (v_chat_id, auth.uid(),      'owner'),
      (v_chat_id, other_user_id,   'member');
  END IF;

  RETURN v_chat_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_direct_chat(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_direct_chat(UUID) TO authenticated;

-- b) mark_all_chats_as_read (subquery em public.chat_members)
CREATE OR REPLACE FUNCTION public.mark_all_chats_as_read(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.chat_members
  SET last_read_at = NOW()
  WHERE user_id = p_user_id;
  
  UPDATE public.messages
  SET status = 'read'
  WHERE chat_id IN (SELECT chat_id FROM public.chat_members WHERE user_id = p_user_id)
  AND sender_id != p_user_id
  AND status != 'read';
END;
$$;
REVOKE ALL ON FUNCTION public.mark_all_chats_as_read(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_all_chats_as_read(uuid) TO authenticated;

-- c) get_workflow_metrics (tabela public.workflow_cards)
CREATE OR REPLACE FUNCTION public.get_workflow_metrics(p_channel_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  result JSONB;
BEGIN
  result := jsonb_build_object(
    'total_cards', (SELECT COUNT(*) FROM public.workflow_cards WHERE channel_id = p_channel_id),
    'by_status', (
      SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb)
      FROM (
        SELECT status, COUNT(*) as cnt
        FROM public.workflow_cards
        WHERE channel_id = p_channel_id
        GROUP BY status
      ) t
    ),
    'total_amount', (SELECT COALESCE(SUM(amount), 0) FROM public.workflow_cards WHERE channel_id = p_channel_id)
  );
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_workflow_metrics(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_workflow_metrics(UUID) TO authenticated;

-- d) Varre o catálogo pg_proc e aplica SET search_path = '' em todas as demais
-- funções SECURITY DEFINER do schema public que ainda não possuam search_path fixo.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND (p.proconfig IS NULL OR NOT EXISTS (
        SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg LIKE 'search_path=%'
      ))
  ) LOOP
    BEGIN
      EXECUTE format('ALTER FUNCTION public.%I(%s) SET search_path = ''''', r.proname, r.args);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Não foi possível alterar search_path na função public.%(%): %', r.proname, r.args, SQLERRM;
    END;
  END LOOP;
END $$;