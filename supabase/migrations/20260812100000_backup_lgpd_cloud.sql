-- ============================================================
-- Backup em nuvem por conta e por dispositivo, cifrado no cliente
--
-- PROBLEMA
-- O módulo de backup era uma função só: `exportMessagesAsZip()` despejava
-- TODO o conteúdo de `local_messages` do Drift num ZIP em claro. Três
-- defeitos graves, nesta ordem:
--
--   1. VAZAMENTO DE TERCEIRO. O espelho local nunca era limpo no logout e
--      era alimentado por `syncRecentMessages()` com o que a RLS de CADA
--      usuário que já logou naquele aparelho permitiu. Num dispositivo
--      compartilhado, quem exportasse levava a conversa de quem veio antes.
--   2. SEM CIFRA. ZIP em texto claro no diretório de documentos — e, na
--      web, um data URI que fica no histórico de downloads do navegador.
--   3. SEM RASTRO. A 20260803180000_audit_log.sql cita "export de backup"
--      como exatamente o tipo de operação que precisava de registro. O
--      export nunca chamou fn_audit.
--
-- E não existia backup em nuvem nenhum: perder o aparelho era perder o
-- histórico local, sem alternativa.
--
-- DESENHO
-- Cifra ponta a ponta com chave que o servidor nunca vê:
--
--   DEK aleatório de 256 bits, por snapshot
--     └─ envelopado por KEK = PBKDF2-HMAC-SHA256(senha do titular, salt)
--   Servidor guarda: ciphertext + salt + nonce + DEK envelopado
--
-- Salt, nonce e DEK envelopado não são segredos — sem a senha, o envelope
-- não abre. O servidor armazena bytes opacos: nem o admin, nem o operador
-- do banco, nem quem obtiver um dump do Storage lê o conteúdo.
--
-- POR QUE O ADMIN NÃO DECIFRA
-- Deliberado. Já existe caminho legítimo para a empresa acessar conteúdo
-- corporativo: `admin_search_messages` (20260803200000), que exige
-- justificativa por escrito e registra cada consulta. Dar ao admin uma
-- segunda via — silenciosa, pelo backup — destruiria essa garantia. O
-- admin aqui vê metadados (quem, quando, qual dispositivo, quantos bytes)
-- e a auditoria; nunca o conteúdo.
--
-- Contrapartida assumida: senha perdida é backup irrecuperável. É o preço
-- do Art. 46 e está dito na UI antes de a senha ser definida.
-- ============================================================

-- MULTI-TENANT
-- A org de cada dispositivo e snapshot vem de fn_current_org(), não da
-- linha do usuário: o dono da plataforma em "empresa em atuação" carimba
-- o registro na empresa visitada, que é onde o ato aconteceu e onde o
-- admin dela precisa enxergá-lo na auditoria.
-- ============================================================

