-- ============================================================
-- Perfil legal da empresa — preenche os documentos LGPD por tenant
--
-- PROBLEMA
-- Os documentos em `docs/legal/` nascem com `[RAZÃO SOCIAL]`, `[CNPJ]`,
-- `[E-MAIL DO DPO]` e afins entre colchetes. Hoje só `[NOME_DA_EMPRESA]` é
-- substituído, e por uma constante de build — o que funciona num produto de
-- empresa única e é ERRADO num produto white label: o documento de um cliente
-- sairia com o nome de outro.
--
-- Já aconteceu nesta base o equivalente com o bot de IA, que passou meses
-- dizendo a colaborador de uma empresa que ele trabalhava na outra, porque o
-- nome estava fixo no código. Documento jurídico com a razão social errada é a
-- versão cara desse mesmo erro.
--
-- DESENHO
--   • O perfil legal é DADO DO TENANT, não constante de build. Mora em
--     `organizations.settings.legal` (mais `legal_name`/`cnpj`, que já são
--     colunas) e é lido pela org corrente.
--   • `fn_current_org()` é quem resolve o tenant. Em produto de empresa única
--     ele devolve a org do usuário; no white label ele já honra a "empresa em
--     atuação" do dono da plataforma. Como toda a leitura passa por ele, o
--     MESMO código serve aos dois produtos sem ramificação.
--   • Escrita só por RPC guardada por papel e auditada: razão social e CNPJ em
--     documento de aceite são prova, e prova que qualquer um edita não é prova.
-- ============================================================

-- ── 1. Forma do perfil, documentada no próprio banco ─────────
COMMENT ON COLUMN public.organizations.settings IS
  'Configurações do tenant. Chaves conhecidas:
     modules                  → módulos licenciáveis contratados (array)
     gps_retencao_dias        → retenção do histórico de localização (default 7)
     candidato_retencao_meses → retenção de candidatos (default 24)
     msg_retencao_dias        → retenção de mensagens (0 = indefinida)
     legal                    → perfil legal usado nos documentos LGPD:
       { endereco, dpo_nome, dpo_email, dpo_telefone, comarca,
         vigencia (YYYY-MM-DD), regiao_hospedagem, telefone_plantao }';

-- ── 2. Leitura: perfil legal da org corrente ─────────────────
-- SECURITY DEFINER para montar o objeto sem depender de a policy de SELECT de
-- `organizations` cobrir cada chamador; o escopo continua sendo a org corrente,
-- nunca outra.
--
-- Devolve também os prazos de retenção EFETIVOS. Sem isso o documento afirma
-- "7 dias" enquanto o tenant configurou 30 — política declarada e não cumprida
-- é agravante em fiscalização (Art. 15/16), então o texto tem de dizer o que o
-- sistema faz, não o que o modelo dizia.
CREATE OR REPLACE FUNCTION public.get_org_legal_profile()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org  uuid;
  v_row  record;
  v_legal jsonb;
