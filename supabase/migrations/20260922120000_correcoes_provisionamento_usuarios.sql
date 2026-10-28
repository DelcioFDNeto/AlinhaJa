-- ============================================================
-- Correções retidas no repositório irmão: senha provisória e não lidas
--
-- ORIGEM
-- As correções abaixo foram aplicadas no Fluxy dentro das migrations
-- 20260908150000 e 20260908160000, ambas marcadas
-- "[EXCLUSIVO FLUXY / SHINERAY BY SABEL — NÃO REPLICAR NO ALINHAJÁ]" porque
-- carregam o cadastro de pessoal daquela empresa. A trava do playbook de sync
-- protegeu os dados — e junto ficou retida a parte técnica, que vale para os
-- dois produtos.
--
-- O QUE FOI CONFERIDO NO BANCO VIVO (PROD e DEV, 22/09/2026)
-- `pg_get_functiondef` para `increment_channel_unread_count` e
-- `notify_new_user_registration` voltou vazio nos dois ambientes: nenhuma das
-- duas jamais existiu aqui. Ou seja, não era uma versão defasada a corrigir —
-- era ausência. Por isso a seção 2 CRIA a função, em vez de só endurecer uma
-- existente, e a seção 3 não cria nada.
--
-- O QUE FOI DELIBERADAMENTE DEIXADO DE FORA
-- A `handle_new_user` do Fluxy passou a honrar `role_level` e `is_active`
-- vindos de `raw_user_meta_data`. Isso NÃO é replicado aqui: `signup_screen`
-- chama `supabase.auth.signUp` com o metadata montado no cliente e o cadastro
-- é aberto, então qualquer pessoa de posse da chave anon — que é pública, vai
-- embutida na build web — poderia se registrar como `super_admin` já ativo,
-- escapando do `banned_until` que segura os cadastros até a aprovação. A
-- `handle_new_user` deste repositório ignora os dois campos, e é isso que a
-- mantém segura. Mantenha assim.
-- ============================================================


-- ============================================================
-- 1. SENHA PROVISÓRIA VOLTA A SER OBRIGATORIAMENTE TROCADA
--
-- PROBLEMA
-- A coluna `users.must_change_password` (20260903140100) tem DEFAULT false e
-- só foi marcada uma vez, no backfill daquela migration. Desde então, todo
-- usuário criado por um administrador nascia com a flag em false: o admin
-- define uma senha provisória, entrega para a pessoa, e o app nunca exige a
-- troca. A `force_change_password_screen` existe e nunca era acionada.
--
-- POR QUE AQUI E NÃO NA handle_new_user
-- O Fluxy resolveu carimbando a flag na trigger `handle_new_user`, que dispara
-- em TODO insert de `auth.users`. Aqui isso pegaria também o auto-cadastro do
-- `signup_screen`, onde a própria pessoa escolhe a senha — forçá-la a trocar a
-- senha que acabou de definir é ruído sem ganho. `admin_create_user` é o ponto
-- exato em que existe senha provisória: quem digitou a senha foi o admin, não
-- o dono da conta.
--
-- O ciclo fecha no app: `login_screen` lê a flag, leva para a
-- `force_change_password_screen`, que chama `mark_password_changed()`.
--
-- Corpo idêntico ao vigente (20260813151000) + `must_change_password = true`
-- no UPDATE final. O `phone` segue NULL (ver cabeçalho daquela migration).
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_create_user(
  p_email TEXT,
  p_password TEXT,
  p_full_name TEXT,
  p_branch_id UUID,
  p_role_level public.user_role_level,
  p_department_id TEXT DEFAULT NULL,
  p_job_position_id TEXT DEFAULT NULL,
  p_sexo TEXT DEFAULT NULL,
  p_data_nascimento DATE DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_new_user_id UUID;
  v_org UUID := public.fn_current_org();
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role_level IN ('super_admin', 'admin')
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas Administradores podem criar usuários.';
  END IF;

  v_new_user_id := gen_random_uuid();

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    phone, phone_confirmed_at, confirmation_token, recovery_token,
    email_change_token_new, email_change, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_new_user_id, 'authenticated', 'authenticated',
    LOWER(p_email),
    extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}',
    -- carimba a org do admin já no metadata (o trigger usa; o UPDATE reforça)
    jsonb_build_object('full_name', p_full_name, 'organization_id', v_org::text),
    -- phone NULL (não ''): ver cabeçalho, constraint users_phone_key
    NULL, NULL, '', '', '', '', now(), now()
  );

  INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_new_user_id, v_new_user_id::text,
    jsonb_build_object('sub', v_new_user_id::text, 'email', LOWER(p_email), 'email_verified', true, 'phone_verified', false),
    'email', now(), now(), now()
  );

  UPDATE public.users
  SET
    organization_id = v_org,
    branch_id = p_branch_id,
    role_level = p_role_level,
    department_id = p_department_id,
    job_position_id = p_job_position_id,
    sexo = COALESCE(p_sexo, sexo),
    data_nascimento = COALESCE(p_data_nascimento, data_nascimento),
    is_active = true,
    -- Senha definida pelo admin: exige troca no primeiro login.
    must_change_password = true
  WHERE id = v_new_user_id;

  UPDATE auth.users SET banned_until = NULL WHERE id = v_new_user_id;

  RETURN v_new_user_id;

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Detailed Error: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END;
$$;


