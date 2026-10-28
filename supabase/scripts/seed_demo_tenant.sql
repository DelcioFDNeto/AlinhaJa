-- ============================================================================
-- SEED MANUAL — Empresa fictícia para testar o multi-tenant
-- ============================================================================
-- Provisiona um tenant COMPLETO e ISOLADO ("Nimbus Tecnologia"):
--   • organizations              → a empresa
--   • perfis RBAC padrão         → via fn_setup_default_roles
--   • 1 usuário admin            → auth.users + public.users (org carimbada)
--   • canais operacionais        → chats(type='channel') com workflow
--   • workflow_status_config     → etapas de cada canal
--   • chat_members               → admin como owner dos canais
--
-- IMPORTANTE — carimbo de org no seed:
--   O trigger trg_force_org só FORÇA a org quando auth.uid() != null
--   (usuário logado). Rodando este seed como service_role/postgres,
--   auth.uid() é NULL → o trigger NÃO sobrescreve, mas o DEFAULT da coluna
--   (DuBairro) venceria se a org fosse omitida. Por isso TODO insert em
--   chats/chat_members/workflow_status_config seta organization_id
--   EXPLICITAMENTE = v_org.
--
-- Idempotente: pode rodar várias vezes sem duplicar.
-- Rodar via Supabase MCP (apply_migration/execute_sql) ou psql/service role.
--
-- Credenciais de acesso geradas:
--   E-mail: admin@nimbus.com
--   Senha:  Nimbus123
-- ============================================================================

DO $$
DECLARE
  v_org      UUID := 'b0000000-0000-4000-8000-000000000002';  -- id fixo (idempotência)
  v_admin_id UUID;
  v_ch_help  UUID;
  v_ch_contas UUID;
  c_email    TEXT := 'admin@nimbus.com';
  c_password TEXT := 'Nimbus123';
BEGIN
  -- ── 1. Empresa (tenant) ───────────────────────────────────
  INSERT INTO public.organizations (id, name, slug, legal_name, cnpj)
  VALUES (v_org, 'Nimbus Tecnologia', 'nimbus',
          'NIMBUS TECNOLOGIA LTDA', '12.345.678/0001-90')
  ON CONFLICT (id) DO NOTHING;

  -- Perfis RBAC padrão da org (Super Admin, RH, Gestor, Colaborador)
  PERFORM public.fn_setup_default_roles(v_org);

  -- ── 2. Usuário admin da empresa ───────────────────────────
  SELECT id INTO v_admin_id FROM auth.users WHERE email = c_email;

  IF v_admin_id IS NULL THEN
    v_admin_id := gen_random_uuid();

    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      phone, phone_confirmed_at, confirmation_token, recovery_token,
      email_change_token_new, email_change, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      v_admin_id, 'authenticated', 'authenticated',
      c_email,
      extensions.crypt(c_password, extensions.gen_salt('bf', 10)),
      now(),
      '{"provider":"email","providers":["email"]}',
      -- o trigger handle_new_user lê organization_id daqui e já carimba
      jsonb_build_object('full_name', 'Administrador Nimbus',
                         'organization_id', v_org::text),
      '', NULL, '', '', '', '', now(), now()
    );

    INSERT INTO auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_admin_id, v_admin_id::text,
      jsonb_build_object('sub', v_admin_id::text, 'email', c_email,
                         'email_verified', true, 'phone_verified', false),
      'email', now(), now(), now()
    );
  END IF;

  -- Garante papel/estado/org do admin (handle_new_user cria como member inativo)
  UPDATE public.users
     SET organization_id = v_org,
         role_level       = 'admin',
         is_active        = true,
         full_name        = 'Administrador Nimbus'
   WHERE id = v_admin_id;

  UPDATE auth.users SET banned_until = NULL WHERE id = v_admin_id;

  -- Perfil RBAC padrão (admin → "Super Admin" da própria org)
  PERFORM public.fn_assign_default_rbac_role(v_admin_id);

  -- ── 3. Canais operacionais (chats type='channel') ─────────
  INSERT INTO public.channels (organization_id, type, name, description, created_by, metadata)
  SELECT v_org, 'channel', 'Helpdesk Nimbus',
         'Chamados internos de TI e suporte da Nimbus.',
         v_admin_id,
         '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"generic","category":"suporte","color":"#1565C0","icon":"headset_mic_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE NOT EXISTS (
    SELECT 1 FROM public.channels
    WHERE organization_id = v_org AND name = 'Helpdesk Nimbus');

  INSERT INTO public.channels (organization_id, type, name, description, created_by, metadata)
  SELECT v_org, 'channel', 'Contas a Pagar',
         'Solicitações de contas a pagar da Nimbus.',
         v_admin_id,
         '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"conta_pagar","category":"financeiro","color":"#2E7D32","icon":"payments_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::jsonb
  WHERE NOT EXISTS (
    SELECT 1 FROM public.channels
    WHERE organization_id = v_org AND name = 'Contas a Pagar');

  SELECT id INTO v_ch_help
    FROM public.channels WHERE organization_id = v_org AND name = 'Helpdesk Nimbus'
    ORDER BY created_at LIMIT 1;
  SELECT id INTO v_ch_contas
    FROM public.channels WHERE organization_id = v_org AND name = 'Contas a Pagar'
    ORDER BY created_at LIMIT 1;

  -- ── 4. Admin como owner dos canais ────────────────────────
  INSERT INTO public.channel_members (organization_id, channel_id, user_id, role) VALUES
    (v_org, v_ch_help,   v_admin_id, 'owner'),
    (v_org, v_ch_contas, v_admin_id, 'owner')
  ON CONFLICT (channel_id, user_id) DO UPDATE SET role = EXCLUDED.role;

  -- ── 5. Etapas de workflow por canal ───────────────────────
  DELETE FROM public.workflow_status_config
   WHERE channel_id IN (v_ch_help, v_ch_contas);

  INSERT INTO public.workflow_status_config
    (organization_id, channel_id, status, status_order, color, icon, is_final) VALUES
    (v_org, v_ch_help,   'Aberto',       1, '#3B82F6', 'add_circle',       FALSE),
    (v_org, v_ch_help,   'Em andamento', 2, '#F59E0B', 'sync',             FALSE),
    (v_org, v_ch_help,   'Resolvido',    3, '#059669', 'task_alt',         TRUE),

    (v_org, v_ch_contas, 'Novo',                  1, '#3B82F6', 'add_circle',      FALSE),
    (v_org, v_ch_contas, 'Aguardando Aprovação',  2, '#F59E0B', 'hourglass_empty', FALSE),
    (v_org, v_ch_contas, 'Pago',                  3, '#059669', 'task_alt',        TRUE);

  RAISE NOTICE 'Seed do tenant Nimbus aplicado. Login: % / %', c_email, c_password;
END $$;
