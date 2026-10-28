-- ============================================================
-- RH-22 — Consolidação das Fases 7/8/9 (hardening do scaffold)
-- 1. Multi-tenant padrão (trg_force_org + tenant_isolation +
--    module_entitlement RESTRICTIVE) nas tabelas rh17/rh19/rh21
-- 2. SMTP: senha nunca retorna ao cliente; RPC de service_role
--    sem EXECUTE público (vazamento cross-tenant corrigido)
-- 3. Automações: trigger candidato_historico → Edge Function
--    rh-automations (padrão webhook do ai-chatbot)
-- 4. Histórico salarial: RPC de inserção cifrada (o cliente não
--    tem acesso a fn_rh_encrypt)
-- 5. RBAC + entitlements dos módulos novos (automações, holerites,
--    ponto, benefícios, desempenho)
-- ============================================================

-- ── 1. Multi-tenant padrão nas tabelas das Fases 8/9 ─────────

DO $$
DECLARE
  t RECORD;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
      ('rh_ausencia',               'rh_ausencias'),
      ('rh_email_template',         'rh_automacoes'),
      ('rh_automacao',              'rh_automacoes'),
      ('rh_comunicacao_log',        'rh_automacoes'),
      ('org_smtp_config',           'rh_automacoes'),
      ('rh_historico_cargo_salario','rh_funcionarios'),
      ('rh_dependente',             'rh_funcionarios'),
      ('rh_beneficio',              'rh_beneficios'),
      ('rh_funcionario_beneficio',  'rh_beneficios'),
      ('rh_avaliacao_desempenho',   'rh_desempenho'),
      ('rh_holerite',               'rh_holerites'),
      ('rh_ponto_registro',         'rh_ponto')
    ) AS v(tbl, module)
  LOOP
    -- Força organization_id do usuário logado em todo INSERT
    EXECUTE format('DROP TRIGGER IF EXISTS trg_force_org ON public.%I', t.tbl);
    EXECUTE format(
      'CREATE TRIGGER trg_force_org BEFORE INSERT ON public.%I
         FOR EACH ROW EXECUTE FUNCTION public.fn_tg_force_current_org()',
      t.tbl);

    -- Isolamento por tenant (RESTRICTIVE: soma-se às policies existentes)
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON public.%I', t.tbl);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON public.%I AS RESTRICTIVE FOR ALL
         USING (organization_id = public.fn_current_org())
         WITH CHECK (organization_id = public.fn_current_org())',
      t.tbl);

    -- Licença do módulo por organização
    EXECUTE format('DROP POLICY IF EXISTS module_entitlement ON public.%I', t.tbl);
    EXECUTE format(
      'CREATE POLICY module_entitlement ON public.%I AS RESTRICTIVE FOR ALL
         USING (public.fn_org_has_module(%L))
         WITH CHECK (public.fn_org_has_module(%L))',
      t.tbl, t.module, t.module);
  END LOOP;
END;
$$;

-- ── 2. SMTP: hardening das RPCs (rh19/rh20) ──────────────────

