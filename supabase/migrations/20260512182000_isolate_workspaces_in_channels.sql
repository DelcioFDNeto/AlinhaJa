-- ============================================================================
-- Isolate operational workspaces in dedicated channel tables
-- ============================================================================
-- DMs/groups stay in chats/messages/chat_members.
-- Operational channels/workspaces use channels/channel_messages/channel_members.
-- ============================================================================

ALTER TABLE public.channels
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  ADD COLUMN IF NOT EXISTS posting_permission TEXT NOT NULL DEFAULT 'everyone';

ALTER TABLE public.channel_members
  ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE public.workflow_cards
  DROP CONSTRAINT IF EXISTS workflow_cards_channel_id_fkey;

ALTER TABLE public.workflow_status_config
  DROP CONSTRAINT IF EXISTS workflow_status_config_channel_id_fkey;

-- Preserve already seeded workspace ids while moving their backing table.
INSERT INTO public.channels (
  id, name, description, created_by, type, metadata, posting_permission,
  created_at, updated_at, last_message_at
)
SELECT
  c.id,
  c.name,
  c.description,
  c.created_by,
  CASE
    WHEN COALESCE(c.metadata->>'card_type', '') = 'aviso' THEN 'avisos'
    ELSE 'operacional'
  END,
  COALESCE(c.metadata, '{}'::JSONB),
  COALESCE(NULLIF(c.metadata->>'posting_permission', ''), 'everyone'),
  c.created_at,
  c.updated_at,
  c.updated_at
FROM public.chats c
WHERE c.type = 'channel'::chat_type
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    created_by = EXCLUDED.created_by,
    type = EXCLUDED.type,
    metadata = EXCLUDED.metadata,
    posting_permission = EXCLUDED.posting_permission,
    updated_at = NOW();

INSERT INTO public.channel_members (channel_id, user_id, role, last_read_at, created_at)
SELECT
  cm.chat_id,
  cm.user_id,
  CASE WHEN cm.role::TEXT IN ('owner', 'admin') THEN 'admin' ELSE 'viewer' END,
  cm.last_read_at,
  cm.joined_at
FROM public.chat_members cm
JOIN public.chats c ON c.id = cm.chat_id
WHERE c.type = 'channel'::chat_type
ON CONFLICT ON CONSTRAINT channel_members_pkey DO UPDATE
SET role = EXCLUDED.role,
    last_read_at = EXCLUDED.last_read_at;

ALTER TABLE public.workflow_cards
  ADD CONSTRAINT workflow_cards_channel_id_fkey
  FOREIGN KEY (channel_id) REFERENCES public.channels(id) ON DELETE CASCADE;

ALTER TABLE public.workflow_status_config
  ADD CONSTRAINT workflow_status_config_channel_id_fkey
  FOREIGN KEY (channel_id) REFERENCES public.channels(id) ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION public.is_channel_member(p_channel_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.channel_members cm
    WHERE cm.channel_id = p_channel_id
      AND cm.user_id = auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_channel_member(UUID) TO authenticated;

DROP POLICY IF EXISTS "Ver membros do mesmo canal" ON public.channel_members;
CREATE POLICY "Ver membros do mesmo canal"
  ON public.channel_members FOR SELECT
  USING (public.is_channel_member(channel_id));

DROP POLICY IF EXISTS "Entrar em canal dedicado" ON public.channel_members;
CREATE POLICY "Entrar em canal dedicado"
  ON public.channel_members FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND role = 'viewer'
    AND EXISTS (
      SELECT 1 FROM public.channels c
      WHERE c.id = channel_id
        AND LOWER(COALESCE(c.metadata->>'archived', 'false')) <> 'true'
    )
  );

DROP POLICY IF EXISTS "Atualizar leitura propria do canal" ON public.channel_members;
CREATE POLICY "Atualizar leitura propria do canal"
  ON public.channel_members FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Membros veem cards do canal" ON public.workflow_cards;
CREATE POLICY "Membros veem cards do canal"
  ON public.workflow_cards FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.channel_members cm
      WHERE cm.channel_id = workflow_cards.channel_id
        AND cm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Membros criam cards no canal" ON public.workflow_cards;