-- ── 1. Parâmetros de retenção por organização ────────────────
-- Mesmo padrão de fn_org_gps_retencao_dias: default sensato, ajustável
-- pelo admin da própria org, com teto rígido no código.
CREATE OR REPLACE FUNCTION public.fn_org_backup_retencao_dias(p_org uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE(NULLIF(settings->>'backup_retencao_dias', '')::int, 90)
    FROM public.organizations WHERE id = p_org;
$$;

CREATE OR REPLACE FUNCTION public.fn_org_backup_max_por_dispositivo(p_org uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE(NULLIF(settings->>'backup_max_por_dispositivo', '')::int, 5)
    FROM public.organizations WHERE id = p_org;
$$;

CREATE OR REPLACE FUNCTION public.fn_org_backup_teto_mb(p_org uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE(NULLIF(settings->>'backup_teto_mb', '')::int, 200)
    FROM public.organizations WHERE id = p_org;
$$;

REVOKE ALL ON FUNCTION public.fn_org_backup_retencao_dias(uuid)       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_org_backup_max_por_dispositivo(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_org_backup_teto_mb(uuid)             FROM PUBLIC, anon;

-- ── 2. Dispositivos que fazem backup ─────────────────────────
-- Separado de `user_trusted_devices` (2FA) de propósito: aquele expira em
-- 30 dias e some, este precisa sobreviver para o titular reconhecer de
-- qual aparelho veio cada snapshot meses depois.
CREATE TABLE IF NOT EXISTS public.backup_devices (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  organization_id UUID REFERENCES public.organizations(id),
  fingerprint     TEXT NOT NULL,
  device_name     TEXT NOT NULL DEFAULT 'Dispositivo',
  platform        TEXT NOT NULL DEFAULT 'desconhecida',
  auto_backup     BOOLEAN NOT NULL DEFAULT false,
  first_seen_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_backup_at  TIMESTAMPTZ,
  revoked_at      TIMESTAMPTZ,
  CONSTRAINT uq_backup_device UNIQUE (user_id, fingerprint)
);

CREATE INDEX IF NOT EXISTS idx_backup_devices_user
  ON public.backup_devices(user_id, last_seen_at DESC);

COMMENT ON TABLE public.backup_devices IS
  'Aparelhos habilitados a gerar backup. O titular vê e revoga os próprios; admin só vê contagem agregada.';

ALTER TABLE public.backup_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Titular lê os próprios dispositivos" ON public.backup_devices;
CREATE POLICY "Titular lê os próprios dispositivos"
  ON public.backup_devices FOR SELECT USING (user_id = auth.uid());

-- Escrita só por RPC: fingerprint e vínculo de org não podem ser forjados.
REVOKE INSERT, UPDATE, DELETE ON public.backup_devices FROM authenticated, anon;

-- ── 3. Snapshots ─────────────────────────────────────────────
-- Guarda só metadado e material público do envelope. `wrapped_dek`,
-- `kdf_salt` e `nonce` são inúteis sem a senha — por isso podem viver no
-- banco sem cifra adicional.
CREATE TABLE IF NOT EXISTS public.backup_snapshots (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  organization_id   UUID REFERENCES public.organizations(id),
  device_id         UUID REFERENCES public.backup_devices(id) ON DELETE SET NULL,
  escopo            TEXT NOT NULL CHECK (escopo IN ('conta', 'dispositivo')),
  origem            TEXT NOT NULL DEFAULT 'manual'
                      CHECK (origem IN ('manual', 'automatico')),
  status            TEXT NOT NULL DEFAULT 'pendente'
                      CHECK (status IN ('pendente', 'concluido', 'falhou')),
  storage_path      TEXT NOT NULL UNIQUE,
  size_bytes        BIGINT NOT NULL DEFAULT 0 CHECK (size_bytes >= 0),
  sha256            TEXT,
  formato_versao    INT  NOT NULL DEFAULT 1,
  cipher_alg        TEXT NOT NULL DEFAULT 'AES-256-GCM',
  kdf               TEXT NOT NULL DEFAULT 'PBKDF2-HMAC-SHA256',
  kdf_iteracoes     INT  NOT NULL DEFAULT 210000,
  kdf_salt          TEXT,
  nonce             TEXT,
  wrapped_dek       TEXT,
  conteudo          JSONB NOT NULL DEFAULT '{}',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  concluido_em      TIMESTAMPTZ,
  ultimo_restore_em TIMESTAMPTZ,
  expires_at        TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_backup_snapshots_user
  ON public.backup_snapshots(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_backup_snapshots_device
  ON public.backup_snapshots(device_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_backup_snapshots_expira
  ON public.backup_snapshots(expires_at) WHERE status = 'concluido';

COMMENT ON TABLE public.backup_snapshots IS
  'Metadados de backup cifrado no cliente. O servidor NÃO possui a chave: wrapped_dek só abre com a senha do titular.';
COMMENT ON COLUMN public.backup_snapshots.wrapped_dek IS
  'DEK do snapshot cifrado pela KEK derivada da senha do titular. Sem a senha, não decifra.';

ALTER TABLE public.backup_snapshots ENABLE ROW LEVEL SECURITY;

-- Só o dono lê. Não há policy de admin: backup é da pessoa, e o acesso
-- corporativo a conteúdo passa por admin_search_messages, que audita.
DROP POLICY IF EXISTS "Titular lê os próprios snapshots" ON public.backup_snapshots;
CREATE POLICY "Titular lê os próprios snapshots"
  ON public.backup_snapshots FOR SELECT USING (user_id = auth.uid());

REVOKE INSERT, UPDATE, DELETE ON public.backup_snapshots FROM authenticated, anon;

-- ── 4. Bucket privado ────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('backups', 'backups', false, 268435456,  -- 256 MB por objeto
        ARRAY['application/octet-stream'])
ON CONFLICT (id) DO UPDATE SET
  public             = EXCLUDED.public,
  file_size_limit    = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Convenção de path: {user_id}/{snapshot_id}.fxb — gerado no servidor, o
-- cliente nunca escolhe o nome. A primeira pasta ser o uid é o que faz a
-- policy funcionar sem consultar tabela.
DROP POLICY IF EXISTS "Titular lê o próprio backup" ON storage.objects;
CREATE POLICY "Titular lê o próprio backup"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'backups'
         AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Titular envia o próprio backup" ON storage.objects;
CREATE POLICY "Titular envia o próprio backup"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'backups'
              AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Titular apaga o próprio backup" ON storage.objects;
CREATE POLICY "Titular apaga o próprio backup"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'backups'
         AND (storage.foldername(name))[1] = auth.uid()::text);

-- Sem policy de UPDATE: snapshot é imutável. Corrigir = criar outro.

-- ── 5. Registro do dispositivo ───────────────────────────────
CREATE OR REPLACE FUNCTION public.backup_register_device(
  p_fingerprint text,
  p_name        text DEFAULT 'Dispositivo',
  p_platform    text DEFAULT 'desconhecida'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_id  uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Sessão inválida'; END IF;
  IF COALESCE(TRIM(p_fingerprint), '') = '' THEN
    RAISE EXCEPTION 'Identificação do dispositivo ausente';
  END IF;

  v_org := public.fn_current_org();

  INSERT INTO public.backup_devices
    (user_id, organization_id, fingerprint, device_name, platform)
  VALUES (v_uid, v_org, p_fingerprint,
          COALESCE(NULLIF(TRIM(p_name), ''), 'Dispositivo'),
          COALESCE(NULLIF(TRIM(p_platform), ''), 'desconhecida'))
  ON CONFLICT (user_id, fingerprint) DO UPDATE
    SET device_name  = EXCLUDED.device_name,
        platform     = EXCLUDED.platform,
        last_seen_at = NOW(),
        revoked_at   = NULL
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.backup_register_device(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.backup_register_device(text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.backup_set_auto(p_device_id uuid, p_ativo boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  UPDATE public.backup_devices
     SET auto_backup = COALESCE(p_ativo, false), last_seen_at = NOW()
   WHERE id = p_device_id AND user_id = auth.uid();

  IF NOT FOUND THEN RAISE EXCEPTION 'Dispositivo não encontrado'; END IF;

  PERFORM public.fn_audit(
    CASE WHEN p_ativo THEN 'backup.auto_enabled' ELSE 'backup.auto_disabled' END,
    'backup_device', p_device_id::text, '{}');
END;
$$;
REVOKE ALL ON FUNCTION public.backup_set_auto(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.backup_set_auto(uuid, boolean) TO authenticated;

-- ── 6. Remoção física do objeto ──────────────────────────────
-- Mesmo mecanismo de mark_view_once_opened: apagar a linha de
-- storage.objects já torna o arquivo inacessível pela Storage API. O
-- cliente ainda chama storage.remove() para o purge físico.
CREATE OR REPLACE FUNCTION public.fn_backup_drop_object(p_path text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_path IS NULL OR p_path = '' THEN RETURN; END IF;
  DELETE FROM storage.objects WHERE bucket_id = 'backups' AND name = p_path;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_backup_drop_object(text) FROM PUBLIC, anon, authenticated;

-- ── 7. Abertura do snapshot (quota + limite de taxa) ─────────
CREATE OR REPLACE FUNCTION public.backup_prepare(
  p_device_id uuid,
  p_escopo    text DEFAULT 'conta',
  p_origem    text DEFAULT 'manual'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_org     uuid;
  v_id      uuid := gen_random_uuid();
  v_recente int;
  v_dias    int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Sessão inválida'; END IF;

  IF p_escopo NOT IN ('conta', 'dispositivo') THEN
    RAISE EXCEPTION 'Escopo inválido: %', p_escopo;
  END IF;
  IF p_origem NOT IN ('manual', 'automatico') THEN
    RAISE EXCEPTION 'Origem inválida: %', p_origem;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.backup_devices
                  WHERE id = p_device_id AND user_id = v_uid
                    AND revoked_at IS NULL) THEN
    RAISE EXCEPTION 'Dispositivo não registrado ou revogado';
  END IF;

  -- Limite de taxa: 6 snapshots por hora. Barra tanto laço acidental do
  -- app quanto uso do backup como canal de exfiltração em volume.
  SELECT COUNT(*) INTO v_recente
    FROM public.backup_snapshots
   WHERE user_id = v_uid AND created_at > NOW() - INTERVAL '1 hour';

  IF v_recente >= 6 THEN
    RAISE EXCEPTION 'Limite de backups por hora atingido. Tente novamente mais tarde.';
  END IF;

  v_org := public.fn_current_org();
  v_dias := public.fn_org_backup_retencao_dias(v_org);

  INSERT INTO public.backup_snapshots
    (id, user_id, organization_id, device_id, escopo, origem,
     storage_path, expires_at)
  VALUES (v_id, v_uid, v_org, p_device_id, p_escopo, p_origem,
          v_uid::text || '/' || v_id::text || '.fxb',
          NOW() + (v_dias || ' days')::interval);

  RETURN jsonb_build_object(
    'snapshot_id',   v_id,
    'storage_path',  v_uid::text || '/' || v_id::text || '.fxb',
    'kdf_iteracoes', 210000,
    'teto_mb',       public.fn_org_backup_teto_mb(v_org),
    'expira_em',     NOW() + (v_dias || ' days')::interval
  );
END;
$$;
REVOKE ALL ON FUNCTION public.backup_prepare(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.backup_prepare(uuid, text, text) TO authenticated;

-- ── 8. Confirmação e poda por quota ──────────────────────────
CREATE OR REPLACE FUNCTION public.backup_commit(
  p_snapshot_id uuid,
  p_size_bytes  bigint,
  p_sha256      text,
  p_kdf_salt    text,
  p_nonce       text,
  p_wrapped_dek text,
  p_conteudo    jsonb DEFAULT '{}'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_snap   public.backup_snapshots%ROWTYPE;
  v_max    int;
  v_paths  text[] := ARRAY[]::text[];
  r        record;
BEGIN
  SELECT * INTO v_snap FROM public.backup_snapshots
   WHERE id = p_snapshot_id AND user_id = v_uid;

  IF NOT FOUND THEN RAISE EXCEPTION 'Backup não encontrado'; END IF;
  IF v_snap.status <> 'pendente' THEN
    RAISE EXCEPTION 'Backup já finalizado';
  END IF;

  IF COALESCE(TRIM(p_kdf_salt), '') = ''
     OR COALESCE(TRIM(p_nonce), '') = ''
     OR COALESCE(TRIM(p_wrapped_dek), '') = ''
     OR COALESCE(TRIM(p_sha256), '') = '' THEN
    -- Sem envelope completo o arquivo é indecifrável: melhor recusar do
    -- que oferecer ao titular um backup que nunca vai restaurar.
    RAISE EXCEPTION 'Envelope criptográfico incompleto';
  END IF;

  UPDATE public.backup_snapshots
     SET status       = 'concluido',
         size_bytes   = GREATEST(COALESCE(p_size_bytes, 0), 0),
         sha256       = p_sha256,
         kdf_salt     = p_kdf_salt,
         nonce        = p_nonce,
         wrapped_dek  = p_wrapped_dek,
         conteudo     = COALESCE(p_conteudo, '{}'::jsonb),
         concluido_em = NOW()
   WHERE id = p_snapshot_id;

  UPDATE public.backup_devices
     SET last_backup_at = NOW(), last_seen_at = NOW()
   WHERE id = v_snap.device_id;

  -- Poda: mantém os N mais recentes do dispositivo (art. 15 — não guardar
  -- além do necessário) e devolve os paths para o cliente purgar.
  v_max := public.fn_org_backup_max_por_dispositivo(v_snap.organization_id);

  FOR r IN
    SELECT id, storage_path FROM public.backup_snapshots
     WHERE user_id = v_uid AND device_id = v_snap.device_id
       AND escopo = v_snap.escopo
       -- Só concluídos entram na contagem: um 'pendente' é upload em
       -- andamento, e podá-lo destruiria o backup que está sendo feito.
       AND status = 'concluido'
     ORDER BY created_at DESC OFFSET GREATEST(v_max, 1)
  LOOP
    PERFORM public.fn_backup_drop_object(r.storage_path);
    DELETE FROM public.backup_snapshots WHERE id = r.id;
    v_paths := v_paths || r.storage_path;
  END LOOP;

  PERFORM public.fn_audit('backup.created', 'backup_snapshot', p_snapshot_id::text,
    jsonb_build_object('escopo', v_snap.escopo, 'origem', v_snap.origem,
                       'bytes', p_size_bytes, 'dispositivo', v_snap.device_id,
                       'conteudo', COALESCE(p_conteudo, '{}'::jsonb),
                       'podados', COALESCE(array_length(v_paths, 1), 0)));

  RETURN jsonb_build_object('podados', to_jsonb(v_paths));
END;
$$;
REVOKE ALL ON FUNCTION public.backup_commit(uuid, bigint, text, text, text, text, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.backup_commit(uuid, bigint, text, text, text, text, jsonb)
  TO authenticated;

-- ── 9. Restauração e exclusão ────────────────────────────────
-- Baixar um backup é acesso a dado pessoal em volume: registra-se sempre,
-- ainda que o titular esteja acessando o que é dele.
CREATE OR REPLACE FUNCTION public.backup_mark_restored(p_snapshot_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_dev uuid;
BEGIN
  UPDATE public.backup_snapshots
     SET ultimo_restore_em = NOW()
   WHERE id = p_snapshot_id AND user_id = auth.uid() AND status = 'concluido'
  RETURNING device_id INTO v_dev;

  IF NOT FOUND THEN RAISE EXCEPTION 'Backup não encontrado'; END IF;

  PERFORM public.fn_audit('backup.restored', 'backup_snapshot', p_snapshot_id::text,
    jsonb_build_object('dispositivo_origem', v_dev));
END;
$$;
REVOKE ALL ON FUNCTION public.backup_mark_restored(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.backup_mark_restored(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.backup_delete(p_snapshot_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_path text;
BEGIN
  SELECT storage_path INTO v_path FROM public.backup_snapshots
   WHERE id = p_snapshot_id AND user_id = auth.uid();

  IF v_path IS NULL THEN RAISE EXCEPTION 'Backup não encontrado'; END IF;

  PERFORM public.fn_backup_drop_object(v_path);
  DELETE FROM public.backup_snapshots WHERE id = p_snapshot_id;

  PERFORM public.fn_audit('backup.deleted', 'backup_snapshot', p_snapshot_id::text, '{}');
  RETURN v_path;
END;
$$;
REVOKE ALL ON FUNCTION public.backup_delete(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.backup_delete(uuid) TO authenticated;

-- Perdeu o aparelho: revogar apaga tudo o que veio dele, de uma vez.
CREATE OR REPLACE FUNCTION public.backup_revoke_device(p_device_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_paths text[] := ARRAY[]::text[];
  r       record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.backup_devices
                  WHERE id = p_device_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Dispositivo não encontrado';
  END IF;

  FOR r IN SELECT id, storage_path FROM public.backup_snapshots
            WHERE device_id = p_device_id AND user_id = auth.uid()
  LOOP
    PERFORM public.fn_backup_drop_object(r.storage_path);
    DELETE FROM public.backup_snapshots WHERE id = r.id;
    v_paths := v_paths || r.storage_path;
  END LOOP;

  UPDATE public.backup_devices
     SET revoked_at = NOW(), auto_backup = false
   WHERE id = p_device_id AND user_id = auth.uid();

  PERFORM public.fn_audit('backup.device_revoked', 'backup_device', p_device_id::text,
    jsonb_build_object('snapshots_removidos', COALESCE(array_length(v_paths, 1), 0)));

  RETURN jsonb_build_object('removidos', to_jsonb(v_paths));
END;
$$;
REVOKE ALL ON FUNCTION public.backup_revoke_device(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.backup_revoke_device(uuid) TO authenticated;

-- ── 10. Expurgo automático ───────────────────────────────────
-- Prazo declarado sem rotina que o cumpra é agravante em fiscalização.
-- Esta é a rotina; o volume expurgado vira evidência no audit_log.
CREATE OR REPLACE FUNCTION public.backup_purge_expired()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_total   int := 0;
  v_por_org jsonb := '{}';
  v_chave   text;
  r         record;
BEGIN
  -- Uma passada só: apaga e vai acumulando a contagem por organização.
  FOR r IN
    SELECT id, storage_path, organization_id
      FROM public.backup_snapshots
     WHERE expires_at <= NOW()
        -- Snapshot que ficou 'pendente' é upload interrompido: lixo com
        -- dado pessoal dentro. Some em 24h.
        OR (status = 'pendente' AND created_at < NOW() - INTERVAL '24 hours')
  LOOP
    PERFORM public.fn_backup_drop_object(r.storage_path);
    DELETE FROM public.backup_snapshots WHERE id = r.id;

    v_chave := COALESCE(r.organization_id::text, 'sem_org');
    v_por_org := jsonb_set(
      v_por_org, ARRAY[v_chave],
      to_jsonb(COALESCE((v_por_org->>v_chave)::int, 0) + 1));
    v_total := v_total + 1;
  END LOOP;

  -- A evidência precisa ser legível por quem responde pela organização: a
  -- policy do audit_log filtra por organization_id, e fn_audit derivaria o
  -- org do ator — que aqui é o cron, sem sessão. Daí o INSERT direto.
  FOR v_chave IN SELECT jsonb_object_keys(v_por_org)
  LOOP
    INSERT INTO public.audit_log
      (organization_id, actor_id, action, target_type, target_id, details)
    VALUES (
      CASE WHEN v_chave = 'sem_org' THEN NULL ELSE v_chave::uuid END,
      NULL, 'backup.purged', 'backup_snapshot', NULL,
      jsonb_build_object('removidos', (v_por_org->>v_chave)::int,
                         'executado_em', NOW(),
                         'origem', 'rotina_diaria'));
  END LOOP;

  RETURN v_total;
END;
$$;
REVOKE ALL ON FUNCTION public.backup_purge_expired() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('backup-purga-diaria')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'backup-purga-diaria');
    PERFORM cron.schedule('backup-purga-diaria', '40 3 * * *',
      $cron$SELECT public.backup_purge_expired();$cron$);
  ELSE
    RAISE NOTICE 'pg_cron não habilitado: agende backup-purga-diaria manualmente.';
  END IF;
END $$;

-- ── 11. Governança do admin: metadado, nunca conteúdo ────────
CREATE OR REPLACE FUNCTION public.set_retencao_backup(
  p_dias              int,
  p_max_por_dispositivo int DEFAULT NULL,
  p_teto_mb           int DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid;
  v_set jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.users u
     WHERE u.id = auth.uid()
       AND u.role_level IN ('super_admin', 'admin')
       AND u.is_active
  ) THEN
    RAISE EXCEPTION 'Apenas administradores podem alterar a política de backup';
  END IF;

  v_org := public.fn_current_org();

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Organização do usuário não resolvida';
  END IF;

  IF p_dias IS NULL OR p_dias < 7 OR p_dias > 365 THEN
    RAISE EXCEPTION 'Retenção inválida (use de 7 a 365 dias)';
  END IF;
  IF p_max_por_dispositivo IS NOT NULL
     AND (p_max_por_dispositivo < 1 OR p_max_por_dispositivo > 30) THEN
    RAISE EXCEPTION 'Limite por dispositivo inválido (use de 1 a 30)';
  END IF;
  IF p_teto_mb IS NOT NULL AND (p_teto_mb < 10 OR p_teto_mb > 256) THEN
    RAISE EXCEPTION 'Teto inválido (use de 10 a 256 MB)';
  END IF;

  SELECT COALESCE(settings, '{}'::jsonb) INTO v_set
    FROM public.organizations WHERE id = v_org;

  v_set := jsonb_set(v_set, '{backup_retencao_dias}', to_jsonb(p_dias));
  IF p_max_por_dispositivo IS NOT NULL THEN
    v_set := jsonb_set(v_set, '{backup_max_por_dispositivo}',
                       to_jsonb(p_max_por_dispositivo));
  END IF;
  IF p_teto_mb IS NOT NULL THEN
    v_set := jsonb_set(v_set, '{backup_teto_mb}', to_jsonb(p_teto_mb));
  END IF;

  UPDATE public.organizations
     SET settings = v_set, updated_at = NOW() WHERE id = v_org;

  PERFORM public.fn_audit('backup.policy_changed', 'organization', v_org::text,
    jsonb_build_object('dias', p_dias, 'max_dispositivo', p_max_por_dispositivo,
                       'teto_mb', p_teto_mb));
END;
$$;
REVOKE ALL ON FUNCTION public.set_retencao_backup(int, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_retencao_backup(int, int, int) TO authenticated;

-- Painel do admin. Devolve cobertura e volume — quem tem backup, de
-- quantos aparelhos, há quanto tempo. Nenhuma coluna de path, salt,
-- nonce ou envelope: nada aqui aproxima o admin do conteúdo.
CREATE OR REPLACE FUNCTION public.admin_backup_overview()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.users u
     WHERE u.id = auth.uid()
       AND u.role_level IN ('super_admin', 'admin')
       AND u.is_active
  ) THEN
    RAISE EXCEPTION 'Acesso restrito a administradores';
  END IF;

  v_org := public.fn_current_org();

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Organização do usuário não resolvida';
  END IF;

  RETURN jsonb_build_object(
    'politica', jsonb_build_object(
      'retencao_dias',    public.fn_org_backup_retencao_dias(v_org),
      'max_dispositivo',  public.fn_org_backup_max_por_dispositivo(v_org),
      'teto_mb',          public.fn_org_backup_teto_mb(v_org)),
    'totais', (
      SELECT jsonb_build_object(
               'snapshots',        COUNT(*),
               'bytes',            COALESCE(SUM(size_bytes), 0),
               'titulares',        COUNT(DISTINCT user_id),
               'auto_ativo',       (SELECT COUNT(*) FROM public.backup_devices d
                                     WHERE d.organization_id = v_org
                                       AND d.auto_backup AND d.revoked_at IS NULL))
        FROM public.backup_snapshots
       WHERE organization_id = v_org AND status = 'concluido'),
    'por_titular', (
      SELECT COALESCE(jsonb_agg(t ORDER BY t->>'ultimo_backup' DESC NULLS LAST), '[]'::jsonb)
        FROM (
          SELECT jsonb_build_object(
                   'usuario',        u.full_name,
                   'dispositivos',   COUNT(DISTINCT s.device_id),
                   'snapshots',      COUNT(s.id),
                   'bytes',          COALESCE(SUM(s.size_bytes), 0),
                   'ultimo_backup',  MAX(s.concluido_em)) AS t
            FROM public.backup_snapshots s
            JOIN public.users u ON u.id = s.user_id
           WHERE s.organization_id = v_org AND s.status = 'concluido'
           GROUP BY u.id, u.full_name
        ) sub)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_backup_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_backup_overview() TO authenticated;
