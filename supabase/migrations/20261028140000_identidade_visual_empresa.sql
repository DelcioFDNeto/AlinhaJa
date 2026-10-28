-- ============================================================
-- Identidade visual por empresa (white-label, Fase 2)
--
-- O AlinhaJá é white-label: dentro de uma mesma implantação, cada
-- empresa usa o próprio logo e as próprias cores. Até aqui a cor vinha de
-- uma constante de build (AppConstants.primary) e o logo era o do produto.
--
-- O QUE ENTRA
--   • organizations.cor_primaria / cor_secundaria — hex #RRGGBB, opcionais
--     (nulo = cores da marca do produto). `logo_url` já existia.
--   • get_org_identity()        — leitura da empresa em atuação, para o tema.
--   • admin_set_org_identity()  — gravação por admin da empresa, auditada.
--   • bucket `org-logos`        — logo público (não é dado sensível), escrita
--                                 só por admin, na pasta da própria empresa.
-- ============================================================

-- ── 1. Colunas ───────────────────────────────────────────────
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS cor_primaria   TEXT,
  ADD COLUMN IF NOT EXISTS cor_secundaria TEXT;

ALTER TABLE public.organizations
  DROP CONSTRAINT IF EXISTS organizations_cor_primaria_hex,
  DROP CONSTRAINT IF EXISTS organizations_cor_secundaria_hex;
ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_cor_primaria_hex
    CHECK (cor_primaria IS NULL OR cor_primaria ~ '^#[0-9A-F]{6}$'),
  ADD CONSTRAINT organizations_cor_secundaria_hex
    CHECK (cor_secundaria IS NULL OR cor_secundaria ~ '^#[0-9A-F]{6}$');

COMMENT ON COLUMN public.organizations.cor_primaria IS
  'Cor principal da empresa no app (#RRGGBB, maiúsculas). Nulo = cor da marca.';
COMMENT ON COLUMN public.organizations.cor_secundaria IS
  'Cor de destaque secundária (#RRGGBB, maiúsculas). Nulo = neutra.';

-- ── 2. Quem pode alterar a identidade ────────────────────────
-- Mesmo critério dos dados legais: admin ativo, sobre a empresa em atuação
-- (fn_current_org acompanha o dono da plataforma quando ele atua por outra).
CREATE OR REPLACE FUNCTION public.fn_pode_editar_identidade()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL
     AND public.fn_current_org() IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role_level IN ('super_admin', 'admin')
          AND u.is_active);
$$;

REVOKE ALL ON FUNCTION public.fn_pode_editar_identidade() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_pode_editar_identidade() TO authenticated;

-- ── 3. Leitura ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_org_identity()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid := public.fn_current_org();
  v_row record;
BEGIN
  IF v_org IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT o.name, o.logo_url, o.cor_primaria, o.cor_secundaria
    INTO v_row
    FROM public.organizations o
   WHERE o.id = v_org;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'organization_id', v_org,
    'nome',            v_row.name,
    'logo_url',        v_row.logo_url,
    'cor_primaria',    v_row.cor_primaria,
    'cor_secundaria',  v_row.cor_secundaria);
END;
$$;

REVOKE ALL ON FUNCTION public.get_org_identity() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_org_identity() TO authenticated;