-- ============================================================
-- 2. CONTADOR DE NÃO LIDAS DOS CANAIS VOLTA A CONTAR
--
-- PROBLEMA
-- `channel_members.unread_count` existe desde a 20260528000000 e o app depende
-- dela: `channels_list_provider` lê a coluna direto
-- (`select('channel_id, unread_count')`) e `channels_tab` desenha o badge e o
-- negrito a partir dela. Só que nada neste banco jamais incrementou a coluna —
-- a única trigger de `channel_messages` aqui é a `update_channel_last_message`,
-- que só carimba `last_message_at`. O outro lado do ciclo já existe e funciona
-- — `_markAsRead` em `active_channel_provider` e o gateway de notificações
-- zeram a coluna direto na tabela (o GRANT da 20260813110000 permite), e há a
-- `mark_all_channels_as_read()`. Só que zerar algo que nunca sobe não muda
-- nada: **nenhum canal jamais mostrou mensagens não lidas no AlinhaJá.**
--
-- O Fluxy tem a trigger `increment_channel_unread_count` desde antes do
-- versionamento e a endureceu na 20260908150000. Aqui ela é criada agora, já
-- na forma endurecida.
--
-- ISOLAMENTO ENTRE EMPRESAS
-- O UPDATE é ancorado em `NEW.channel_id`, e `channel_members` é chaveada por
-- (channel_id, user_id): um canal pertence a uma única organização, então os
-- membros atingidos são sempre os daquele canal. Não há filtro de org a fazer —
-- e não se deve usar `fn_current_org()` aqui, porque a trigger também roda em
-- inserts de serviço (webhooks, bots), onde não há org em atuação.
--
-- DIFERENÇA PROPOSITAL EM RELAÇÃO AO FLUXY
-- O Fluxy usa `user_id != NEW.sender_id`. Quando `sender_id` é NULL (mensagem
-- de sistema, ou remetente removido — a FK é ON DELETE SET NULL), a comparação
-- resulta em NULL e nenhuma linha é atualizada: a mensagem não conta para
-- ninguém. `IS DISTINCT FROM` trata NULL como "diferente de todos", que é o
-- comportamento correto para mensagem de sistema.
-- ============================================================

CREATE OR REPLACE FUNCTION public.increment_channel_unread_count()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  UPDATE public.channel_members
     SET unread_count = COALESCE(unread_count, 0) + 1
   WHERE channel_id = NEW.channel_id
     AND user_id IS DISTINCT FROM NEW.sender_id;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.increment_channel_unread_count() FROM PUBLIC, anon;

COMMENT ON FUNCTION public.increment_channel_unread_count() IS
  'Soma 1 em channel_members.unread_count para todos os membros do canal, menos '
  'o remetente. O app zera a coluna ao abrir o canal e em '
  'mark_all_channels_as_read().';

DROP TRIGGER IF EXISTS trg_increment_channel_unread ON public.channel_messages;
CREATE TRIGGER trg_increment_channel_unread
  AFTER INSERT ON public.channel_messages
  FOR EACH ROW EXECUTE FUNCTION public.increment_channel_unread_count();

-- Sem backfill proposital: recalcular o histórico exigiria varrer
-- `channel_messages` contra o `last_read_at` de cada membro, um UPDATE pesado
-- em produção para corrigir um badge. A contagem passa a valer das mensagens
-- novas em diante; qualquer canal aberto uma vez zera e segue correto.


-- ============================================================
-- 3. O QUE NÃO ENTRA AQUI: notify_new_user_registration
--
-- O Fluxy tem uma trigger que, a cada auto-cadastro pendente, posta um aviso
-- de bot num canal "Administração TI". Ela não existe neste banco e não é
-- criada aqui: trazê-la seria adicionar um recurso novo ao produto, não
-- corrigir uma defasagem — e ela depende de um usuário-bot
-- (00000000-0000-0000-0000-000000000001) e de um canal dedicado que este
-- ambiente não tem.
--
-- Se um dia for adotada, a versão do Fluxy NÃO serve como está: ela procura o
-- canal por `WHERE name = 'Administração TI'` sem filtrar `organization_id` e
-- cria o canal e a mensagem sem carimbar a org. Em base multi-tenant isso faz
-- o aviso de cadastro de uma empresa cair no canal de outra. A adaptação
-- mínima é filtrar e carimbar por `NEW.organization_id` nos três pontos
-- (SELECT do canal, INSERT do canal, INSERT da mensagem).
-- ============================================================


-- ============================================================
-- 4. search_path FIXO EM retry_cv_extraction
--
-- A 20260903170000 varreu todas as `SECURITY DEFINER` sem `search_path` e
-- fixou `''` em cada uma. `retry_cv_extraction` nasceu depois, na
-- 20260918110200, sem o pin — as outras oito funções daquele mesmo arquivo
-- têm. A consulta a `pg_proc` no banco vivo (PROD, 22/09/2026) confirmou: é a
-- única `SECURITY DEFINER` deste schema ainda sem `search_path` fixo. Sem o
-- pin, a resolução dos nomes não qualificados dentro de uma função que roda
-- com os privilégios do dono passa a depender do `search_path` de quem chamou.
--
-- `''` (e não `public`) porque o corpo já qualifica tudo: `public.candidato`,
-- `public.candidato_curriculo`, `public.fn_rh_pode`, `public.fn_current_org`,
-- `public.get_edge_base_url`, `public.get_webhook_secret` e `net.http_post`. O
-- resto é pg_catalog, que independe de search_path.
--
-- O mesmo descuido existe no Fluxy e é corrigido lá pela 20260922130000.
-- ============================================================

ALTER FUNCTION public.retry_cv_extraction(UUID) SET search_path = '';


NOTIFY pgrst, 'reload schema';
