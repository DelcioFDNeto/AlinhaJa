-- ============================================================
-- Direitos do titular e aceite de política (achados 2.5 e 2.6)
--
-- PROBLEMA
-- Candidatos têm portal, exportação, anonimização e retenção
-- configurável. COLABORADORES não tinham nada disso: nenhum acesso
-- consolidado aos próprios dados (Art. 18, II), nenhuma portabilidade
-- (V), nenhum canal para pedir eliminação (VI) e nenhum aceite de
-- política registrado — a pessoa entrava no app sem nunca ter sido
-- informada de que suas conversas, localização e atividade são tratadas.
--
-- `exportMessagesAsZip` não cobre isso: exporta o cache local do Drift,
-- fica no painel admin e não é um direito do titular.
-- ============================================================

-- ── 1. Aceite de política, versionado ────────────────────────
CREATE TABLE IF NOT EXISTS public.policy_acceptance (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  organization_id UUID REFERENCES public.organizations(id),
  policy_type     TEXT NOT NULL,          -- 'privacidade' | 'uso' | 'monitoramento'
  policy_version  TEXT NOT NULL,
  accepted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, policy_type, policy_version)
);

CREATE INDEX IF NOT EXISTS idx_policy_acceptance_user
  ON public.policy_acceptance(user_id, policy_type);

-- Multi-tenant: índice e carimbo de org no padrão do retrofit
-- (20260713110000). O carimbo é redundante com accept_policy, que já grava
-- fn_current_org(), mas fecha qualquer caminho de escrita futuro.
CREATE INDEX IF NOT EXISTS idx_policy_acceptance_organization
  ON public.policy_acceptance(organization_id);

DROP TRIGGER IF EXISTS trg_force_org ON public.policy_acceptance;
CREATE TRIGGER trg_force_org BEFORE INSERT ON public.policy_acceptance
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org();

ALTER TABLE public.policy_acceptance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Titular lê os próprios aceites" ON public.policy_acceptance;
CREATE POLICY "Titular lê os próprios aceites"
  ON public.policy_acceptance FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Admin lê aceites da org" ON public.policy_acceptance;
CREATE POLICY "Admin lê aceites da org"
  ON public.policy_acceptance FOR SELECT
  USING (
    organization_id = public.fn_current_org()
    AND EXISTS (
      SELECT 1 FROM public.users u
       WHERE u.id = auth.uid()
         AND u.role_level IN ('super_admin', 'admin')
         AND u.is_active
    )
  );

-- Escrita só pela RPC: o aceite não pode ser forjado nem apagado.
REVOKE INSERT, UPDATE, DELETE ON public.policy_acceptance FROM authenticated, anon;

CREATE OR REPLACE FUNCTION public.accept_policy(
  p_policy_type text,
  p_version     text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida';
  END IF;

  IF p_policy_type NOT IN ('privacidade', 'uso', 'monitoramento') THEN
    RAISE EXCEPTION 'Tipo de política inválido: %', p_policy_type;
  END IF;

  -- Multi-tenant: fn_current_org() (não a org natal) para que o registro
  -- nasça na empresa em que o usuário está atuando.
  v_org := public.fn_current_org();

  INSERT INTO public.policy_acceptance
    (user_id, organization_id, policy_type, policy_version)
  VALUES (auth.uid(), v_org, p_policy_type, p_version)
  ON CONFLICT (user_id, policy_type, policy_version) DO NOTHING;

  PERFORM public.fn_audit('policy.accepted', 'user', auth.uid()::text,
    jsonb_build_object('tipo', p_policy_type, 'versao', p_version));
END;
$$;
REVOKE ALL ON FUNCTION public.accept_policy(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_policy(text, text) TO authenticated;

-- ── 2. Direito de acesso e portabilidade (Art. 18, II e V) ───
-- Devolve um JSON com tudo que o sistema trata sobre o titular. Não
-- inclui o conteúdo das conversas de terceiros — apenas o que ele
-- próprio produziu — para não transformar um direito individual em
-- vazamento coletivo.
CREATE OR REPLACE FUNCTION public.export_my_data()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_out jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida';
  END IF;

  SELECT jsonb_build_object(
    'gerado_em', NOW(),
    'titular', (
      SELECT jsonb_build_object(
        'id', u.id, 'nome', u.full_name, 'email', u.email,
        'telefone', u.phone, 'cpf', u.cpf,
        'data_nascimento', u.data_nascimento, 'sexo', u.sexo,
        'cargo', u.job_title, 'ativo', u.is_active,
        'criado_em', u.created_at)
        FROM public.users u WHERE u.id = v_uid),
    'mensagens_enviadas', (
      SELECT COUNT(*) FROM public.messages m WHERE m.sender_id = v_uid),
    'mensagens', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'id', m.id, 'conversa', m.chat_id, 'conteudo', m.content,
               'tipo', m.content_type, 'enviada_em', m.created_at)), '[]'::jsonb)
        FROM public.messages m WHERE m.sender_id = v_uid),
    'localizacoes', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'lat', l.latitude, 'lng', l.longitude,
               'registrado_em', l.recorded_at)), '[]'::jsonb)
        FROM public.user_locations l WHERE l.user_id = v_uid),
    'consentimento_gps', (
      SELECT jsonb_build_object(
               'ativo', public.fn_gps_consent_active(v_uid),
               'concedido_em', s.consent_given_at,
               'revogado_em', s.consent_revoked_at,
               'finalidade', s.finalidade)
        FROM public.location_tracking_settings s WHERE s.user_id = v_uid),
    'politicas_aceitas', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'tipo', p.policy_type, 'versao', p.policy_version,
               'aceito_em', p.accepted_at)), '[]'::jsonb)
        FROM public.policy_acceptance p WHERE p.user_id = v_uid),
    'chamadas', (
      SELECT COUNT(*) FROM public.calls c WHERE c.caller_id = v_uid)
  ) INTO v_out;

  PERFORM public.fn_audit('titular.export', 'user', v_uid::text, '{}');
  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION public.export_my_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated;

