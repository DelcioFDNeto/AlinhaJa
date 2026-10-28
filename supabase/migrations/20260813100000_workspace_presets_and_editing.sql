-- ============================================================================
-- Workspaces maleáveis: presets editáveis + edição completa pós-criação
-- ============================================================================
-- Antes desta migration:
--   * Os "tipos de workflow" viviam hardcoded no Flutter (channel_create_screen).
--   * Um workspace criado só podia ter nome/descrição alterados
--     (`update_channel_info`); categoria, ícone, cor e principalmente as
--     ETAPAS do Kanban ficavam congeladas para sempre.
--   * "Cancelado" era detectado por comparação de string no cliente, então
--     qualquer preset com nome diferente quebrava o fluxo de cancelamento.
--
-- Esta migration entrega:
--   1. Flags semânticas em workflow_status_config (is_initial / is_cancelled).
--   2. Tabela public.workspace_presets (CRUD de presets pelo usuário).
--   3. RPCs upsert/delete de preset + seed dos 6 presets de sistema.
--   4. RPC update_workspace: edição completa, incluindo sincronização das
--      etapas com migração segura dos cards existentes.
--   5. create_workspace passa a aceitar p_preset_id e as novas flags.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Flags semânticas nas etapas do workflow
-- ----------------------------------------------------------------------------

ALTER TABLE public.workflow_status_config
  ADD COLUMN IF NOT EXISTS is_initial   BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_cancelled BOOLEAN NOT NULL DEFAULT FALSE;

-- Backfill do cancelamento a partir da heurística que o cliente usava.
UPDATE public.workflow_status_config
SET is_cancelled = TRUE
WHERE is_cancelled = FALSE
  AND LOWER(TRIM(status)) IN ('cancelado', 'cancelada', 'cancelled', 'canceled');

-- Backfill da etapa inicial: menor status_order entre as não canceladas.
WITH firsts AS (
  SELECT DISTINCT ON (channel_id) id
  FROM public.workflow_status_config
  WHERE is_cancelled = FALSE
  ORDER BY channel_id, status_order ASC, status ASC
)
UPDATE public.workflow_status_config s
SET is_initial = TRUE
FROM firsts f
WHERE f.id = s.id
  AND s.is_initial = FALSE;

CREATE INDEX IF NOT EXISTS idx_wfs_config_channel_order
  ON public.workflow_status_config(channel_id, status_order);

-- ----------------------------------------------------------------------------
-- 2. Tabela de presets de workspace
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.workspace_presets (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT NOT NULL,
  description       TEXT,
  category          TEXT NOT NULL DEFAULT 'operacional',
  icon              TEXT NOT NULL DEFAULT 'workspaces_rounded',
  color             TEXT NOT NULL DEFAULT '#616161',
  card_type         TEXT NOT NULL DEFAULT 'generic',
  workflow_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
  assignment_mode   TEXT NOT NULL DEFAULT 'operator_pool',
  posting_permission TEXT NOT NULL DEFAULT 'everyone',
  status_config     JSONB NOT NULL DEFAULT '[]'::JSONB,
  -- Presets de sistema são somente leitura: a UI oferece "Duplicar".
  is_system         BOOLEAN NOT NULL DEFAULT FALSE,
  -- Preset privado (só o dono vê) x compartilhado com a empresa.
  is_shared         BOOLEAN NOT NULL DEFAULT TRUE,
  created_by        UUID REFERENCES public.users(id) ON DELETE SET NULL,
  usage_count       INTEGER NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT workspace_presets_name_not_blank CHECK (LENGTH(TRIM(name)) > 0),
  CONSTRAINT workspace_presets_assignment_mode_check
    CHECK (assignment_mode IN ('single_operator', 'operator_pool', 'manual')),
  CONSTRAINT workspace_presets_posting_permission_check
    CHECK (posting_permission IN ('everyone', 'admins'))
);

-- Nome único entre os presets de sistema (torna o seed idempotente).
CREATE UNIQUE INDEX IF NOT EXISTS idx_workspace_presets_system_name
  ON public.workspace_presets (LOWER(TRIM(name))) WHERE is_system;

-- Um usuário não repete o nome dos próprios presets.
CREATE UNIQUE INDEX IF NOT EXISTS idx_workspace_presets_owner_name
  ON public.workspace_presets (created_by, LOWER(TRIM(name))) WHERE NOT is_system;

CREATE INDEX IF NOT EXISTS idx_workspace_presets_visibility
  ON public.workspace_presets (is_system, is_shared, created_by);

ALTER TABLE public.workspace_presets ENABLE ROW LEVEL SECURITY;

