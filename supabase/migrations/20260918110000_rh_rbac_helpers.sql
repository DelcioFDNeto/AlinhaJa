-- =============================================================
-- RH passa a obedecer o RBAC (1/7): helpers, laços e Storage
-- =============================================================
-- Antes: o app escolhia os menus de RH pelo RBAC, mas o banco liberava os
-- dados por users.role_level/hr_role (fn_is_rh). O hr_role nunca foi
-- atribuído, então na prática só admin via RH — e todo admin via salários,
-- com ou sem perfil de RH. `view`/`manage` não tinham efeito.
--
-- Agora cada política e RPC do RH confere a permissão RBAC do SEU módulo:
-- leitura → `view`, escrita → `manage` (que implica `view`). Super Admin
-- passa sempre (dono da empresa não fica trancado fora). Admin comum segue
-- o perfil como qualquer usuário.
--
-- Arquivos 2..7: políticas das tabelas e RPCs, geradas a partir da última
-- definição de cada objeto — só a checagem de acesso muda.
-- =============================================================

-- ── 1. Permissão RBAC do módulo ──────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_rh_pode(p_module text, p_action text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid()
        AND u.role_level = 'super_admin'
        AND COALESCE(u.is_active, true)
    )
    OR EXISTS (
      SELECT 1
      FROM public.rbac_user_roles ur
      JOIN public.users u ON u.id = ur.user_id
      JOIN public.rbac_roles r ON r.id = ur.role_id
      JOIN public.rbac_role_permissions rp ON rp.role_id = ur.role_id
      JOIN public.rbac_permissions p ON p.id = rp.permission_id
      WHERE ur.user_id = auth.uid()
        AND COALESCE(u.is_active, true)
        -- Perfil de outra organização não vale aqui.
        AND r.organization_id = public.fn_current_org()
        AND p.module = p_module
        AND (p.action = p_action OR (p_action = 'view' AND p.action = 'manage'))
    );
$$;