-- ── 3. Pedido de eliminação (Art. 18, VI) ────────────────────
-- Conta de colaborador não pode ser autoexcluída: há obrigação legal de
-- guarda de registro trabalhista e as mensagens são registro corporativo.
-- O direito exercido aqui é o de REQUERER, com prazo e rastro.
CREATE TABLE IF NOT EXISTS public.titular_request (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  organization_id UUID REFERENCES public.organizations(id),
  tipo            TEXT NOT NULL,   -- 'eliminacao' | 'correcao' | 'informacao'
  descricao       TEXT,
  status          TEXT NOT NULL DEFAULT 'aberto',
  resposta        TEXT,
  respondido_por  UUID REFERENCES public.users(id),
  respondido_em   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Multi-tenant: mesmo padrão aplicado a policy_acceptance acima.
CREATE INDEX IF NOT EXISTS idx_titular_request_organization
  ON public.titular_request(organization_id);
CREATE INDEX IF NOT EXISTS idx_titular_request_user
  ON public.titular_request(user_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_force_org ON public.titular_request;
CREATE TRIGGER trg_force_org BEFORE INSERT ON public.titular_request
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org();

ALTER TABLE public.titular_request ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Titular lê os próprios pedidos" ON public.titular_request;
CREATE POLICY "Titular lê os próprios pedidos"
  ON public.titular_request FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Admin lê pedidos da org" ON public.titular_request;
CREATE POLICY "Admin lê pedidos da org"
  ON public.titular_request FOR SELECT
  USING (
    organization_id = public.fn_current_org()
    AND EXISTS (
      SELECT 1 FROM public.users u
       WHERE u.id = auth.uid()
         AND u.role_level IN ('super_admin', 'admin')
         AND u.is_active
    )
  );

DROP POLICY IF EXISTS "Admin responde pedidos da org" ON public.titular_request;
CREATE POLICY "Admin responde pedidos da org"
  ON public.titular_request FOR UPDATE
  USING (
    organization_id = public.fn_current_org()
    AND EXISTS (
      SELECT 1 FROM public.users u
       WHERE u.id = auth.uid()
         AND u.role_level IN ('super_admin', 'admin')
         AND u.is_active
    )
  );

CREATE OR REPLACE FUNCTION public.create_titular_request(
  p_tipo      text,
  p_descricao text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_id  uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida';
  END IF;

  IF p_tipo NOT IN ('eliminacao', 'correcao', 'informacao') THEN
    RAISE EXCEPTION 'Tipo de pedido inválido: %', p_tipo;
  END IF;

  -- Multi-tenant: fn_current_org() (não a org natal) para que o registro
  -- nasça na empresa em que o usuário está atuando.
  v_org := public.fn_current_org();

  INSERT INTO public.titular_request (user_id, organization_id, tipo, descricao)
  VALUES (auth.uid(), v_org, p_tipo, p_descricao)
  RETURNING id INTO v_id;

  PERFORM public.fn_audit('titular.request', 'user', auth.uid()::text,
    jsonb_build_object('tipo', p_tipo, 'pedido_id', v_id));

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_titular_request(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_titular_request(text, text) TO authenticated;

-- ── 4. Retenção de mensagens configurável ────────────────────
-- Fechava o par com a retenção de GPS: `messages` e `channel_messages`
-- cresciam para sempre, sem política declarada.
-- Default 0 = sem expiração (comportamento atual preservado); a empresa
-- decide conscientemente quando quiser ligar.
CREATE OR REPLACE FUNCTION public.fn_org_msg_retencao_dias(p_org uuid)
RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT COALESCE(NULLIF(settings->>'msg_retencao_dias', '')::int, 0)
    FROM public.organizations WHERE id = p_org;
$$;
REVOKE ALL ON FUNCTION public.fn_org_msg_retencao_dias(uuid) FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.cleanup_old_messages()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org     record;
  v_dias    int;
  v_deleted int := 0;
  v_total   int := 0;
BEGIN
  FOR v_org IN SELECT id FROM public.organizations LOOP
    v_dias := public.fn_org_msg_retencao_dias(v_org.id);
    CONTINUE WHEN v_dias <= 0;   -- 0 = retenção indefinida

    DELETE FROM public.messages m
     WHERE m.created_at < NOW() - (v_dias || ' days')::interval
       AND EXISTS (SELECT 1 FROM public.users u
                    WHERE u.id = m.sender_id AND u.organization_id = v_org.id);
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    v_total := v_total + v_deleted;

    DELETE FROM public.channel_messages cm
     WHERE cm.created_at < NOW() - (v_dias || ' days')::interval
       AND EXISTS (SELECT 1 FROM public.users u
                    WHERE u.id = cm.sender_id AND u.organization_id = v_org.id);
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    v_total := v_total + v_deleted;
  END LOOP;

  RETURN v_total;
END;
$$;
REVOKE ALL ON FUNCTION public.cleanup_old_messages() FROM PUBLIC, anon;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('msg-retencao-diaria')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'msg-retencao-diaria');
    PERFORM cron.schedule('msg-retencao-diaria', '40 3 * * *',
      $cron$ SELECT public.cleanup_old_messages(); $cron$);
  ELSE
    RAISE WARNING 'pg_cron não habilitado: retenção de mensagens não será aplicada.';
  END IF;
END $$;