-- Leitura: quem pode criar workspace vê presets de sistema, compartilhados
-- e os próprios. Escrita passa exclusivamente pelas RPCs abaixo (sem policy
-- de INSERT/UPDATE/DELETE = negado por padrão no acesso direto).
DROP POLICY IF EXISTS "Ver presets de workspace" ON public.workspace_presets;
CREATE POLICY "Ver presets de workspace"
  ON public.workspace_presets FOR SELECT
  USING (
    public.current_user_can_create_workspace()
    AND (is_system OR is_shared OR created_by = auth.uid())
  );

-- ----------------------------------------------------------------------------
-- 3. Helpers
-- ----------------------------------------------------------------------------

-- Normaliza a lista de etapas de um canal: garante exatamente uma etapa
-- inicial e pelo menos uma etapa final entre as não canceladas.
CREATE OR REPLACE FUNCTION public.normalize_workflow_statuses(p_channel_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_initial_id UUID;
  v_final_id UUID;
BEGIN
  SELECT id INTO v_initial_id
  FROM public.workflow_status_config
  WHERE channel_id = p_channel_id AND is_cancelled = FALSE AND is_initial = TRUE
  ORDER BY status_order ASC
  LIMIT 1;

  IF v_initial_id IS NULL THEN
    SELECT id INTO v_initial_id
    FROM public.workflow_status_config
    WHERE channel_id = p_channel_id AND is_cancelled = FALSE
    ORDER BY status_order ASC
    LIMIT 1;
  END IF;

  UPDATE public.workflow_status_config
  SET is_initial = FALSE
  WHERE channel_id = p_channel_id AND is_initial = TRUE AND id IS DISTINCT FROM v_initial_id;

  IF v_initial_id IS NOT NULL THEN
    UPDATE public.workflow_status_config
    SET is_initial = TRUE
    WHERE id = v_initial_id AND is_initial = FALSE;
  END IF;

  -- Sem etapa final o card nunca conclui: promove a última não cancelada.
  IF NOT EXISTS (
    SELECT 1 FROM public.workflow_status_config
    WHERE channel_id = p_channel_id AND is_cancelled = FALSE AND is_final = TRUE
  ) THEN
    SELECT id INTO v_final_id
    FROM public.workflow_status_config
    WHERE channel_id = p_channel_id AND is_cancelled = FALSE
    ORDER BY status_order DESC
    LIMIT 1;

    IF v_final_id IS NOT NULL AND v_final_id IS DISTINCT FROM v_initial_id THEN
      UPDATE public.workflow_status_config SET is_final = TRUE WHERE id = v_final_id;
    END IF;
  END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. CRUD de presets
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.upsert_workspace_preset(
  p_id UUID DEFAULT NULL,
  p_name TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_category TEXT DEFAULT 'operacional',
  p_icon TEXT DEFAULT 'workspaces_rounded',
  p_color TEXT DEFAULT '#616161',
  p_card_type TEXT DEFAULT 'generic',
  p_workflow_enabled BOOLEAN DEFAULT TRUE,
  p_assignment_mode TEXT DEFAULT 'operator_pool',
  p_posting_permission TEXT DEFAULT 'everyone',
  p_status_config JSONB DEFAULT '[]'::JSONB,
  p_is_shared BOOLEAN DEFAULT TRUE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_name TEXT := NULLIF(TRIM(COALESCE(p_name, '')), '');
  v_is_system BOOLEAN;
  v_owner UUID;
  v_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  IF NOT public.current_user_can_create_workspace() THEN
    RAISE EXCEPTION 'Acesso Negado: apenas gestores ou administradores podem manter presets.';
  END IF;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'O preset precisa de um nome.';
  END IF;

  IF p_workflow_enabled AND COALESCE(jsonb_array_length(p_status_config), 0) = 0 THEN
    RAISE EXCEPTION 'Um preset com workflow precisa de pelo menos uma etapa.';
  END IF;

  IF p_id IS NOT NULL THEN
    SELECT is_system, created_by INTO v_is_system, v_owner
    FROM public.workspace_presets
    WHERE id = p_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Preset não encontrado.';
    END IF;

    IF v_is_system THEN
      RAISE EXCEPTION 'Presets do sistema são somente leitura. Duplique para criar sua versão.';
    END IF;

    IF v_owner IS DISTINCT FROM v_user_id
       AND NOT EXISTS (
         SELECT 1 FROM public.users u
         WHERE u.id = v_user_id
           AND (u.role_level::TEXT IN ('super_admin', 'admin', 'ti_admin', 'director')
                OR u.department_id = 'ti')
       ) THEN
      RAISE EXCEPTION 'Acesso Negado: este preset pertence a outro usuário.';
    END IF;

    UPDATE public.workspace_presets
    SET name = v_name,
        description = NULLIF(TRIM(COALESCE(p_description, '')), ''),
        category = COALESCE(NULLIF(TRIM(p_category), ''), 'operacional'),
        icon = COALESCE(NULLIF(TRIM(p_icon), ''), 'workspaces_rounded'),
        color = COALESCE(NULLIF(TRIM(p_color), ''), '#616161'),
        card_type = COALESCE(NULLIF(TRIM(p_card_type), ''), 'generic'),
        workflow_enabled = COALESCE(p_workflow_enabled, TRUE),
        assignment_mode = COALESCE(NULLIF(TRIM(p_assignment_mode), ''), 'operator_pool'),
        posting_permission = COALESCE(NULLIF(TRIM(p_posting_permission), ''), 'everyone'),
        status_config = COALESCE(p_status_config, '[]'::JSONB),
        is_shared = COALESCE(p_is_shared, TRUE),
        updated_at = NOW()
    WHERE id = p_id
    RETURNING id INTO v_id;

    RETURN v_id;
  END IF;

  INSERT INTO public.workspace_presets (
    name, description, category, icon, color, card_type, workflow_enabled,
    assignment_mode, posting_permission, status_config, is_system, is_shared, created_by
  )
  VALUES (
    v_name,
    NULLIF(TRIM(COALESCE(p_description, '')), ''),
    COALESCE(NULLIF(TRIM(p_category), ''), 'operacional'),
    COALESCE(NULLIF(TRIM(p_icon), ''), 'workspaces_rounded'),
    COALESCE(NULLIF(TRIM(p_color), ''), '#616161'),
    COALESCE(NULLIF(TRIM(p_card_type), ''), 'generic'),
    COALESCE(p_workflow_enabled, TRUE),
    COALESCE(NULLIF(TRIM(p_assignment_mode), ''), 'operator_pool'),
    COALESCE(NULLIF(TRIM(p_posting_permission), ''), 'everyone'),
    COALESCE(p_status_config, '[]'::JSONB),
    FALSE,
    COALESCE(p_is_shared, TRUE),
    v_user_id
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_workspace_preset(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_is_system BOOLEAN;
  v_owner UUID;
BEGIN
  SELECT is_system, created_by INTO v_is_system, v_owner
  FROM public.workspace_presets
  WHERE id = p_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_is_system THEN
    RAISE EXCEPTION 'Presets do sistema não podem ser excluídos.';
  END IF;

  IF v_owner IS DISTINCT FROM v_user_id
     AND NOT EXISTS (
       SELECT 1 FROM public.users u
       WHERE u.id = v_user_id
         AND (u.role_level::TEXT IN ('super_admin', 'admin', 'ti_admin', 'director')
              OR u.department_id = 'ti')
     ) THEN
    RAISE EXCEPTION 'Acesso Negado: este preset pertence a outro usuário.';
  END IF;

  DELETE FROM public.workspace_presets WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_workspace_preset(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT, JSONB, BOOLEAN
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_workspace_preset(UUID) TO authenticated;
-- normalize_workflow_statuses é helper interno (SECURITY DEFINER sem checagem
-- de permissão): só as RPCs acima o chamam, então não vai para `authenticated`.
REVOKE ALL ON FUNCTION public.normalize_workflow_statuses(UUID) FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- 5. Criação de workspace ciente de preset e das novas flags
-- ----------------------------------------------------------------------------

-- Assinatura antiga precisa sair de cena: manter as duas geraria ambiguidade
-- na resolução por parâmetros nomeados do PostgREST.
DROP FUNCTION IF EXISTS public.create_workspace(TEXT, TEXT, JSONB, UUID[], JSONB);

CREATE OR REPLACE FUNCTION public.create_workspace(
  p_name TEXT,
  p_description TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::JSONB,
  p_member_ids UUID[] DEFAULT ARRAY[]::UUID[],
  p_status_config JSONB DEFAULT '[]'::JSONB,
  p_preset_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_channel_id UUID;
  v_posting_permission TEXT;
  v_metadata JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  IF NOT public.current_user_can_create_workspace() THEN
    RAISE EXCEPTION 'Acesso Negado: apenas gestores ou administradores podem criar workspaces.';
  END IF;

  v_posting_permission := COALESCE(NULLIF(p_metadata->>'posting_permission', ''), 'everyone');
  v_metadata := COALESCE(p_metadata, '{}'::JSONB) || jsonb_build_object('archived', FALSE);

  IF p_preset_id IS NOT NULL THEN
    v_metadata := v_metadata || jsonb_build_object('preset_id', p_preset_id::TEXT);
  END IF;

  INSERT INTO public.channels (name, description, created_by, type, metadata, posting_permission)
  VALUES (
    NULLIF(TRIM(p_name), ''),
    NULLIF(TRIM(COALESCE(p_description, '')), ''),
    v_user_id,
    CASE WHEN COALESCE((p_metadata->>'workflow_enabled')::BOOLEAN, FALSE) THEN 'operacional' ELSE 'comum' END,
    v_metadata,
    v_posting_permission
  )
  RETURNING id INTO v_channel_id;

  INSERT INTO public.channel_members (channel_id, user_id, role)
  VALUES (v_channel_id, v_user_id, 'admin')
  ON CONFLICT ON CONSTRAINT channel_members_pkey DO UPDATE SET role = 'admin';

  INSERT INTO public.channel_members (channel_id, user_id, role)
  SELECT v_channel_id, member_id, 'viewer'
  FROM (
    SELECT DISTINCT unnest(COALESCE(p_member_ids, ARRAY[]::UUID[])) AS member_id
  ) members
  WHERE member_id IS NOT NULL
    AND member_id <> v_user_id
  ON CONFLICT ON CONSTRAINT channel_members_pkey DO NOTHING;

  INSERT INTO public.workflow_status_config (
    channel_id, status, status_order, color, icon, is_final, is_initial, is_cancelled
  )
  SELECT
    v_channel_id,
    NULLIF(TRIM(status), ''),
    COALESCE(status_order, (ROW_NUMBER() OVER ())::INT),
    COALESCE(color, '#6B7280'),
    COALESCE(icon, 'circle'),
    COALESCE(is_final, FALSE),
    COALESCE(is_initial, FALSE),
    COALESCE(is_cancelled, FALSE)
  FROM jsonb_to_recordset(COALESCE(p_status_config, '[]'::JSONB))
    AS x(status TEXT, status_order INT, color TEXT, icon TEXT,
         is_final BOOLEAN, is_initial BOOLEAN, is_cancelled BOOLEAN)
  WHERE NULLIF(TRIM(status), '') IS NOT NULL
  ON CONFLICT (channel_id, status) DO NOTHING;

  PERFORM public.normalize_workflow_statuses(v_channel_id);

  IF p_preset_id IS NOT NULL THEN
    UPDATE public.workspace_presets
    SET usage_count = usage_count + 1
    WHERE id = p_preset_id;
  END IF;

  RETURN v_channel_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_workspace(TEXT, TEXT, JSONB, UUID[], JSONB, UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. Edição completa de workspace (inclui as etapas do Kanban)
-- ----------------------------------------------------------------------------

-- p_status_config: lista COMPLETA desejada. Itens com `id` de uma etapa
--   existente são atualizados (renomear propaga para os cards); itens sem `id`
--   viram novas etapas; etapas ausentes da lista são removidas.
-- p_status_migrations: [{"from_status": "Etapa X", "to_status": "Etapa Y"}]
--   aplicado ANTES da remoção, para esvaziar etapas que ainda tenham cards. Se
--   sobrar card em uma etapa removida, a função aborta — nenhum card fica órfão.
CREATE OR REPLACE FUNCTION public.update_workspace(
  p_channel_id UUID,
  p_name TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT NULL,
  p_posting_permission TEXT DEFAULT NULL,
  p_status_config JSONB DEFAULT NULL,
  p_status_migrations JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_metadata JSONB;
  v_name TEXT;
  v_posting TEXT;
  v_workflow_enabled BOOLEAN;
  v_migrated INT := 0;
  v_renamed INT := 0;
  v_created INT := 0;
  v_removed INT := 0;
  v_row RECORD;
  v_blocking TEXT;
  v_blocking_count INT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para editar este workspace.';
  END IF;

  SELECT COALESCE(metadata, '{}'::JSONB), name, posting_permission
  INTO v_metadata, v_name, v_posting
  FROM public.channels
  WHERE id = p_channel_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workspace não encontrado.';
  END IF;

  -- Merge raso: as chaves enviadas sobrescrevem, o resto do metadata sobrevive.
  --
  -- Chaves de governança são removidas do payload: operadores só mudam por
  -- `update_workflow_operators` (exige super_admin ou criador do canal) e o
  -- arquivamento só por `archive_channel`. Sem isso, um `manager` usaria esta
  -- função como atalho para privilégios que ele não tem.
  IF p_metadata IS NOT NULL THEN
    v_metadata := v_metadata || (
      p_metadata
        - 'assignment_mode'
        - 'operator_ids'
        - 'default_operator_id'
        - 'operator_count'
        - 'archived'
        - 'archived_at'
    );
  END IF;

  v_name := COALESCE(NULLIF(TRIM(COALESCE(p_name, '')), ''), v_name);
  v_posting := COALESCE(NULLIF(TRIM(COALESCE(p_posting_permission, '')), ''), v_posting);
  v_workflow_enabled := COALESCE((v_metadata->>'workflow_enabled')::BOOLEAN, FALSE);

  UPDATE public.channels
  SET name = v_name,
      description = CASE
        WHEN p_description IS NULL THEN description
        ELSE NULLIF(TRIM(p_description), '')
      END,
      metadata = v_metadata,
      posting_permission = v_posting,
      type = CASE
        WHEN type = 'avisos' THEN type
        WHEN v_workflow_enabled THEN 'operacional'
        ELSE 'comum'
      END,
      updated_at = NOW()
  WHERE id = p_channel_id;

  IF p_status_config IS NULL THEN
    RETURN jsonb_build_object('ok', TRUE, 'status_config_touched', FALSE);
  END IF;

  -- Etapas desejadas, normalizadas em uma temp table para os passos seguintes.
  -- O schema é explícito (`pg_temp.`) para não depender da resolução implícita
  -- sob `SET search_path = public`; o DROP cobre uma segunda chamada dentro da
  -- mesma transação, já que `ON COMMIT DROP` só age no commit.
  DROP TABLE IF EXISTS pg_temp._desired_statuses;

  CREATE TEMP TABLE pg_temp._desired_statuses ON COMMIT DROP AS
  SELECT
    -- Ids temporários vindos do builder ("temp_1699...") não são UUID: viram
    -- NULL e a etapa é tratada como nova.
    CASE
      WHEN x.id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN x.id::UUID
      ELSE NULL
    END AS id,
    TRIM(x.status) AS status,
    COALESCE(x.status_order, (ROW_NUMBER() OVER ())::INT) AS status_order,
    COALESCE(NULLIF(TRIM(x.color), ''), '#6B7280') AS color,
    COALESCE(NULLIF(TRIM(x.icon), ''), 'circle') AS icon,
    COALESCE(x.is_final, FALSE) AS is_final,
    COALESCE(x.is_initial, FALSE) AS is_initial,
    COALESCE(x.is_cancelled, FALSE) AS is_cancelled
  FROM jsonb_to_recordset(p_status_config)
    AS x(id TEXT, status TEXT, status_order INT, color TEXT, icon TEXT,
         is_final BOOLEAN, is_initial BOOLEAN, is_cancelled BOOLEAN)
  WHERE NULLIF(TRIM(COALESCE(x.status, '')), '') IS NOT NULL;

  IF NOT EXISTS (SELECT 1 FROM pg_temp._desired_statuses) THEN
    RAISE EXCEPTION 'O workflow precisa de pelo menos uma etapa.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_temp._desired_statuses GROUP BY LOWER(status) HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Existem etapas com o mesmo nome. Os nomes precisam ser únicos.';
  END IF;

  -- Ignora ids que não pertencem a este canal (evita sequestro de etapa).
  UPDATE pg_temp._desired_statuses d
  SET id = NULL
  WHERE d.id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.workflow_status_config s
      WHERE s.id = d.id AND s.channel_id = p_channel_id
    );

  -- (a) Migrações explícitas de cards, antes de qualquer remoção.
  FOR v_row IN
    SELECT TRIM(m.from_status) AS from_status, TRIM(m.to_status) AS to_status
    FROM jsonb_to_recordset(COALESCE(p_status_migrations, '[]'::JSONB))
      AS m(from_status TEXT, to_status TEXT)
    WHERE NULLIF(TRIM(COALESCE(m.from_status, '')), '') IS NOT NULL
      AND NULLIF(TRIM(COALESCE(m.to_status, '')), '') IS NOT NULL
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_temp._desired_statuses d WHERE LOWER(d.status) = LOWER(v_row.to_status)
    ) THEN
      RAISE EXCEPTION 'Destino "%" não existe na nova configuração de etapas.', v_row.to_status;
    END IF;

    WITH moved AS (
      UPDATE public.workflow_cards
      SET status = v_row.to_status, updated_at = NOW()
      WHERE channel_id = p_channel_id
        AND LOWER(status) = LOWER(v_row.from_status)
      RETURNING id
    ),
    logged AS (
      INSERT INTO public.workflow_card_history (card_id, user_id, action, field_changed, old_value, new_value, observations)
      SELECT m.id, v_user_id, 'status_migrated', 'status', v_row.from_status, v_row.to_status,
             'Etapa removida na edição do workspace'
      FROM moved m
      RETURNING 1
    )
    SELECT COUNT(*) INTO v_blocking_count FROM logged;

    v_migrated := v_migrated + COALESCE(v_blocking_count, 0);
  END LOOP;

  -- (b) Renomeações em duas fases, para suportar trocas cíclicas de nome sem
  --     violar UNIQUE(channel_id, status).
  FOR v_row IN
    SELECT s.id, s.status AS old_status, d.status AS new_status
    FROM pg_temp._desired_statuses d
    JOIN public.workflow_status_config s ON s.id = d.id
    WHERE s.channel_id = p_channel_id
      AND s.status IS DISTINCT FROM d.status
  LOOP
    UPDATE public.workflow_status_config
    SET status = '__tmp_' || v_row.id::TEXT
    WHERE id = v_row.id;

    UPDATE public.workflow_cards
    SET status = '__tmp_' || v_row.id::TEXT
    WHERE channel_id = p_channel_id AND status = v_row.old_status;

    v_renamed := v_renamed + 1;
  END LOOP;

  FOR v_row IN
    SELECT s.id, d.status AS new_status
    FROM pg_temp._desired_statuses d
    JOIN public.workflow_status_config s ON s.id = d.id
    WHERE s.channel_id = p_channel_id
      AND s.status = '__tmp_' || s.id::TEXT
  LOOP
    UPDATE public.workflow_status_config
    SET status = v_row.new_status
    WHERE id = v_row.id;

    UPDATE public.workflow_cards
    SET status = v_row.new_status, updated_at = NOW()
    WHERE channel_id = p_channel_id AND status = '__tmp_' || v_row.id::TEXT;
  END LOOP;

  -- (c) Atributos visuais/semânticos das etapas mantidas.
  UPDATE public.workflow_status_config s
  SET status_order = d.status_order,
      color = d.color,
      icon = d.icon,
      is_final = d.is_final,
      is_initial = d.is_initial,
      is_cancelled = d.is_cancelled
  FROM pg_temp._desired_statuses d
  WHERE s.id = d.id AND s.channel_id = p_channel_id;

  -- (d) Novas etapas.
  WITH inserted AS (
    INSERT INTO public.workflow_status_config (
      channel_id, status, status_order, color, icon, is_final, is_initial, is_cancelled
    )
    SELECT p_channel_id, d.status, d.status_order, d.color, d.icon,
           d.is_final, d.is_initial, d.is_cancelled
    FROM pg_temp._desired_statuses d
    WHERE d.id IS NULL
    ON CONFLICT (channel_id, status) DO NOTHING
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_created FROM inserted;

  -- (e) Remoções — só depois de garantir que nenhuma delas tem card vivo.
  SELECT s.status, COUNT(c.id)
  INTO v_blocking, v_blocking_count
  FROM public.workflow_status_config s
  JOIN public.workflow_cards c
    ON c.channel_id = p_channel_id AND LOWER(c.status) = LOWER(s.status)
  WHERE s.channel_id = p_channel_id
    AND NOT EXISTS (
      SELECT 1 FROM pg_temp._desired_statuses d WHERE LOWER(d.status) = LOWER(s.status)
    )
  GROUP BY s.status
  ORDER BY COUNT(c.id) DESC
  LIMIT 1;

  IF v_blocking IS NOT NULL THEN
    RAISE EXCEPTION 'A etapa "%" ainda tem % card(s). Escolha para onde movê-los antes de removê-la.',
      v_blocking, v_blocking_count;
  END IF;

  WITH removed AS (
    DELETE FROM public.workflow_status_config s
    WHERE s.channel_id = p_channel_id
      AND NOT EXISTS (
        SELECT 1 FROM pg_temp._desired_statuses d WHERE LOWER(d.status) = LOWER(s.status)
      )
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_removed FROM removed;

  PERFORM public.normalize_workflow_statuses(p_channel_id);

  DROP TABLE IF EXISTS pg_temp._desired_statuses;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'status_config_touched', TRUE,
    'cards_migrated', v_migrated,
    'stages_renamed', v_renamed,
    'stages_created', v_created,
    'stages_removed', v_removed
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_workspace(UUID, TEXT, TEXT, JSONB, TEXT, JSONB, JSONB) TO authenticated;

-- Quantos cards existem por etapa — a UI usa isso para pedir o destino antes
-- de deixar o usuário remover uma etapa ocupada.
CREATE OR REPLACE FUNCTION public.workspace_status_usage(p_channel_id UUID)
RETURNS TABLE (status TEXT, card_count BIGINT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.status, COUNT(*)::BIGINT
  FROM public.workflow_cards c
  WHERE c.channel_id = p_channel_id
    AND public.is_channel_member(p_channel_id)
  GROUP BY c.status;
$$;

GRANT EXECUTE ON FUNCTION public.workspace_status_usage(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 7. Seed dos presets de sistema (espelham o que era hardcoded no Flutter)
-- ----------------------------------------------------------------------------

INSERT INTO public.workspace_presets (
  name, description, category, icon, color, card_type, workflow_enabled,
  assignment_mode, status_config, is_system, is_shared
)
VALUES
  (
    'Liberação Contas a Pagar',
    'Solicitação e liberação de pagamentos a fornecedores.',
    'financeiro', 'payments_outlined', '#2E7D32', 'conta_pagar', TRUE, 'operator_pool',
    '[{"status":"Novo","status_order":1,"color":"#3B82F6","icon":"add_circle","is_final":false,"is_initial":true,"is_cancelled":false},
      {"status":"Em análise","status_order":2,"color":"#F59E0B","icon":"search","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Aguardando Solicitante","status_order":3,"color":"#8B5CF6","icon":"hourglass_empty","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Liberado para Pagamento","status_order":4,"color":"#0EA5E9","icon":"task_alt","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Pago","status_order":5,"color":"#22C55E","icon":"task_alt","is_final":true,"is_initial":false,"is_cancelled":false},
      {"status":"Cancelado","status_order":6,"color":"#EF4444","icon":"cancel","is_final":false,"is_initial":false,"is_cancelled":true}]'::JSONB,
    TRUE, TRUE
  ),
  (
    'Liberação de Pedido',
    'Conferência e liberação de pedidos de veículos.',
    'faturamento', 'fact_check', '#7B1FA2', 'fat_moto', TRUE, 'operator_pool',
    '[{"status":"Solicitação criada","status_order":1,"color":"#3B82F6","icon":"add_circle","is_final":false,"is_initial":true,"is_cancelled":false},
      {"status":"Em conferência","status_order":2,"color":"#F59E0B","icon":"search","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Aguardando liberação","status_order":3,"color":"#8B5CF6","icon":"hourglass_empty","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Liberado","status_order":4,"color":"#0EA5E9","icon":"task_alt","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Pendente de ajuste","status_order":5,"color":"#F97316","icon":"error_outline","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Finalizado","status_order":6,"color":"#22C55E","icon":"task_alt","is_final":true,"is_initial":false,"is_cancelled":false},
      {"status":"Cancelado","status_order":7,"color":"#EF4444","icon":"cancel","is_final":false,"is_initial":false,"is_cancelled":true}]'::JSONB,
    TRUE, TRUE
  ),
  (
    'Documentação/Cadastro',
    'Emplacamento e trâmites documentais.',
    'operacional', 'description', '#1565C0', 'emplacamento', TRUE, 'operator_pool',
    '[{"status":"Solicitação aberta","status_order":1,"color":"#3B82F6","icon":"add_circle","is_final":false,"is_initial":true,"is_cancelled":false},
      {"status":"Documentação em análise","status_order":2,"color":"#F59E0B","icon":"search","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Aguardando pagamento/taxa","status_order":3,"color":"#8B5CF6","icon":"hourglass_empty","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Em processamento","status_order":4,"color":"#0EA5E9","icon":"autorenew","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Concluído","status_order":5,"color":"#22C55E","icon":"task_alt","is_final":true,"is_initial":false,"is_cancelled":false},
      {"status":"Pendência documental","status_order":6,"color":"#F97316","icon":"error_outline","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Cancelado","status_order":7,"color":"#EF4444","icon":"cancel","is_final":false,"is_initial":false,"is_cancelled":true}]'::JSONB,
    TRUE, TRUE
  ),
  (
    'Faturamento OS/Produtos',
    'Faturamento de ordens de serviço e peças.',
    'faturamento', 'receipt_outlined', '#E65100', 'faturamento_os', TRUE, 'operator_pool',
    '[{"status":"Aberto","status_order":1,"color":"#3B82F6","icon":"add_circle","is_final":false,"is_initial":true,"is_cancelled":false},
      {"status":"Em análise","status_order":2,"color":"#F59E0B","icon":"search","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Em faturamento","status_order":3,"color":"#0EA5E9","icon":"autorenew","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Aguardando correção","status_order":4,"color":"#F97316","icon":"error_outline","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Faturado","status_order":5,"color":"#22C55E","icon":"task_alt","is_final":true,"is_initial":false,"is_cancelled":false},
      {"status":"Cancelado","status_order":6,"color":"#EF4444","icon":"cancel","is_final":false,"is_initial":false,"is_cancelled":true}]'::JSONB,
    TRUE, TRUE
  ),
  (
    'Avisos Gerais',
    'Canal de comunicados sem fila de atendimento.',
    'informativo', 'campaign_outlined', '#C62828', 'aviso', TRUE, 'manual',
    '[{"status":"Ativo","status_order":1,"color":"#3B82F6","icon":"campaign","is_final":false,"is_initial":true,"is_cancelled":false},
      {"status":"Arquivado","status_order":2,"color":"#22C55E","icon":"task_alt","is_final":true,"is_initial":false,"is_cancelled":false}]'::JSONB,
    TRUE, TRUE
  ),
  (
    'Canal Genérico',
    'Fluxo simples de quatro etapas para qualquer time.',
    'operacional', 'workspaces_rounded', '#616161', 'generic', TRUE, 'operator_pool',
    '[{"status":"Novo","status_order":1,"color":"#3B82F6","icon":"add_circle","is_final":false,"is_initial":true,"is_cancelled":false},
      {"status":"Em andamento","status_order":2,"color":"#F59E0B","icon":"autorenew","is_final":false,"is_initial":false,"is_cancelled":false},
      {"status":"Concluído","status_order":3,"color":"#22C55E","icon":"task_alt","is_final":true,"is_initial":false,"is_cancelled":false},
      {"status":"Cancelado","status_order":4,"color":"#EF4444","icon":"cancel","is_final":false,"is_initial":false,"is_cancelled":true}]'::JSONB,
    TRUE, TRUE
  ),
  (
    'Somente Comunicação',
    'Workspace sem Kanban: apenas mensagens, anúncios e enquetes.',
    'informativo', 'forum', '#0369A1', 'generic', FALSE, 'manual',
    '[]'::JSONB,
    TRUE, TRUE
  )
ON CONFLICT (LOWER(TRIM(name))) WHERE is_system DO UPDATE
SET description = EXCLUDED.description,
    category = EXCLUDED.category,
    icon = EXCLUDED.icon,
    color = EXCLUDED.color,
    card_type = EXCLUDED.card_type,
    workflow_enabled = EXCLUDED.workflow_enabled,
    assignment_mode = EXCLUDED.assignment_mode,
    status_config = EXCLUDED.status_config,
    updated_at = NOW();

-- ============================================================================
-- ADAPTAÇÃO MULTI-TENANT (exclusiva do AlinhaJá)
-- ============================================================================
-- Este arquivo tem o mesmo nome no Fluxy, com conteúdo diferente de propósito:
-- lá o banco é de um tenant só. Aqui `workspace_presets` precisa de isolamento
-- por organização.
--
-- Por que NÃO usar o `trg_force_org` genérico: `fn_tg_force_current_org()` cai
-- na org inicial quando `auth.uid()` é nulo — e é exatamente esse o contexto do
-- seed abaixo. Os 7 presets de sistema sairiam carimbados com a primeira org e
-- ficariam invisíveis para todas as outras. Eles são globais por natureza, então
-- ficam com `organization_id` NULL e um trigger próprio só carimba os presets
-- criados por usuário.
-- ============================================================================

ALTER TABLE public.workspace_presets
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id);

CREATE INDEX IF NOT EXISTS idx_workspace_presets_organization
  ON public.workspace_presets(organization_id);

-- Preset de sistema é global (org NULL); preset de usuário herda a org de quem
-- criou, sem aceitar valor vindo do cliente.
CREATE OR REPLACE FUNCTION public.fn_tg_workspace_preset_org()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.is_system, FALSE) THEN
    NEW.organization_id := NULL;
  ELSE
    NEW.organization_id := public.fn_current_org();
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_tg_workspace_preset_org() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_workspace_preset_org ON public.workspace_presets;
CREATE TRIGGER trg_workspace_preset_org
  BEFORE INSERT ON public.workspace_presets
  FOR EACH ROW EXECUTE FUNCTION public.fn_tg_workspace_preset_org();

-- Carimba o que já existir (execuções anteriores desta migration).
UPDATE public.workspace_presets p
SET organization_id = u.organization_id
FROM public.users u
WHERE p.created_by = u.id
  AND p.is_system = FALSE
  AND p.organization_id IS NULL;

-- Isolamento por tenant: RESTRICTIVE entra em AND com a policy de leitura já
-- criada acima. O ramo `is_system` mantém os modelos de fábrica visíveis a
-- todas as organizações.
DROP POLICY IF EXISTS tenant_isolation ON public.workspace_presets;
CREATE POLICY tenant_isolation
  ON public.workspace_presets AS RESTRICTIVE FOR ALL
  USING (
    organization_id = public.fn_current_org()
    OR (is_system AND organization_id IS NULL)
  )
  WITH CHECK (
    organization_id = public.fn_current_org()
    OR (is_system AND organization_id IS NULL)
  );

-- O nome único por dono passa a considerar a org: duas organizações podem ter
-- presets homônimos sem colidir.
DROP INDEX IF EXISTS idx_workspace_presets_owner_name;
CREATE UNIQUE INDEX IF NOT EXISTS idx_workspace_presets_owner_name
  ON public.workspace_presets (organization_id, created_by, LOWER(TRIM(name)))
  WHERE NOT is_system;