-- ── 4. Gravação ──────────────────────────────────────────────
-- Recebe o estado completo do formulário: nulo ou vazio apaga o campo
-- (volta para o padrão da marca).
CREATE OR REPLACE FUNCTION public.admin_set_org_identity(
  p_logo_url       text,
  p_cor_primaria   text,
  p_cor_secundaria text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org   uuid := public.fn_current_org();
  v_logo  text := NULLIF(trim(p_logo_url), '');
  v_pri   text := upper(NULLIF(trim(p_cor_primaria), ''));
  v_sec   text := upper(NULLIF(trim(p_cor_secundaria), ''));
  v_antes record;
BEGIN
  IF NOT public.fn_pode_editar_identidade() THEN
    RAISE EXCEPTION 'Apenas administradores podem alterar a identidade visual';
  END IF;

  IF v_pri IS NOT NULL AND v_pri !~ '^#[0-9A-F]{6}$' THEN
    RAISE EXCEPTION 'Cor primária inválida: use o formato #RRGGBB';
  END IF;
  IF v_sec IS NOT NULL AND v_sec !~ '^#[0-9A-F]{6}$' THEN
    RAISE EXCEPTION 'Cor secundária inválida: use o formato #RRGGBB';
  END IF;
  IF v_logo IS NOT NULL AND v_logo !~ '^https?://' THEN
    RAISE EXCEPTION 'Endereço do logo inválido';
  END IF;

  SELECT o.logo_url, o.cor_primaria, o.cor_secundaria
    INTO v_antes
    FROM public.organizations o
   WHERE o.id = v_org;

  UPDATE public.organizations
     SET logo_url       = v_logo,
         cor_primaria   = v_pri,
         cor_secundaria = v_sec,
         updated_at     = NOW()
   WHERE id = v_org;

  PERFORM public.fn_audit(
    'org.identity_changed', 'organization', v_org::text,
    jsonb_build_object(
      'logo',           v_antes.logo_url IS DISTINCT FROM v_logo,
      'cor_primaria',   jsonb_build_array(v_antes.cor_primaria, v_pri),
      'cor_secundaria', jsonb_build_array(v_antes.cor_secundaria, v_sec)));

  RETURN public.get_org_identity();
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_org_identity(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_org_identity(text, text, text) TO authenticated;

-- ── 5. Armazenamento do logo ─────────────────────────────────
-- Público como os avatares: o logo aparece antes do login e em e-mails.
-- SVG fica de fora (pode carregar script). Convenção: {org_id}/logo_{ts}.ext
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('org-logos', 'org-logos', true, 2097152,
        ARRAY['image/png', 'image/jpeg', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET
  public             = EXCLUDED.public,
  file_size_limit    = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Leitura pública de logos de empresa" ON storage.objects;
CREATE POLICY "Leitura pública de logos de empresa"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'org-logos');

DROP POLICY IF EXISTS "Admin envia logo da própria empresa" ON storage.objects;
CREATE POLICY "Admin envia logo da própria empresa"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'org-logos'
    AND (storage.foldername(name))[1] = public.fn_current_org()::text
    AND public.fn_pode_editar_identidade());

DROP POLICY IF EXISTS "Admin atualiza logo da própria empresa" ON storage.objects;
CREATE POLICY "Admin atualiza logo da própria empresa"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'org-logos'
    AND (storage.foldername(name))[1] = public.fn_current_org()::text
    AND public.fn_pode_editar_identidade());

DROP POLICY IF EXISTS "Admin remove logo da própria empresa" ON storage.objects;
CREATE POLICY "Admin remove logo da própria empresa"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'org-logos'
    AND (storage.foldername(name))[1] = public.fn_current_org()::text
    AND public.fn_pode_editar_identidade());

-- ── 6. Permissão RBAC da aba "Identidade Visual" ─────────────
-- Super Admin recebe a aba; os demais perfis só quando atribuída. A gravação
-- continua exigindo admin (fn_pode_editar_identidade), mesmo com a aba visível.
INSERT INTO public.rbac_permissions (module, action, description) VALUES
  ('admin_identidade', 'view', 'Pode acessar a Identidade Visual da empresa (logo e cores)')
ON CONFLICT (module, action) DO NOTHING;

DO $$
DECLARE
  r record;
  v_perm uuid;
BEGIN
  SELECT id INTO v_perm FROM public.rbac_permissions
   WHERE module = 'admin_identidade' AND action = 'view';

  IF v_perm IS NULL THEN RETURN; END IF;

  FOR r IN SELECT id FROM public.rbac_roles WHERE name = 'Super Admin' LOOP
    INSERT INTO public.rbac_role_permissions (role_id, permission_id)
    VALUES (r.id, v_perm)
    ON CONFLICT DO NOTHING;
  END LOOP;
END $$;