CREATE POLICY "Membros criam cards no canal"
  ON public.workflow_cards FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.channel_members cm
      WHERE cm.channel_id = workflow_cards.channel_id
        AND cm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Membros atualizam cards" ON public.workflow_cards;
CREATE POLICY "Membros atualizam cards"
  ON public.workflow_cards FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.channel_members cm
      WHERE cm.channel_id = workflow_cards.channel_id
        AND cm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Responsável atualiza cards" ON public.workflow_cards;
CREATE POLICY "Responsável atualiza cards"
  ON public.workflow_cards FOR UPDATE
  USING (
    assigned_to = auth.uid()
    OR requested_by = auth.uid()
    OR (
      EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role_level IN ('super_admin', 'admin', 'manager')
      )
      AND EXISTS (
        SELECT 1 FROM public.channel_members cm
        WHERE cm.channel_id = workflow_cards.channel_id
          AND cm.user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "Membros veem comentários" ON public.workflow_card_comments;
CREATE POLICY "Membros veem comentários"
  ON public.workflow_card_comments FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.workflow_cards wc
      JOIN public.channel_members cm ON cm.channel_id = wc.channel_id
      WHERE wc.id = workflow_card_comments.card_id
        AND cm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Membros inserem comentários" ON public.workflow_card_comments;
CREATE POLICY "Membros inserem comentários"
  ON public.workflow_card_comments FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.workflow_cards wc
      JOIN public.channel_members cm ON cm.channel_id = wc.channel_id
      WHERE wc.id = workflow_card_comments.card_id
        AND cm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Membros veem histórico" ON public.workflow_card_history;
CREATE POLICY "Membros veem histórico"
  ON public.workflow_card_history FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.workflow_cards wc
      JOIN public.channel_members cm ON cm.channel_id = wc.channel_id
      WHERE wc.id = workflow_card_history.card_id
        AND cm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Membros leem config de status" ON public.workflow_status_config;
CREATE POLICY "Membros leem config de status"
  ON public.workflow_status_config FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.channel_members cm
      WHERE cm.channel_id = workflow_status_config.channel_id
        AND cm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Admins gerenciam status config" ON public.workflow_status_config;
CREATE POLICY "Admins gerenciam status config"
  ON public.workflow_status_config FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.channel_members cm
      WHERE cm.channel_id = workflow_status_config.channel_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin', 'editor')
    )
  );

