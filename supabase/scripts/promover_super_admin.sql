-- ============================================================
-- Promove um usuário EXISTENTE a super_admin ativo
--
-- Substitui a antiga conta mestre fixa em `handle_new_user()`: o primeiro
-- administrador de uma instalação passa a ser definido por quem instala,
-- de forma explícita e registrada no log de auditoria.
--
-- Uso (como postgres, na instalação):
--
--   psql "postgresql://postgres:<senha>@<host>:5432/postgres" \
--        -v email=admin@cliente.com.br \
--        -f supabase/scripts/promover_super_admin.sql
--
-- Opcional, só para quem opera o Console de Plataforma:
--        -v dono_plataforma=sim
--
-- O usuário precisa existir antes: criado pelo painel do Supabase
-- (Authentication → Add user), por convite ou pelo seed_demo_tenant.sql.
-- ============================================================
\set ON_ERROR_STOP on

\if :{?email}
\else
  \echo 'Informe o e-mail do usuário: -v email=admin@empresa.com.br'
  \quit
\endif

\if :{?dono_plataforma}
\else
  \set dono_plataforma nao
\endif

-- Variáveis do psql não chegam dentro do bloco DO: passam por set_config.
SELECT set_config('instalacao.email', lower(trim(:'email')), false),
       set_config('instalacao.dono_plataforma', :'dono_plataforma', false);

DO $$
DECLARE
  v_email TEXT := current_setting('instalacao.email');
  v_dono  BOOLEAN := current_setting('instalacao.dono_plataforma') = 'sim';
  v_id    UUID;
  v_org   UUID;
BEGIN
  SELECT id INTO v_id FROM auth.users WHERE lower(email) = v_email;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Usuário % não existe em auth.users. Crie a conta antes.', v_email;
  END IF;

  UPDATE public.users
     SET role_level = 'super_admin',
         is_active  = true,
         is_platform_owner = is_platform_owner OR v_dono
   WHERE id = v_id
  RETURNING organization_id INTO v_org;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuário % não tem perfil em public.users.', v_email;
  END IF;

  -- Cadastro pendente nasce bloqueado (handle_new_user): libera o login.
  UPDATE auth.users SET banned_until = NULL WHERE id = v_id;

  INSERT INTO public.audit_log
    (organization_id, actor_id, action, target_type, target_id, details)
  VALUES (
    v_org, NULL, 'user.promoted_super_admin', 'user', v_id::text,
    jsonb_build_object('origem', 'script_instalacao',
                       'dono_plataforma', v_dono,
                       'executado_em', NOW()));

  RAISE NOTICE 'Usuário % promovido a super_admin%.', v_email,
    CASE WHEN v_dono THEN ' e dono da plataforma' ELSE '' END;
END $$;