REVOKE ALL ON FUNCTION public.fn_rh_pode(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_rh_pode(text, text) TO authenticated;

COMMENT ON FUNCTION public.fn_rh_pode(text, text) IS
  'Permissão RBAC (módulo, ação) do usuário logado. manage implica view; super_admin passa.';

-- ── 2. fn_is_rh / fn_is_rh_admin viram RBAC ──────────────────
-- Depois deste lote nenhuma política ou RPC do RH os usa; restam usos
-- genéricos (ex.: leitura de rbac_user_roles). Mantidos com a mesma
-- assinatura, mas sem role_level/hr_role: "tem algum módulo de RH" e
-- "gere algum módulo de RH".
CREATE OR REPLACE FUNCTION public.fn_rh_pode_algum(p_action text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.rbac_permissions p
    WHERE p.module LIKE 'rh\_%'
      AND p.action = p_action
      AND public.fn_rh_pode(p.module, p_action)
  );
$$;

REVOKE ALL ON FUNCTION public.fn_rh_pode_algum(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_rh_pode_algum(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_is_rh()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT public.fn_rh_pode_algum('view');
$$;

CREATE OR REPLACE FUNCTION public.fn_is_rh_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT public.fn_rh_pode_algum('manage');
$$;

-- Leitura dos perfis atribuídos: usava fn_is_rh() sem escopo de org. Com o
-- fn_is_rh() agora valendo para qualquer perfil com algum módulo de RH (ex.:
-- Gestor), fica restrita a quem gere funcionários ou administra — e à
-- própria organização.
DROP POLICY IF EXISTS "Leitura de user_roles" ON public.rbac_user_roles;
CREATE POLICY "Leitura de user_roles"
  ON public.rbac_user_roles FOR SELECT
  USING (
    user_id = auth.uid()
    OR (
      (public.fn_is_admin()
       OR (SELECT public.fn_rh_pode('rh_funcionarios', 'manage')))
      AND user_id IN (SELECT id FROM public.users
                      WHERE organization_id = public.fn_current_org())
    )
  );

-- ── 3. Tabelas com política criada em laço ───────────────────
-- Satélites do candidato: herdam o acesso via join com candidato.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['candidato_curriculo', 'candidato_formacao',
                           'candidato_experiencia', 'candidato_habilidade',
                           'candidato_historico']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS "RH acessa %1$s da própria org" ON public.%1$s', t);
    EXECUTE format($f$
      CREATE POLICY "RH acessa %1$s da própria org"
        ON public.%1$s FOR ALL
        USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND EXISTS (
          SELECT 1 FROM public.candidato c
          WHERE c.id = %1$s.candidato_id
            AND c.organization_id = public.fn_current_org()))
        WITH CHECK ((SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')) AND EXISTS (
          SELECT 1 FROM public.candidato c
          WHERE c.id = %1$s.candidato_id
            AND c.organization_id = public.fn_current_org()))
    $f$, t);
    EXECUTE format('DROP POLICY IF EXISTS "RH lê %1$s da própria org" ON public.%1$s', t);
    EXECUTE format($f$
      CREATE POLICY "RH lê %1$s da própria org"
        ON public.%1$s FOR SELECT
        USING ((SELECT public.fn_rh_pode('rh_banco_talentos', 'view')) AND EXISTS (
          SELECT 1 FROM public.candidato c
          WHERE c.id = %1$s.candidato_id
            AND c.organization_id = public.fn_current_org()))
    $f$, t);
  END LOOP;
END $$;

-- Onboarding e período de experiência.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'onboarding_template', 'onboarding_template_item',
    'onboarding_execucao', 'onboarding_item', 'periodo_experiencia'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS "RH gerencia %1$s" ON public.%1$s', t);
    EXECUTE format(
      'CREATE POLICY "RH gerencia %1$s" ON public.%1$s FOR ALL '
      'USING ((SELECT public.fn_rh_pode(''rh_onboarding'', ''manage'')) AND organization_id = public.fn_current_org()) '
      'WITH CHECK ((SELECT public.fn_rh_pode(''rh_onboarding'', ''manage'')) AND organization_id = public.fn_current_org())',
      t);
    EXECUTE format('DROP POLICY IF EXISTS "RH lê %1$s" ON public.%1$s', t);
    EXECUTE format(
      'CREATE POLICY "RH lê %1$s" ON public.%1$s FOR SELECT '
      'USING ((SELECT public.fn_rh_pode(''rh_onboarding'', ''view'')) AND organization_id = public.fn_current_org())',
      t);
  END LOOP;
END $$;

-- Catálogo (áreas, cargos, competências): a org inteira continua lendo
-- ("Org lê catálogo"); escreve quem gere funcionários OU vagas — o mesmo
-- catálogo alimenta os dois cadastros.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['rh_area', 'rh_cargo', 'rh_competencia',
                           'cargo_competencia'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS "RH gerencia catálogo" ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY "RH gerencia catálogo" ON public.%I FOR ALL '
      'USING (((SELECT public.fn_rh_pode(''rh_funcionarios'', ''manage'')) '
      '        OR (SELECT public.fn_rh_pode(''rh_banco_talentos'', ''manage''))) '
      '       AND organization_id = public.fn_current_org()) '
      'WITH CHECK (((SELECT public.fn_rh_pode(''rh_funcionarios'', ''manage'')) '
      '        OR (SELECT public.fn_rh_pode(''rh_banco_talentos'', ''manage''))) '
      '       AND organization_id = public.fn_current_org())',
      t);
  END LOOP;
END $$;

-- ── 4. Storage dos buckets de RH ─────────────────────────────
-- Holerites (rh-documentos/holerites/…) ficam no módulo de holerites; o
-- resto do rh-documentos (documentos, onboarding, anexos de candidato) nos
-- módulos que os usam. As políticas do próprio colaborador seguem intactas.
DROP POLICY IF EXISTS "RH acessa storage RH" ON storage.objects;

DROP POLICY IF EXISTS "RH lê storage RH" ON storage.objects;
CREATE POLICY "RH lê storage RH"
  ON storage.objects FOR SELECT
  USING (
    (bucket_id = 'rh-curriculos'
      AND (SELECT public.fn_rh_pode('rh_banco_talentos', 'view')))
    OR (bucket_id = 'rh-fotos'
      AND ((SELECT public.fn_rh_pode('rh_funcionarios', 'view'))
           OR (SELECT public.fn_rh_pode('rh_banco_talentos', 'view'))))
    OR (bucket_id = 'rh-documentos' AND name LIKE 'holerites/%'
      AND (SELECT public.fn_rh_pode('rh_holerites', 'view')))
    OR (bucket_id = 'rh-documentos' AND name NOT LIKE 'holerites/%'
      AND ((SELECT public.fn_rh_pode('rh_documentos', 'view'))
           OR (SELECT public.fn_rh_pode('rh_onboarding', 'view'))
           OR (SELECT public.fn_rh_pode('rh_funcionarios', 'view'))
           OR (SELECT public.fn_rh_pode('rh_banco_talentos', 'view'))))
  );

DROP POLICY IF EXISTS "RH gerencia storage RH" ON storage.objects;
CREATE POLICY "RH gerencia storage RH"
  ON storage.objects FOR ALL
  USING (
    (bucket_id = 'rh-curriculos'
      AND (SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')))
    OR (bucket_id = 'rh-fotos'
      AND ((SELECT public.fn_rh_pode('rh_funcionarios', 'manage'))
           OR (SELECT public.fn_rh_pode('rh_banco_talentos', 'manage'))))
    OR (bucket_id = 'rh-documentos' AND name LIKE 'holerites/%'
      AND (SELECT public.fn_rh_pode('rh_holerites', 'manage')))
    OR (bucket_id = 'rh-documentos' AND name NOT LIKE 'holerites/%'
      AND ((SELECT public.fn_rh_pode('rh_documentos', 'manage'))
           OR (SELECT public.fn_rh_pode('rh_onboarding', 'manage'))
           OR (SELECT public.fn_rh_pode('rh_funcionarios', 'manage'))
           OR (SELECT public.fn_rh_pode('rh_banco_talentos', 'manage'))))
  )
  WITH CHECK (
    (bucket_id = 'rh-curriculos'
      AND (SELECT public.fn_rh_pode('rh_banco_talentos', 'manage')))
    OR (bucket_id = 'rh-fotos'
      AND ((SELECT public.fn_rh_pode('rh_funcionarios', 'manage'))
           OR (SELECT public.fn_rh_pode('rh_banco_talentos', 'manage'))))
    OR (bucket_id = 'rh-documentos' AND name LIKE 'holerites/%'
      AND (SELECT public.fn_rh_pode('rh_holerites', 'manage')))
    OR (bucket_id = 'rh-documentos' AND name NOT LIKE 'holerites/%'
      AND ((SELECT public.fn_rh_pode('rh_documentos', 'manage'))
           OR (SELECT public.fn_rh_pode('rh_onboarding', 'manage'))
           OR (SELECT public.fn_rh_pode('rh_funcionarios', 'manage'))
           OR (SELECT public.fn_rh_pode('rh_banco_talentos', 'manage'))))
  );