CREATE OR REPLACE FUNCTION public.can_manage_workspace(
  p_channel_id UUID,
  p_min_role TEXT DEFAULT 'manager'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_department_id TEXT;
  v_is_owner BOOLEAN := FALSE;
  v_has_global_role BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NULL OR p_channel_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT role_level::TEXT, department_id
  INTO v_role, v_department_id
  FROM public.users
  WHERE id = auth.uid()
    AND COALESCE(is_active, TRUE) = TRUE;

  SELECT EXISTS (
    SELECT 1 FROM public.channels c
    WHERE c.id = p_channel_id
      AND c.created_by = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.channel_members cm
    WHERE cm.channel_id = p_channel_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin', 'editor')
  )
  INTO v_is_owner;

  IF p_min_role = 'admin' THEN
    v_has_global_role := COALESCE(
      v_role IN ('super_admin', 'admin', 'ti_admin', 'director')
      OR v_department_id = 'ti',
      FALSE
    );
  ELSE
    v_has_global_role := COALESCE(
      v_role IN ('super_admin', 'admin', 'manager', 'ti_admin', 'director', 'store_leader', 'coordinator')
      OR v_department_id = 'ti',
      FALSE
    );
  END IF;

  RETURN v_is_owner OR v_has_global_role;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_workspace(
  p_name TEXT,
  p_description TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::JSONB,
  p_member_ids UUID[] DEFAULT ARRAY[]::UUID[],
  p_status_config JSONB DEFAULT '[]'::JSONB
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
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  IF NOT public.current_user_can_create_workspace() THEN
    RAISE EXCEPTION 'Acesso Negado: apenas gestores ou administradores podem criar workspaces.';
  END IF;

  v_posting_permission := COALESCE(NULLIF(p_metadata->>'posting_permission', ''), 'everyone');

  INSERT INTO public.channels (name, description, created_by, type, metadata, posting_permission)
  VALUES (
    NULLIF(TRIM(p_name), ''),
    NULLIF(TRIM(COALESCE(p_description, '')), ''),
    v_user_id,
    CASE WHEN COALESCE((p_metadata->>'workflow_enabled')::BOOLEAN, FALSE) THEN 'operacional' ELSE 'comum' END,
    COALESCE(p_metadata, '{}'::JSONB) || jsonb_build_object('archived', FALSE),
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

  INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
  SELECT
    v_channel_id,
    NULLIF(TRIM(status), ''),
    COALESCE(status_order, (ROW_NUMBER() OVER ())::INT),
    COALESCE(color, '#6B7280'),
    COALESCE(icon, 'circle'),
    COALESCE(is_final, FALSE)
  FROM jsonb_to_recordset(COALESCE(p_status_config, '[]'::JSONB))
    AS x(status TEXT, status_order INT, color TEXT, icon TEXT, is_final BOOLEAN)
  WHERE NULLIF(TRIM(status), '') IS NOT NULL;

  RETURN v_channel_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_channel(p_channel_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_manage_workspace(p_channel_id, 'admin') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para excluir este workspace.';
  END IF;

  DELETE FROM public.workflow_card_comments
  WHERE card_id IN (SELECT id FROM public.workflow_cards WHERE channel_id = p_channel_id);

  DELETE FROM public.workflow_card_history
  WHERE card_id IN (SELECT id FROM public.workflow_cards WHERE channel_id = p_channel_id);

  DELETE FROM public.workflow_cards WHERE channel_id = p_channel_id;
  DELETE FROM public.workflow_status_config WHERE channel_id = p_channel_id;
  DELETE FROM public.channel_messages WHERE channel_id = p_channel_id;
  DELETE FROM public.channel_members WHERE channel_id = p_channel_id;
  DELETE FROM public.channels WHERE id = p_channel_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.archive_channel(p_channel_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para arquivar este workspace.';
  END IF;

  UPDATE public.channels
  SET metadata = COALESCE(metadata, '{}'::JSONB)
      || jsonb_build_object('archived', TRUE, 'archived_at', NOW()::TEXT),
      updated_at = NOW()
  WHERE id = p_channel_id;

  DELETE FROM public.channel_members
  WHERE channel_id = p_channel_id
    AND role <> 'admin';
END;
$$;

CREATE OR REPLACE FUNCTION public.add_channel_member(
  p_channel_id UUID,
  p_user_id UUID,
  p_role TEXT DEFAULT 'viewer'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT := LOWER(COALESCE(p_role, 'viewer'));
BEGIN
  IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para adicionar membros.';
  END IF;

  IF v_role NOT IN ('admin', 'editor', 'viewer') THEN
    v_role := 'viewer';
  END IF;

  INSERT INTO public.channel_members (channel_id, user_id, role)
  VALUES (p_channel_id, p_user_id, v_role)
  ON CONFLICT ON CONSTRAINT channel_members_pkey DO UPDATE SET role = EXCLUDED.role;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_channel_member(
  p_channel_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_manage_workspace(p_channel_id, 'manager') THEN
    RAISE EXCEPTION 'Acesso Negado: sem permissão para remover membros.';
  END IF;

  DELETE FROM public.channel_members
  WHERE channel_id = p_channel_id
    AND user_id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_workflow_card(p_card_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_channel_id UUID;
  v_assigned_to UUID;
  v_requested_by UUID;
  v_status TEXT;
  v_channel_metadata JSONB;
  v_assignment_mode TEXT;
  v_default_operator_id UUID;
  v_operator_ids JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  SELECT wc.channel_id, wc.assigned_to, wc.requested_by, wc.status, COALESCE(c.metadata, '{}'::JSONB)
  INTO v_channel_id, v_assigned_to, v_requested_by, v_status, v_channel_metadata
  FROM public.workflow_cards wc
  JOIN public.channels c ON c.id = wc.channel_id
  WHERE wc.id = p_card_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Card não encontrado.';
  END IF;

  IF LOWER(COALESCE(v_status, '')) = 'cancelado' THEN
    RAISE EXCEPTION 'Card cancelado não pode ser assumido.';
  END IF;

  IF v_requested_by = v_user_id THEN
    RAISE EXCEPTION 'O solicitante não deve assumir o próprio atendimento.';
  END IF;

  IF v_assigned_to IS NOT NULL AND v_assigned_to <> v_user_id THEN
    RAISE EXCEPTION 'Este card já possui responsável.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.channel_members cm
    WHERE cm.channel_id = v_channel_id
      AND cm.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não participa deste workspace.';
  END IF;

  v_assignment_mode := COALESCE(NULLIF(v_channel_metadata->>'assignment_mode', ''), 'operator_pool');
  v_default_operator_id := NULLIF(v_channel_metadata->>'default_operator_id', '')::UUID;
  v_operator_ids := v_channel_metadata->'operator_ids';

  IF v_assignment_mode = 'single_operator'
     AND v_default_operator_id IS NOT NULL
     AND v_default_operator_id <> v_user_id THEN
    RAISE EXCEPTION 'Apenas o operador definido pode assumir cards deste canal.';
  END IF;

  IF jsonb_typeof(v_operator_ids) = 'array'
     AND jsonb_array_length(v_operator_ids) > 0
     AND NOT EXISTS (
       SELECT 1
       FROM jsonb_array_elements_text(v_operator_ids) AS operator_id(value)
       WHERE operator_id.value::UUID = v_user_id
     ) THEN
    RAISE EXCEPTION 'Usuário não está configurado como operador deste canal.';
  END IF;

  UPDATE public.workflow_cards
  SET assigned_to = v_user_id,
      updated_at = NOW()
  WHERE id = p_card_id;

  INSERT INTO public.workflow_card_history (
    card_id, user_id, action, field_changed, old_value, new_value, observations
  )
  VALUES (
    p_card_id,
    v_user_id,
    'Card assumido',
    'assigned_to',
    COALESCE(v_assigned_to::TEXT, ''),
    v_user_id::TEXT,
    'Operador assumiu o atendimento'
  );

  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_workflow_operators(
  p_channel_id UUID,
  p_assignment_mode TEXT,
  p_operator_ids UUID[] DEFAULT ARRAY[]::UUID[],
  p_default_operator_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_operator_ids UUID[] := COALESCE(p_operator_ids, ARRAY[]::UUID[]);
  v_operator_count INT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Acesso Negado: usuário não autenticado.';
  END IF;

  IF NOT (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = v_user_id
        AND COALESCE(u.is_active, TRUE) = TRUE
        AND u.role_level::TEXT = 'super_admin'
    )
    OR EXISTS (
      SELECT 1 FROM public.channels c
      WHERE c.id = p_channel_id
        AND c.created_by = v_user_id
    )
  ) THEN
    RAISE EXCEPTION 'Acesso Negado: apenas super_admin ou criador do canal pode gerenciar operadores.';
  END IF;

  IF p_assignment_mode NOT IN ('single_operator', 'operator_pool') THEN
    RAISE EXCEPTION 'Modo de atribuição inválido.';
  END IF;

  IF p_assignment_mode = 'single_operator' AND p_default_operator_id IS NULL THEN
    RAISE EXCEPTION 'Canal com operador único exige default_operator_id.';
  END IF;

  IF p_assignment_mode = 'operator_pool' AND array_length(v_operator_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'Canal com equipe exige ao menos um operador.';
  END IF;

  IF p_default_operator_id IS NOT NULL AND NOT p_default_operator_id = ANY(v_operator_ids) THEN
    v_operator_ids := array_append(v_operator_ids, p_default_operator_id);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(v_operator_ids) AS operator_candidate(user_id)
    WHERE NOT EXISTS (
      SELECT 1 FROM public.channel_members cm
      WHERE cm.channel_id = p_channel_id
        AND cm.user_id = operator_candidate.user_id
    )
  ) THEN
    RAISE EXCEPTION 'Todos os operadores precisam ser membros do canal.';
  END IF;

  v_operator_count := COALESCE(array_length(v_operator_ids, 1), 0);

  UPDATE public.channels
  SET metadata = COALESCE(metadata, '{}'::JSONB)
      || jsonb_build_object(
        'assignment_mode', p_assignment_mode,
        'operator_ids', COALESCE(to_jsonb(v_operator_ids), '[]'::JSONB),
        'default_operator_id', CASE
          WHEN p_assignment_mode = 'single_operator'
          THEN to_jsonb(p_default_operator_id)
          ELSE 'null'::JSONB
        END,
        'operator_count', v_operator_count
      ),
      updated_at = NOW()
  WHERE id = p_channel_id;

  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.seed_base_workflow_channels(
  p_reset_statuses BOOLEAN DEFAULT TRUE,
  p_preserve_operator_config BOOLEAN DEFAULT TRUE
)
RETURNS TABLE(channel_name TEXT, channel_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id UUID;
  v_ch_contas UUID;
  v_ch_fat_moto UUID;
  v_ch_emplacamento UUID;
  v_ch_fat_os UUID;
  v_ch_avisos UUID;
BEGIN
  SELECT id
  INTO v_owner_id
  FROM public.users
  WHERE COALESCE(is_active, TRUE) = TRUE
  ORDER BY
    CASE role_level::TEXT
      WHEN 'super_admin' THEN 1
      WHEN 'admin' THEN 2
      WHEN 'manager' THEN 3
      WHEN 'ti_admin' THEN 4
      ELSE 9
    END,
    created_at
  LIMIT 1;

  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum usuario ativo encontrado para criar os canais base.';
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS pg_temp.base_workflow_channels (
    name TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    channel_type TEXT NOT NULL,
    posting_permission TEXT NOT NULL,
    metadata JSONB NOT NULL
  ) ON COMMIT DROP;

  TRUNCATE TABLE pg_temp.base_workflow_channels;

  INSERT INTO pg_temp.base_workflow_channels (name, description, channel_type, posting_permission, metadata) VALUES
    ('Liberação Contas a Pagar', 'Solicitações de contas a pagar. Operadores conferem, solicitantes respondem pendências e o financeiro conclui o pagamento.', 'operacional', 'everyone', '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"conta_pagar","category":"financeiro","color":"#2E7D32","icon":"payments_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::JSONB),
    ('Liberação Fat Moto', 'Solicitações de liberação/faturamento de motocicletas com conferência operacional e retorno ao solicitante quando necessário.', 'operacional', 'everyone', '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"fat_moto","category":"financeiro","color":"#7B1FA2","icon":"two_wheeler","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::JSONB),
    ('Emplacamento', 'Acompanhamento de emplacamento com dados do cliente, veículo, chassi, placa, filial, anexos e histórico de atendimento.', 'operacional', 'everyone', '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"emplacamento","category":"operacional","color":"#1565C0","icon":"directions_car_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::JSONB),
    ('Faturamento OS/Peças', 'Solicitações de faturamento de ordens de serviço e peças com conferência, correção e emissão final.', 'operacional', 'everyone', '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"everyone","card_type":"faturamento_os","category":"faturamento","color":"#E65100","icon":"receipt_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::JSONB),
    ('Avisos Gerais', 'Comunicados gerais da empresa. Avisos, reuniões e atualizações corporativas.', 'avisos', 'admins', '{"workspace":"alinha_operations","workflow_enabled":true,"posting_permission":"admins","card_type":"aviso","category":"informativo","color":"#C62828","icon":"campaign_outlined","assignment_mode":"operator_pool","operator_ids":[],"default_operator_id":null,"operator_count":0,"archived":false}'::JSONB);

  INSERT INTO public.channels (name, description, created_by, type, metadata, posting_permission)
  SELECT b.name, b.description, v_owner_id, b.channel_type, b.metadata, b.posting_permission
  FROM pg_temp.base_workflow_channels b
  WHERE NOT EXISTS (SELECT 1 FROM public.channels c WHERE c.name = b.name);

  UPDATE public.channels c
  SET description = b.description,
      created_by = COALESCE(c.created_by, v_owner_id),
      type = b.channel_type,
      posting_permission = b.posting_permission,
      metadata = COALESCE(c.metadata, '{}'::JSONB)
        || b.metadata
        || CASE
          WHEN p_preserve_operator_config THEN jsonb_build_object(
            'assignment_mode', COALESCE(NULLIF(c.metadata->>'assignment_mode', ''), b.metadata->>'assignment_mode'),
            'operator_ids', CASE
              WHEN jsonb_typeof(c.metadata->'operator_ids') = 'array' THEN c.metadata->'operator_ids'
              ELSE COALESCE(b.metadata->'operator_ids', '[]'::JSONB)
            END,
            'default_operator_id', CASE
              WHEN c.metadata ? 'default_operator_id' THEN c.metadata->'default_operator_id'
              ELSE COALESCE(b.metadata->'default_operator_id', 'null'::JSONB)
            END,
            'operator_count', CASE
              WHEN jsonb_typeof(c.metadata->'operator_count') = 'number' THEN c.metadata->'operator_count'
              ELSE COALESCE(b.metadata->'operator_count', '0'::JSONB)
            END
          )
          ELSE '{}'::JSONB
        END,
      updated_at = NOW()
  FROM pg_temp.base_workflow_channels b
  WHERE c.name = b.name;

  SELECT id INTO v_ch_contas FROM public.channels WHERE name = 'Liberação Contas a Pagar' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_ch_fat_moto FROM public.channels WHERE name = 'Liberação Fat Moto' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_ch_emplacamento FROM public.channels WHERE name = 'Emplacamento' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_ch_fat_os FROM public.channels WHERE name = 'Faturamento OS/Peças' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_ch_avisos FROM public.channels WHERE name = 'Avisos Gerais' ORDER BY created_at LIMIT 1;

  INSERT INTO public.channel_members (channel_id, user_id, role)
  SELECT ch.channel_id, v_owner_id, 'admin'
  FROM (VALUES (v_ch_contas), (v_ch_fat_moto), (v_ch_emplacamento), (v_ch_fat_os), (v_ch_avisos)) ch(channel_id)
  WHERE ch.channel_id IS NOT NULL
  ON CONFLICT ON CONSTRAINT channel_members_pkey DO UPDATE SET role = 'admin';

  INSERT INTO public.channel_members (channel_id, user_id, role)
  SELECT ch.channel_id, u.id, 'viewer'
  FROM (VALUES (v_ch_contas), (v_ch_fat_moto), (v_ch_emplacamento), (v_ch_fat_os), (v_ch_avisos)) ch(channel_id)
  CROSS JOIN public.users u
  WHERE ch.channel_id IS NOT NULL
    AND u.id <> v_owner_id
    AND COALESCE(u.is_active, TRUE) = TRUE
  ON CONFLICT ON CONSTRAINT channel_members_pkey DO NOTHING;

  IF p_reset_statuses THEN
    DELETE FROM public.workflow_status_config
    WHERE workflow_status_config.channel_id IN (v_ch_contas, v_ch_fat_moto, v_ch_emplacamento, v_ch_fat_os, v_ch_avisos);
  END IF;

  INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final) VALUES
    (v_ch_contas, 'Novo', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_contas, 'Em análise', 2, '#F59E0B', 'search', FALSE),
    (v_ch_contas, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_contas, 'Liberado para Pagamento', 4, '#06B6D4', 'payments', FALSE),
    (v_ch_contas, 'Pago', 5, '#059669', 'task_alt', TRUE),
    (v_ch_fat_moto, 'Solicitação criada', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_fat_moto, 'Em conferência', 2, '#F59E0B', 'search', FALSE),
    (v_ch_fat_moto, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_fat_moto, 'Liberado', 4, '#10B981', 'check_circle', FALSE),
    (v_ch_fat_moto, 'Pendente de ajuste', 5, '#F97316', 'warning', FALSE),
    (v_ch_fat_moto, 'Finalizado', 6, '#059669', 'task_alt', TRUE),
    (v_ch_emplacamento, 'Solicitação aberta', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_emplacamento, 'Documentação em análise', 2, '#F59E0B', 'fact_check', FALSE),
    (v_ch_emplacamento, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_emplacamento, 'Aguardando pagamento/taxa', 4, '#F43F5E', 'payments', FALSE),
    (v_ch_emplacamento, 'Em processamento', 5, '#6366F1', 'sync', FALSE),
    (v_ch_emplacamento, 'Pendência documental', 6, '#EF4444', 'error_outline', FALSE),
    (v_ch_emplacamento, 'Emplacado', 7, '#10B981', 'task_alt', TRUE),
    (v_ch_fat_os, 'Aberto', 1, '#3B82F6', 'add_circle', FALSE),
    (v_ch_fat_os, 'Em análise', 2, '#F59E0B', 'search', FALSE),
    (v_ch_fat_os, 'Aguardando Solicitante', 3, '#8B5CF6', 'hourglass_empty', FALSE),
    (v_ch_fat_os, 'Em faturamento', 4, '#6366F1', 'sync', FALSE),
    (v_ch_fat_os, 'Aguardando correção', 5, '#F97316', 'warning', FALSE),
    (v_ch_fat_os, 'Faturado', 6, '#10B981', 'task_alt', TRUE),
    (v_ch_avisos, 'Ativo', 1, '#3B82F6', 'publish', FALSE),
    (v_ch_avisos, 'Arquivado', 2, '#6B7280', 'archive', TRUE)
  ON CONFLICT ON CONSTRAINT workflow_status_config_channel_id_status_key DO UPDATE
  SET status_order = EXCLUDED.status_order,
      color = EXCLUDED.color,
      icon = EXCLUDED.icon,
      is_final = EXCLUDED.is_final;

  DELETE FROM public.chats
  WHERE type = 'channel'::chat_type
    AND name IN (SELECT name FROM pg_temp.base_workflow_channels);

  RETURN QUERY
  SELECT b.name, c.id
  FROM pg_temp.base_workflow_channels b
  JOIN public.channels c ON c.name = b.name
  ORDER BY b.name, c.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_operational_data(
  p_reseed_channels BOOLEAN DEFAULT TRUE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t TEXT;
  tables_to_truncate TEXT[] := ARRAY[
    'workflow_card_comments',
    'workflow_card_history',
    'workflow_status_config',
    'workflow_cards',
    'channel_messages',
    'channel_members',
    'channels',
    'message_actions',
    'message_reactions',
    'announcement_acks',
    'poll_votes',
    'message_read_status',
    'messages',
    'chat_members',
    'chats',
    'calls',
    'meeting_transcriptions',
    'meetings',
    'notifications',
    'user_notification_preferences',
    'support_ticket_messages',
    'support_tickets',
    'it_support_tickets',
    'user_activities',
    'user_activity_history',
    'user_locations',
    'fcm_tokens'
  ];
BEGIN
  IF p_reseed_channels
     AND NOT EXISTS (SELECT 1 FROM public.users WHERE COALESCE(is_active, TRUE) = TRUE) THEN
    RAISE EXCEPTION 'Reset cancelado: nenhum usuario ativo encontrado para recriar os canais base.';
  END IF;

  FOREACH t IN ARRAY tables_to_truncate LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = t
    ) THEN
      EXECUTE format('TRUNCATE TABLE public.%I CASCADE', t);
      RAISE NOTICE 'Truncated: %', t;
    END IF;
  END LOOP;

  IF p_reseed_channels THEN
    PERFORM public.seed_base_workflow_channels(TRUE, FALSE);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_workspace(TEXT, TEXT, JSONB, UUID[], JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_channel(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_channel(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_channel_member(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_channel_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_workflow_card(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_workflow_operators(UUID, TEXT, UUID[], UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seed_base_workflow_channels(BOOLEAN, BOOLEAN) TO service_role;
GRANT EXECUTE ON FUNCTION public.reset_operational_data(BOOLEAN) TO service_role;