BEGIN
  v_org := public.fn_current_org();
  IF v_org IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT o.name, o.legal_name, o.cnpj, o.settings
    INTO v_row
    FROM public.organizations o
   WHERE o.id = v_org;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  v_legal := COALESCE(v_row.settings->'legal', '{}'::jsonb);

  RETURN jsonb_build_object(
    'organization_id',    v_org,
    'nome_fantasia',      v_row.name,
    'razao_social',       v_row.legal_name,
    'cnpj',               v_row.cnpj,
    'endereco',           v_legal->>'endereco',
    'dpo_nome',           v_legal->>'dpo_nome',
    'dpo_email',          v_legal->>'dpo_email',
    'dpo_telefone',       v_legal->>'dpo_telefone',
    'comarca',            v_legal->>'comarca',
    'vigencia',           v_legal->>'vigencia',
    'regiao_hospedagem',  v_legal->>'regiao_hospedagem',
    'telefone_plantao',   v_legal->>'telefone_plantao',
    -- Prazos efetivos, com os mesmos defaults das rotinas de expurgo.
    'gps_retencao_dias',
      COALESCE(NULLIF(v_row.settings->>'gps_retencao_dias', ''), '7'),
    'candidato_retencao_meses',
      COALESCE(NULLIF(v_row.settings->>'candidato_retencao_meses', ''), '24'),
    'msg_retencao_dias',
      COALESCE(NULLIF(v_row.settings->>'msg_retencao_dias', ''), '0')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_org_legal_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_org_legal_profile() TO authenticated;

COMMENT ON FUNCTION public.get_org_legal_profile() IS
  'Perfil legal da org corrente para preencher os documentos LGPD. Resolve o
   tenant por fn_current_org(), portanto acompanha a empresa em atuação.';

-- ── 3. Escrita: só admin da própria org, auditada ────────────
-- Recebe o objeto inteiro e faz merge sobre `settings.legal`, preservando as
-- demais chaves de `settings` (módulos, prazos). Chaves com valor nulo são
-- REMOVIDAS — é assim que se apaga um campo preenchido por engano.
CREATE OR REPLACE FUNCTION public.admin_set_org_legal_profile(p_profile jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org       uuid;
  v_is_admin  boolean;
  v_legal     jsonb;
  v_razao     text;
  v_cnpj      text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida';
  END IF;

  v_org := public.fn_current_org();
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Organização não resolvida para este usuário';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.users u
     WHERE u.id = auth.uid()
       AND u.role_level IN ('super_admin', 'admin')
       AND u.is_active
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Apenas administradores podem alterar os dados legais';
  END IF;

  -- Razão social e CNPJ moram em coluna própria; o resto vai para settings.
  v_razao := NULLIF(p_profile->>'razao_social', '');
  v_cnpj  := NULLIF(p_profile->>'cnpj', '');

  v_legal := jsonb_strip_nulls(jsonb_build_object(
    'endereco',          NULLIF(p_profile->>'endereco', ''),
    'dpo_nome',          NULLIF(p_profile->>'dpo_nome', ''),
    'dpo_email',         NULLIF(p_profile->>'dpo_email', ''),
    'dpo_telefone',      NULLIF(p_profile->>'dpo_telefone', ''),
    'comarca',           NULLIF(p_profile->>'comarca', ''),
    'vigencia',          NULLIF(p_profile->>'vigencia', ''),
    'regiao_hospedagem', NULLIF(p_profile->>'regiao_hospedagem', ''),
    'telefone_plantao',  NULLIF(p_profile->>'telefone_plantao', '')
  ));

  UPDATE public.organizations o
     SET legal_name = COALESCE(v_razao, o.legal_name),
         cnpj       = COALESCE(v_cnpj,  o.cnpj),
         settings   = jsonb_set(
                        COALESCE(o.settings, '{}'::jsonb),
                        '{legal}',
                        v_legal,
                        true),
         updated_at = NOW()
   WHERE o.id = v_org;

  -- O QUE mudou fica no log; o CONTEÚDO não, para o log de auditoria não virar
  -- uma segunda cópia dos dados da empresa.
  PERFORM public.fn_audit('org.legal_profile.updated', 'organization',
    v_org::text,
    jsonb_build_object('campos', (
      SELECT COALESCE(jsonb_agg(k), '[]'::jsonb) FROM jsonb_object_keys(v_legal) k
    )));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_org_legal_profile(jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_org_legal_profile(jsonb)
  TO authenticated;

-- ── 4. Permissão RBAC da nova aba do painel ──────────────────
INSERT INTO public.rbac_permissions (module, action, description) VALUES
  ('admin_legal', 'view', 'Pode acessar os Dados Legais da empresa (LGPD)')
ON CONFLICT (module, action) DO NOTHING;

-- Super Admin recebe tudo; os demais perfis não ganham a aba automaticamente:
-- quem edita razão social e Encarregado num documento de aceite tem de ser
-- escolhido, não herdado.
DO $$
DECLARE
  r record;
  v_perm uuid;
BEGIN
  SELECT id INTO v_perm FROM public.rbac_permissions
   WHERE module = 'admin_legal' AND action = 'view';

  IF v_perm IS NULL THEN RETURN; END IF;

  FOR r IN SELECT id FROM public.rbac_roles WHERE name = 'Super Admin' LOOP
    INSERT INTO public.rbac_role_permissions (role_id, permission_id)
    VALUES (r.id, v_perm)
    ON CONFLICT DO NOTHING;
  END LOOP;
END $$;
