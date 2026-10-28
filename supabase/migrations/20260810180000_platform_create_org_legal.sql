-- ============================================================
-- Cadastro de empresa passa a capturar o perfil legal (LGPD)
--
-- PROBLEMA
-- `platform_create_organization` criava a empresa só com nome, slug, razão
-- social e CNPJ. Os demais dados que os documentos LGPD exigem — endereço,
-- Encarregado, e-mail do DPO, data de vigência — ficavam para depois, e
-- "depois" quer dizer que o primeiro colaborador da empresa nova aceita
-- Termos de Uso com `[RAZÃO SOCIAL]` e `[E-MAIL DO DPO]` literais na tela.
--
-- Aceite registrado sobre documento não personalizado é aceite de um texto que
-- não identifica o controlador nem o canal de exercício de direitos. Como
-- prova, vale pouco.
--
-- DESENHO
-- O perfil legal entra no MESMO ato da criação, na mesma transação. Sem RPC
-- adicional depois: `admin_set_org_legal_profile` opera sobre `fn_current_org()`
-- e o dono da plataforma não está atuando na empresa recém-criada — chamá-la
-- aqui gravaria o perfil na empresa ERRADA.
--
-- A função de 4 argumentos é DERRUBADA em vez de mantida: com a de 5 tendo
-- default, uma chamada nomeada com os 4 primeiros casaria com as duas e o
-- PostgREST devolveria erro de função ambígua.
-- ============================================================

DROP FUNCTION IF EXISTS public.platform_create_organization(text, text, text, text);

CREATE OR REPLACE FUNCTION public.platform_create_organization(
  p_name       text,
  p_slug       text,
  p_legal_name text  DEFAULT NULL,
  p_cnpj       text  DEFAULT NULL,
  p_legal      jsonb DEFAULT '{}'::jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_id    uuid;
  v_legal jsonb;
BEGIN
  IF NOT public.fn_is_platform_owner() THEN
    RAISE EXCEPTION 'Apenas o dono da plataforma pode criar empresas';
  END IF;
  IF COALESCE(trim(p_name), '') = '' THEN
    RAISE EXCEPTION 'Informe o nome da empresa';
  END IF;
  p_slug := lower(trim(p_slug));
  IF p_slug !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$' THEN
    RAISE EXCEPTION 'Slug inválido (use apenas letras minúsculas, números e hífen)';
  END IF;

  -- Mesma forma de `settings.legal` que `admin_set_org_legal_profile` grava e
  -- que `get_org_legal_profile()` lê. Chave vazia é descartada: campo em branco
  -- tem de continuar aparecendo como pendência, não virar string vazia.
  v_legal := jsonb_strip_nulls(jsonb_build_object(
    'endereco',          NULLIF(trim(p_legal->>'endereco'), ''),
    'dpo_nome',          NULLIF(trim(p_legal->>'dpo_nome'), ''),
    'dpo_email',         NULLIF(trim(p_legal->>'dpo_email'), ''),
    'dpo_telefone',      NULLIF(trim(p_legal->>'dpo_telefone'), ''),
    'comarca',           NULLIF(trim(p_legal->>'comarca'), ''),
    'vigencia',          NULLIF(trim(p_legal->>'vigencia'), ''),
    'regiao_hospedagem', NULLIF(trim(p_legal->>'regiao_hospedagem'), ''),
    'telefone_plantao',  NULLIF(trim(p_legal->>'telefone_plantao'), '')
  ));

  INSERT INTO public.organizations (name, slug, legal_name, cnpj, settings)
  VALUES (
    trim(p_name),
    p_slug,
    NULLIF(trim(p_legal_name), ''),
    NULLIF(trim(p_cnpj), ''),
    jsonb_build_object('legal', v_legal)
  )
  RETURNING id INTO v_id;

  -- Provisiona os perfis-padrão de RBAC da nova org (reusa autoprovision)
  PERFORM public.fn_setup_default_roles(v_id);

  -- INSERT direto, e não fn_audit: aquela função resolve a org por
  -- fn_current_org(), que aqui é a empresa NATAL ou a EM ATUAÇÃO do dono da
  -- plataforma — nunca a que acabou de nascer. Pelo caminho dela, a linha com o
  -- slug do cliente novo ficaria carimbada com o id de outro tenant e visível
  -- ao admin daquele tenant (a policy de auditoria filtra por org), enquanto a
  -- empresa criada nasceria sem registro da própria criação — justo a entrada
  -- que sustenta o Art. 37 para ela.
  INSERT INTO public.audit_log
    (organization_id, actor_id, action, target_type, target_id, details)
  VALUES (
    v_id,
    auth.uid(),
    'platform.org_created',
    'organization',
    v_id::text,
    jsonb_build_object(
      'slug', p_slug,
      'perfil_legal_campos', (
        SELECT COALESCE(jsonb_agg(k), '[]'::jsonb)
          FROM jsonb_object_keys(v_legal) k)));

  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Já existe uma empresa com este slug';
END;
$$;

REVOKE ALL ON FUNCTION
  public.platform_create_organization(text, text, text, text, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.platform_create_organization(text, text, text, text, jsonb)
  TO authenticated;

COMMENT ON FUNCTION
  public.platform_create_organization(text, text, text, text, jsonb) IS
  'Cria a empresa já com o perfil legal em settings.legal, na mesma transação.
   O formato de p_legal espelha admin_set_org_legal_profile.';