-- 2a. A senha NUNCA volta ao cliente: a assinatura antiga retornava
-- password_decrypted para qualquer usuário RH. Agora retorna apenas
-- has_password (a UI mostra "senha salva" sem conhecê-la).
DROP FUNCTION IF EXISTS public.rh_get_smtp_config();
CREATE FUNCTION public.rh_get_smtp_config()
RETURNS TABLE (
  host TEXT, port INTEGER, username TEXT,
  from_email TEXT, from_name TEXT, has_password BOOLEAN
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
BEGIN
  IF NOT (public.fn_is_admin() OR public.fn_is_rh()) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  RETURN QUERY
  SELECT c.host, c.port, c.username, c.from_email, c.from_name,
         (c.password_encrypted IS NOT NULL) AS has_password
  FROM public.org_smtp_config c
  WHERE c.organization_id = v_org;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_get_smtp_config() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_get_smtp_config() TO authenticated;

-- 2b. Salvar: senha vazia preserva a senha já gravada (edição de
-- host/porta/remetente sem redigitar a credencial).
CREATE OR REPLACE FUNCTION public.rh_save_smtp_config(
  p_host TEXT, p_port INTEGER, p_username TEXT,
  p_password TEXT, p_from_email TEXT, p_from_name TEXT
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_secret TEXT;
  v_cipher BYTEA;
BEGIN
  IF NOT (public.fn_is_admin() OR public.fn_is_rh()) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Organização não resolvida';
  END IF;

  -- Chave por organização no Vault (mesmo padrão de fn_rh_encrypt);
  -- o salt estático derivável do rh19 nunca chegou a cifrar dados reais.
  v_secret := public.fn_rh_data_key(v_org);

  IF p_password IS NULL OR length(trim(p_password)) = 0 THEN
    SELECT c.password_encrypted INTO v_cipher
    FROM public.org_smtp_config c WHERE c.organization_id = v_org;
    IF v_cipher IS NULL THEN
      RAISE EXCEPTION 'Informe a senha do servidor SMTP';
    END IF;
  ELSE
    v_cipher := extensions.pgp_sym_encrypt(p_password, v_secret);
  END IF;

  INSERT INTO public.org_smtp_config (
    organization_id, host, port, username,
    password_encrypted, from_email, from_name
  ) VALUES (
    v_org, p_host, p_port, p_username, v_cipher, p_from_email, p_from_name
  )
  ON CONFLICT (organization_id) DO UPDATE SET
    host = EXCLUDED.host,
    port = EXCLUDED.port,
    username = EXCLUDED.username,
    password_encrypted = EXCLUDED.password_encrypted,
    from_email = EXCLUDED.from_email,
    from_name = EXCLUDED.from_name;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_save_smtp_config(TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_save_smtp_config(TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- 2c. CRÍTICO: a rh_get_smtp_server(p_org_id) nasceu SECURITY DEFINER
-- com EXECUTE default para qualquer authenticated — qualquer usuário
-- logado obtinha a senha SMTP descriptografada de QUALQUER organização.
-- Uso exclusivo da Edge Function (service_role).
CREATE OR REPLACE FUNCTION public.rh_get_smtp_server(p_org_id UUID)
RETURNS TABLE (
  host TEXT, port INTEGER, username TEXT,
  from_email TEXT, from_name TEXT, password_decrypted TEXT
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN QUERY
  SELECT c.host, c.port, c.username, c.from_email, c.from_name,
         extensions.pgp_sym_decrypt(
           c.password_encrypted,
           public.fn_rh_data_key(p_org_id)) AS password_decrypted
  FROM public.org_smtp_config c
  WHERE c.organization_id = p_org_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_get_smtp_server(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rh_get_smtp_server(UUID) TO service_role;

-- ── 3. Trigger de automações: candidato_historico → Edge Fn ──
-- A Edge Function rh-automations esperava organization_id/status_id
-- no record, mas candidato_historico não tem essas colunas — a
-- automação nunca dispararia. O trigger resolve a org aqui e só
-- acorda a function se a org tiver automação ativa (padrão do
-- trg_ai_chatbot: net.http_post + x-webhook-secret).
CREATE OR REPLACE FUNCTION public.fn_tg_rh_automacao_notify()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid;
  v_url text;
BEGIN
  IF NEW.acao <> 'mudanca_status' THEN
    RETURN NEW;
  END IF;

  SELECT c.organization_id INTO v_org
  FROM public.candidato c WHERE c.id = NEW.candidato_id;
  IF v_org IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.rh_automacao a
    WHERE a.organization_id = v_org
      AND a.ativo AND a.evento = 'mudanca_etapa'
  ) THEN
    RETURN NEW;
  END IF;

  v_url := public.get_edge_base_url() || '/rh-automations';
  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.get_webhook_secret()
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'candidato_historico',
      'organization_id', v_org,
      'record', row_to_json(NEW)
    )
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Falha no webhook nunca pode abortar a mudança de etapa
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rh_automacao_notify ON public.candidato_historico;
CREATE TRIGGER trg_rh_automacao_notify
  AFTER INSERT ON public.candidato_historico
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_rh_automacao_notify();

-- ── 4. Histórico salarial: inserção via RPC (cifrada + audit) ─
-- fn_rh_encrypt é REVOKEd de authenticated; sem esta RPC a UI não
-- teria como gravar o salário cifrado.
CREATE OR REPLACE FUNCTION public.rh_add_historico_cargo_salario(
  p_funcionario_id uuid,
  p_salario text,
  p_data_inicio date,
  p_motivo text,
  p_cargo_id text DEFAULT NULL,
  p_departamento_id text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_id uuid;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Apenas o RH pode registrar histórico salarial';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.funcionario f
    WHERE f.id = p_funcionario_id
      AND f.organization_id = v_org AND f.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Funcionário não encontrado nesta organização';
  END IF;
  IF coalesce(trim(p_motivo), '') = '' THEN
    RAISE EXCEPTION 'Informe o motivo do registro';
  END IF;

  INSERT INTO public.rh_historico_cargo_salario
    (organization_id, funcionario_id, cargo_id, departamento_id,
     salario_encrypted, data_inicio, motivo, created_by)
  VALUES
    (v_org, p_funcionario_id, nullif(p_cargo_id, ''), nullif(p_departamento_id, ''),
     public.fn_rh_encrypt(p_salario, v_org), p_data_inicio, trim(p_motivo), auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.rh_access_log
    (organization_id, funcionario_id, usuario_id, acao)
  VALUES (v_org, p_funcionario_id, auth.uid(), 'registrou_historico_salarial');

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_add_historico_cargo_salario(uuid, text, date, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_add_historico_cargo_salario(uuid, text, date, text, text, text) TO authenticated;

-- ── 4b. Benefícios: adesão com desconto cifrado ──────────────
-- valor_desconto_encrypted usa a mesma chave Vault da org; o cliente
-- não cifra nem decifra — tudo via RPC com guard de RH/próprio.
CREATE OR REPLACE FUNCTION public.rh_add_adesao_beneficio(
  p_funcionario_id uuid,
  p_beneficio_id uuid,
  p_data_adesao date,
  p_valor_desconto text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_id uuid;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Apenas o RH pode registrar adesões';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.funcionario f
    WHERE f.id = p_funcionario_id
      AND f.organization_id = v_org AND f.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Funcionário não encontrado nesta organização';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.rh_beneficio b
    WHERE b.id = p_beneficio_id AND b.organization_id = v_org AND b.ativo
  ) THEN
    RAISE EXCEPTION 'Benefício inativo ou de outra organização';
  END IF;

  INSERT INTO public.rh_funcionario_beneficio
    (organization_id, funcionario_id, beneficio_id, data_adesao,
     valor_desconto_encrypted)
  VALUES
    (v_org, p_funcionario_id, p_beneficio_id, p_data_adesao,
     public.fn_rh_encrypt(nullif(trim(coalesce(p_valor_desconto, '')), ''), v_org))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_add_adesao_beneficio(uuid, uuid, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_add_adesao_beneficio(uuid, uuid, date, text) TO authenticated;

-- Lista adesões com desconto decifrado: RH vê a org; colaborador vê
-- apenas as próprias adesões.
CREATE OR REPLACE FUNCTION public.rh_list_adesoes_beneficio(
  p_funcionario_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_res jsonb;
BEGIN
  IF NOT public.fn_is_rh() THEN
    IF p_funcionario_id IS NULL
       OR NOT public.fn_is_own_funcionario(p_funcionario_id) THEN
      RAISE EXCEPTION 'Acesso negado';
    END IF;
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'id', fb.id,
    'funcionario_id', fb.funcionario_id,
    'funcionario_nome', f.nome,
    'beneficio_id', fb.beneficio_id,
    'beneficio_nome', b.nome,
    'beneficio_tipo', b.tipo,
    'data_adesao', fb.data_adesao,
    'data_cancelamento', fb.data_cancelamento,
    'valor_desconto', public.fn_rh_decrypt(fb.valor_desconto_encrypted, v_org)
  ) ORDER BY fb.data_adesao DESC) INTO v_res
  FROM public.rh_funcionario_beneficio fb
  JOIN public.funcionario f ON f.id = fb.funcionario_id
  JOIN public.rh_beneficio b ON b.id = fb.beneficio_id
  WHERE fb.organization_id = v_org
    AND (p_funcionario_id IS NULL OR fb.funcionario_id = p_funcionario_id);

  RETURN coalesce(v_res, '[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.rh_list_adesoes_beneficio(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_list_adesoes_beneficio(uuid) TO authenticated;

-- ── 4c. Dependentes: CPF cifrado via RPC ─────────────────────
CREATE OR REPLACE FUNCTION public.rh_add_dependente(
  p_funcionario_id uuid,
  p_nome text,
  p_data_nascimento date,
  p_parentesco text,
  p_cpf text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_id uuid;
BEGIN
  IF NOT public.fn_is_rh() THEN
    RAISE EXCEPTION 'Apenas o RH pode registrar dependentes';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.funcionario f
    WHERE f.id = p_funcionario_id
      AND f.organization_id = v_org AND f.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Funcionário não encontrado nesta organização';
  END IF;

  INSERT INTO public.rh_dependente
    (organization_id, funcionario_id, nome, data_nascimento, parentesco,
     cpf_encrypted)
  VALUES
    (v_org, p_funcionario_id, trim(p_nome), p_data_nascimento, trim(p_parentesco),
     public.fn_rh_encrypt(nullif(trim(coalesce(p_cpf, '')), ''), v_org))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rh_add_dependente(uuid, text, date, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_add_dependente(uuid, text, date, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rh_list_dependentes(p_funcionario_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_res jsonb;
BEGIN
  IF NOT (public.fn_is_rh() OR public.fn_is_own_funcionario(p_funcionario_id)) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'id', d.id,
    'nome', d.nome,
    'data_nascimento', d.data_nascimento,
    'parentesco', d.parentesco,
    'cpf', public.fn_rh_decrypt(d.cpf_encrypted, v_org)
  ) ORDER BY d.data_nascimento) INTO v_res
  FROM public.rh_dependente d
  WHERE d.funcionario_id = p_funcionario_id AND d.organization_id = v_org;

  RETURN coalesce(v_res, '[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.rh_list_dependentes(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rh_list_dependentes(uuid) TO authenticated;

-- ── 4d. Storage: colaborador lê o PRÓPRIO holerite ───────────
-- Convenção de path: holerites/{funcionario_id}/{arquivo}.pdf no
-- bucket rh-documentos (que hoje só o RH lê).
DROP POLICY IF EXISTS "Funcionario le proprio holerite" ON storage.objects;
CREATE POLICY "Funcionario le proprio holerite"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'rh-documentos'
    AND name LIKE 'holerites/%'
    AND public.fn_is_own_funcionario(
          CASE WHEN (storage.foldername(name))[2]
                    ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}$'
               THEN ((storage.foldername(name))[2])::uuid END)
  );

-- ── 5. RBAC + entitlements dos módulos novos ─────────────────

INSERT INTO public.rbac_permissions (module, action, description) VALUES
  ('rh_automacoes', 'view',   'Pode visualizar templates de e-mail e automações'),
  ('rh_automacoes', 'manage', 'Pode gerenciar SMTP, templates e regras de automação'),
  ('rh_holerites',  'view',   'Pode visualizar holerites da organização'),
  ('rh_holerites',  'manage', 'Pode emitir e gerenciar holerites'),
  ('rh_ponto',      'view',   'Pode visualizar registros de ponto'),
  ('rh_ponto',      'manage', 'Pode ajustar e aprovar registros de ponto'),
  ('rh_beneficios', 'view',   'Pode visualizar benefícios e adesões'),
  ('rh_beneficios', 'manage', 'Pode gerenciar benefícios e adesões'),
  ('rh_desempenho', 'view',   'Pode visualizar avaliações de desempenho'),
  ('rh_desempenho', 'manage', 'Pode registrar avaliações de desempenho')
ON CONFLICT (module, action) DO NOTHING;

-- Backfill nos perfis já provisionados (Super Admin e RH de cada org)
INSERT INTO public.rbac_role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.rbac_roles r
CROSS JOIN public.rbac_permissions p
WHERE r.name IN ('Super Admin', 'RH')
  AND p.module IN ('rh_automacoes', 'rh_holerites', 'rh_ponto',
                   'rh_beneficios', 'rh_desempenho', 'rh_ausencias')
ON CONFLICT DO NOTHING;

-- Perfis padrão de orgs futuras nascem com os módulos novos
CREATE OR REPLACE FUNCTION public.fn_setup_default_roles(p_org_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_super  uuid;
  v_rh     uuid;
  v_gestor uuid;
  v_colab  uuid;
BEGIN
  v_super  := public.fn_ensure_role(p_org_id, 'Super Admin',
                'Acesso total ao sistema, painel e módulos sensíveis');
  v_rh     := public.fn_ensure_role(p_org_id, 'RH',
                'Gestão completa de Recursos Humanos');
  v_gestor := public.fn_ensure_role(p_org_id, 'Gestor',
                'Gestão de equipe com visão de RH limitada');
  v_colab  := public.fn_ensure_role(p_org_id, 'Colaborador',
                'Acesso padrão de funcionário');

  -- Super Admin: todas as permissões existentes
  INSERT INTO public.rbac_role_permissions (role_id, permission_id)
  SELECT v_super, id FROM public.rbac_permissions
  ON CONFLICT DO NOTHING;

  -- Colaborador: comunicação básica
  PERFORM public.fn_grant_perms(v_colab, ARRAY[
    'comunicacao_canais:view', 'comunicacao_conversas:view',
    'comunicacao_chamadas:view']);

  -- Gestor: comunicação + visão de RH + abrir chamados
  PERFORM public.fn_grant_perms(v_gestor, ARRAY[
    'comunicacao_canais:view', 'comunicacao_conversas:view',
    'comunicacao_chamadas:view',
    'rh_funcionarios:view', 'rh_documentos:view', 'rh_alertas:view',
    'rh_ausencias:view',
    'helpdesk:view']);

  -- RH: todo o módulo de RH + comunicação + helpdesk
  PERFORM public.fn_grant_perms(v_rh, ARRAY[
    'comunicacao_canais:view', 'comunicacao_conversas:view',
    'comunicacao_chamadas:view',
    'rh_banco_talentos:view', 'rh_banco_talentos:manage',
    'rh_funcionarios:view', 'rh_funcionarios:manage',
    'rh_documentos:view', 'rh_documentos:manage',
    'rh_onboarding:view', 'rh_onboarding:manage',
    'rh_alertas:view',
    'rh_ausencias:view', 'rh_ausencias:manage',
    'rh_automacoes:view', 'rh_automacoes:manage',
    'rh_holerites:view', 'rh_holerites:manage',
    'rh_ponto:view', 'rh_ponto:manage',
    'rh_beneficios:view', 'rh_beneficios:manage',
    'rh_desempenho:view', 'rh_desempenho:manage',
    'helpdesk:view', 'helpdesk:manage']);
END;
$$;
REVOKE ALL ON FUNCTION public.fn_setup_default_roles(uuid) FROM PUBLIC, anon, authenticated;

-- Entitlements: orgs que já têm o RH ganham os módulos novos
-- (rh_ausencias já foi semeado pela rh18)
DO $$
DECLARE
  m TEXT;
BEGIN
  FOREACH m IN ARRAY ARRAY['rh_holerites', 'rh_ponto', 'rh_beneficios', 'rh_desempenho']
  LOOP
    UPDATE public.organizations
    SET settings = jsonb_set(
          settings, '{modules}',
          (settings->'modules') || to_jsonb(m))
    WHERE settings->'modules' IS NOT NULL
      AND NOT (settings->'modules' @> to_jsonb(ARRAY[m]))
      AND (settings->'modules' @> '["rh_funcionarios"]'::jsonb);
  END LOOP;

  UPDATE public.organizations
  SET settings = jsonb_set(
        settings, '{modules}',
        (settings->'modules') || '["rh_automacoes"]'::jsonb)
  WHERE settings->'modules' IS NOT NULL
    AND NOT (settings->'modules' @> '["rh_automacoes"]'::jsonb)
    AND (settings->'modules' @> '["rh_banco_talentos"]'::jsonb);
END;
$$;
