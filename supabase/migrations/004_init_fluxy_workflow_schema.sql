-- CONSOLIDATED MIGRATIONS 032 to 039

-- Migration 027: RPC segura para alteração de role_level pelo Admin
-- ==============================================================================
-- Substitui o .update() direto que é bloqueado pelo RLS (auth.uid() = id)

CREATE OR REPLACE FUNCTION public.admin_update_user_role(
  p_target_user_id UUID,
  p_new_role TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller_role public.user_role_level;
BEGIN
  -- 1. Verifica se quem está chamando é TI Admin ou Diretor
  SELECT role_level INTO v_caller_role
  FROM public.users WHERE id = auth.uid();

  IF v_caller_role NOT IN ('ti_admin', 'director') THEN
    RAISE EXCEPTION 'Acesso Negado: Apenas TI Admin ou Diretores podem alterar níveis de acesso.';
  END IF;

  -- 2. Não permite alterar o próprio role
  IF auth.uid() = p_target_user_id THEN
    RAISE EXCEPTION 'Ação Inválida: Você não pode alterar seu próprio nível de acesso.';
  END IF;

  -- 3. Valida que o novo role é válido no enum
  IF p_new_role NOT IN ('staff', 'store_leader', 'supervisor', 'manager', 'director', 'ti_admin') THEN
    RAISE EXCEPTION 'Role inválido: %. Valores aceitos: staff, store_leader, supervisor, manager, director, ti_admin', p_new_role;
  END IF;

  -- 4. Atualiza o role_level do usuário alvo
  UPDATE public.users
  SET role_level = p_new_role::public.user_role_level
  WHERE id = p_target_user_id;

END;
$$;
-- ==============================================================================
-- Migration 033: Workflow - Sistema de Cards e Fluxos Operacionais
-- ==============================================================================
-- Evolui a estrutura de canais para suportar workflow operacional
-- Inspirado em Slack + Linear + Monday

-- ==============================================================================
-- 1. ENUMS
-- ==============================================================================

-- Enum para tipo de card/workflow
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'workflow_card_type') THEN
    CREATE TYPE workflow_card_type AS ENUM (
      'conta_pagar',      -- Liberação Contas a Pagar
      'fat_moto',         -- Liberação Fat Moto
      'emplacamento',     -- Emplacamento
      'faturamento_os',   -- Faturamento OS/Peças
      'aviso',            -- Avisos Gerais
      'generic'           -- Card genérico
    );
  END IF;
END $$;

-- Enum para prioridade
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'workflow_priority') THEN
    CREATE TYPE workflow_priority AS ENUM ('low', 'medium', 'high', 'urgent');
  END IF;
END $$;

-- Enum para status de aprovação
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'workflow_approval_status') THEN
    CREATE TYPE workflow_approval_status AS ENUM ('pending', 'approved', 'rejected');
  END IF;
END $$;

-- ==============================================================================
-- 2. TABELAS PRINCIPAIS
-- ==============================================================================

-- Tabela principal de cards/workflow
CREATE TABLE IF NOT EXISTS public.workflow_cards (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  channel_id            UUID NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
  card_type             workflow_card_type NOT NULL DEFAULT 'generic',
  title                 TEXT NOT NULL,
  description           TEXT,
  
  -- Campos específicos por tipo
  -- Conta a Pagar
  supplier              TEXT,
  expense_description   TEXT,
  amount                NUMERIC(15,2),
  due_date              DATE,
  cost_center           TEXT,
  
  -- Fat Moto
  client_name           TEXT,
  order_number          TEXT,
  ficha_number          TEXT,
  consultant            TEXT,
  
  -- Emplacamento
  client_cpf_cnpj       TEXT,
  vehicle_model         TEXT,
  chassis_number        TEXT,
  plate                 TEXT,
  
  -- Faturamento OS
  os_number             TEXT,
  budget_number         TEXT,
  billing_type          TEXT,
  items_details         TEXT,
  
  -- Campos comunes
  observations          TEXT,
  attachments           JSONB DEFAULT '[]',
  priority              workflow_priority DEFAULT 'medium',
  status                TEXT NOT NULL DEFAULT 'novo',
  assigned_to           UUID REFERENCES public.users(id),
  requested_by          UUID REFERENCES public.users(id),
  approved_by           UUID REFERENCES public.users(id),
  approval_status       workflow_approval_status DEFAULT 'pending',
  approval_date         TIMESTAMPTZ,
  approval_observations TEXT,
  
  -- Controle
  is_pinned             BOOLEAN DEFAULT FALSE,
  is_archived           BOOLEAN DEFAULT FALSE,
  metadata              JSONB DEFAULT '{}',
  
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index para performance
CREATE INDEX IF NOT EXISTS idx_workflow_cards_channel ON public.workflow_cards(channel_id);
CREATE INDEX IF NOT EXISTS idx_workflow_cards_status ON public.workflow_cards(status);
CREATE INDEX IF NOT EXISTS idx_workflow_cards_type ON public.workflow_cards(card_type);
CREATE INDEX IF NOT EXISTS idx_workflow_cards_assigned ON public.workflow_cards(assigned_to);
CREATE INDEX IF NOT EXISTS idx_workflow_cards_priority ON public.workflow_cards(priority);

-- Trigger para updated_at
DROP TRIGGER IF EXISTS workflow_cards_updated_at ON public.workflow_cards;
CREATE TRIGGER workflow_cards_updated_at
  BEFORE UPDATE ON public.workflow_cards
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ==============================================================================
-- 3. COMENTÁRIOS EM CARDS
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.workflow_card_comments (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id     UUID NOT NULL REFERENCES public.workflow_cards(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content     TEXT NOT NULL,
  attachments JSONB DEFAULT '[]',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wfc_comments_card ON public.workflow_card_comments(card_id);

DROP TRIGGER IF EXISTS wfc_comments_updated_at ON public.workflow_card_comments;
CREATE TRIGGER wfc_comments_updated_at
  BEFORE UPDATE ON public.workflow_card_comments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ==============================================================================
-- 4. HISTÓRICO/TIMELINE DE MOVIMENTAÇÕES
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.workflow_card_history (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id         UUID NOT NULL REFERENCES public.workflow_cards(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES public.users(id),
  action          TEXT NOT NULL,
  field_changed   TEXT,
  old_value       TEXT,
  new_value       TEXT,
  observations    TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wfc_history_card ON public.workflow_card_history(card_id);

-- ==============================================================================
-- 5. STATUS CONFIGURÁVEL POR CANAL
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.workflow_status_config (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  channel_id  UUID NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
  status      TEXT NOT NULL,
  status_order INTEGER NOT NULL,
  color       TEXT DEFAULT '#6B7280',
  icon        TEXT DEFAULT 'circle',
  is_final    BOOLEAN DEFAULT FALSE,
  UNIQUE(channel_id, status)
);

CREATE INDEX IF NOT EXISTS idx_wfs_config_channel ON public.workflow_status_config(channel_id);

-- ==============================================================================
-- 6. RODANDO STATUS PADRÃO PARA CADA CANAL
-- ==============================================================================

-- Status para Liberação Contas a Pagar
INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Novo', 1, '#3B82F6', 'add_circle', FALSE
FROM public.chats c WHERE c.name ILIKE '%Liberação Contas a Pagar%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Em análise', 2, '#F59E0B', 'pending', FALSE
FROM public.chats c WHERE c.name ILIKE '%Liberação Contas a Pagar%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Aguardando aprovação', 3, '#8B5CF6', 'hourglass_empty', FALSE
FROM public.chats c WHERE c.name ILIKE '%Liberação Contas a Pagar%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Aprovado', 4, '#10B981', 'check_circle', FALSE
FROM public.chats c WHERE c.name ILIKE '%Liberação Contas a Pagar%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Rejeitado', 5, '#EF4444', 'cancel', TRUE
FROM public.chats c WHERE c.name ILIKE '%Liberação Contas a Pagar%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Pago', 6, '#059669', 'payments', TRUE
FROM public.chats c WHERE c.name ILIKE '%Liberação Contas a Pagar%'
ON CONFLICT DO NOTHING;

-- Status para Liberação Fat Moto
INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Solicitação criada', 1, '#3B82F6', 'add_circle', FALSE
FROM public.chats c WHERE c.name ILIKE '%Liberação Fat Moto%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Em conferência', 2, '#F59E0B', 'search', FALSE
FROM public.chats c WHERE c.name ILIKE '%Liberação Fat Moto%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Aguardando liberação', 3, '#8B5CF6', 'hourglass_empty', FALSE
FROM public.chats c WHERE c.name ILIKE '%Liberação Fat Moto%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Liberado', 4, '#10B981', 'check_circle', FALSE
FROM public.chats c WHERE c.name ILIKE '%Liberação Fat Moto%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Pendente de ajuste', 5, '#F97316', 'warning', FALSE
FROM public.chats c WHERE c.name ILIKE '%Liberação Fat Moto%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Finalizado', 6, '#059669', 'task_alt', TRUE
FROM public.chats c WHERE c.name ILIKE '%Liberação Fat Moto%'
ON CONFLICT DO NOTHING;

-- Status para Emplacamento
INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Solicitação aberta', 1, '#3B82F6', 'add_circle', FALSE
FROM public.chats c WHERE c.name ILIKE '%Emplacamento%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Documentação em análise', 2, '#F59E0B', 'fact_check', FALSE
FROM public.chats c WHERE c.name ILIKE '%Emplacamento%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Aguardando pagamento/taxa', 3, '#8B5CF6', 'payments', FALSE
FROM public.chats c WHERE c.name ILIKE '%Emplacamento%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Em processamento', 4, '#6366F1', 'sync', FALSE
FROM public.chats c WHERE c.name ILIKE '%Emplacamento%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Emplacado', 5, '#10B981', 'check_circle', TRUE
FROM public.chats c WHERE c.name ILIKE '%Emplacamento%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Pendência documental', 6, '#EF4444', 'error_outline', FALSE
FROM public.chats c WHERE c.name ILIKE '%Emplacamento%'
ON CONFLICT DO NOTHING;

-- Status para Faturamento OS/Peças
INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Aberto', 1, '#3B82F6', 'add_circle', FALSE
FROM public.chats c WHERE c.name ILIKE '%Faturamento%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Em análise', 2, '#F59E0B', 'pending', FALSE
FROM public.chats c WHERE c.name ILIKE '%Faturamento%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Em faturamento', 3, '#6366F1', 'sync', FALSE
FROM public.chats c WHERE c.name ILIKE '%Faturamento%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Aguardando correção', 4, '#F97316', 'warning', FALSE
FROM public.chats c WHERE c.name ILIKE '%Faturamento%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Faturado', 5, '#10B981', 'check_circle', TRUE
FROM public.chats c WHERE c.name ILIKE '%Faturamento%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Cancelado', 6, '#EF4444', 'cancel', TRUE
FROM public.chats c WHERE c.name ILIKE '%Faturamento%'
ON CONFLICT DO NOTHING;

-- Status para Avisos Gerais
INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Ativo', 1, '#3B82F6', 'publish', FALSE
FROM public.chats c WHERE c.name ILIKE '%Avisos Gerais%'
ON CONFLICT DO NOTHING;

INSERT INTO public.workflow_status_config (channel_id, status, status_order, color, icon, is_final)
SELECT c.id, 'Arquivado', 2, '#6B7280', 'archive', TRUE
FROM public.chats c WHERE c.name ILIKE '%Avisos Gerais%'
ON CONFLICT DO NOTHING;

-- ==============================================================================
-- 7. RLS - POLICIES
-- ==============================================================================

ALTER TABLE public.workflow_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_card_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_card_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_status_config ENABLE ROW LEVEL SECURITY;

-- Workflow Cards: membros do canal podem ver
CREATE POLICY "Membros veem cards do canal"
  ON public.workflow_cards FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.chat_members cm
      WHERE cm.chat_id = channel_id AND cm.user_id = auth.uid()
    )
  );

-- Workflow Cards: membros podem inserir
CREATE POLICY "Membros criam cards no canal"
  ON public.workflow_cards FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.chat_members cm
      WHERE cm.chat_id = channel_id AND cm.user_id = auth.uid()
    )
  );

-- Workflow Cards: responsável ou admin pode atualizar
CREATE POLICY "Responsável atualiza cards"
  ON public.workflow_cards FOR UPDATE
  USING (
    assigned_to = auth.uid() OR
    requested_by = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.chat_members cm
      WHERE cm.chat_id = channel_id AND cm.user_id = auth.uid()
        AND cm.role IN ('owner', 'admin')
    )
  );

-- Comentários: membros podem ver e inserir
CREATE POLICY "Membros veem comentários"
  ON public.workflow_card_comments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.workflow_cards wc
      WHERE wc.id = card_id
      AND EXISTS (
        SELECT 1 FROM public.chat_members cm
        WHERE cm.chat_id = wc.channel_id AND cm.user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Membros inserem comentários"
  ON public.workflow_card_comments FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.workflow_cards wc
      WHERE wc.id = card_id
      AND EXISTS (
        SELECT 1 FROM public.chat_members cm
        WHERE cm.chat_id = wc.channel_id AND cm.user_id = auth.uid()
      )
    )
  );

-- Histórico: apenas leitura para membros
CREATE POLICY "Membros veem histórico"
  ON public.workflow_card_history FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.workflow_cards wc
      WHERE wc.id = card_id
      AND EXISTS (
        SELECT 1 FROM public.chat_members cm
        WHERE cm.chat_id = wc.channel_id AND cm.user_id = auth.uid()
      )
    )
  );

-- Status Config: membros leem, apenas admins modificam
CREATE POLICY "Membros leem config de status"
  ON public.workflow_status_config FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.chat_members cm
      WHERE cm.chat_id = channel_id AND cm.user_id = auth.uid()
    )
  );

CREATE POLICY "Admins gerenciam status config"
  ON public.workflow_status_config FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.chat_members cm
      WHERE cm.chat_id = channel_id AND cm.user_id = auth.uid()
        AND cm.role IN ('owner', 'admin')
    )
  );

-- ==============================================================================
-- 8. RPCS ÚTEIS
-- ==============================================================================

-- Criar card de workflow
CREATE OR REPLACE FUNCTION public.create_workflow_card(
  p_channel_id UUID,
  p_card_type workflow_card_type,
  p_title TEXT,
  p_description TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_card_id UUID;
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  
  INSERT INTO public.workflow_cards (
    channel_id, card_type, title, description, metadata, requested_by
  )
  VALUES (
    p_channel_id, p_card_type, p_title, p_description, p_metadata, v_user_id
  )
  RETURNING id INTO v_card_id;
  
  -- Registra no histórico
  INSERT INTO public.workflow_card_history (card_id, user_id, action, new_value)
  VALUES (v_card_id, v_user_id, 'Criação', 'Card criado');
  
  RETURN v_card_id;
END;
$$;

-- Atualizar status do card
CREATE OR REPLACE FUNCTION public.update_workflow_card_status(
  p_card_id UUID,
  p_new_status TEXT,
  p_observations TEXT DEFAULT NULL
)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_old_status TEXT;
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  
  SELECT status INTO v_old_status FROM public.workflow_cards WHERE id = p_card_id;
  
  UPDATE public.workflow_cards
  SET status = p_new_status, updated_at = NOW()
  WHERE id = p_card_id;
  
  INSERT INTO public.workflow_card_history (card_id, user_id, action, field_changed, old_value, new_value, observations)
  VALUES (p_card_id, v_user_id, 'Status alterado', 'status', v_old_status, p_new_status, p_observations);
  
  RETURN TRUE;
END;
$$;

-- Aprovar/Rejeitar card
CREATE OR REPLACE FUNCTION public.approve_workflow_card(
  p_card_id UUID,
  p_approve BOOLEAN,
  p_observations TEXT DEFAULT NULL
)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  
  UPDATE public.workflow_cards
  SET 
    approval_status = CASE WHEN p_approve THEN 'approved'::workflow_approval_status ELSE 'rejected'::workflow_approval_status END,
    approved_by = v_user_id,
    approval_date = NOW(),
    approval_observations = p_observations,
    updated_at = NOW()
  WHERE id = p_card_id;
  
  INSERT INTO public.workflow_card_history (card_id, user_id, action, new_value, observations)
  VALUES (
    p_card_id, v_user_id, 
    CASE WHEN p_approve THEN 'Aprovado' ELSE 'Rejeitado' END,
    CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
    p_observations
  );
  
  RETURN TRUE;
END;
$$;

-- Listar cards por canal com filtros
CREATE OR REPLACE FUNCTION public.get_workflow_cards(
  p_channel_id UUID,
  p_status TEXT DEFAULT NULL,
  p_priority TEXT DEFAULT NULL,
  p_assigned_to UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  card_type TEXT,
  status TEXT,
  priority TEXT,
  requested_by UUID,
  assigned_to UUID,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    wc.id, wc.title, wc.card_type::TEXT, wc.status, wc.priority::TEXT,
    wc.requested_by, wc.assigned_to, wc.created_at, wc.updated_at
  FROM public.workflow_cards wc
  WHERE wc.channel_id = p_channel_id
    AND wc.is_archived = FALSE
    AND (p_status IS NULL OR wc.status = p_status)
    AND (p_priority IS NULL OR wc.priority::TEXT = p_priority)
    AND (p_assigned_to IS NULL OR wc.assigned_to = p_assigned_to)
  ORDER BY wc.is_pinned DESC, wc.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ==============================================================================
-- 9. REALTIME
-- ==============================================================================

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'workflow_cards'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE workflow_cards;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'workflow_card_comments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE workflow_card_comments;
  END IF;
END $$;
-- ==============================================================================
-- Migration 036: RPCs para Gestão de Canais e Workflow (AlinhaJá)
-- ==============================================================================

-- ==============================================================================
-- 1. RPC: Exclusão Total de Canal (Channel + Messages + Members + Workflow)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.delete_channel(p_channel_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- 1. Remove workflow cards relacionados ao canal
  DELETE FROM public.workflow_card_comments
  WHERE card_id IN (SELECT id FROM public.workflow_cards WHERE channel_id = p_channel_id);
  
  DELETE FROM public.workflow_card_history
  WHERE card_id IN (SELECT id FROM public.workflow_cards WHERE channel_id = p_channel_id);
  
  DELETE FROM public.workflow_cards
  WHERE channel_id = p_channel_id;
  
  -- 2. Remove configuração de status do workflow
  DELETE FROM public.workflow_status_config
  WHERE channel_id = p_channel_id;
  
  -- 3. Remove mensagens do canal
  DELETE FROM public.messages
  WHERE chat_id = p_channel_id;
  
  -- 4. Remove membros do canal
  DELETE FROM public.chat_members
  WHERE chat_id = p_channel_id;
  
  -- 5. Remove o canal
  DELETE FROM public.chats
  WHERE id = p_channel_id;
  
  RAISE NOTICE 'Canal % excluído com sucesso', p_channel_id;
END;
$$;

-- ==============================================================================
-- 2. RPC: Arquivar Canal (Mantém dados, remove membros)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.archive_channel(p_channel_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Remove todos os membros exceto o owner
  DELETE FROM public.chat_members
  WHERE chat_id = p_channel_id
    AND role != 'owner';
  
  -- Atualiza metadata para marcar como arquivado
  UPDATE public.chats
  SET metadata = metadata || '{"archived": true, "archived_at": "' || NOW()::TEXT || '"}'::jsonb
  WHERE id = p_channel_id;
  
  RAISE NOTICE 'Canal % arquivado', p_channel_id;
END;
$$;

-- ==============================================================================
-- 3. RPC: Adicionar Membro ao Canal
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.add_channel_member(
  p_channel_id UUID,
  p_user_id UUID,
  p_role TEXT DEFAULT 'member'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.chat_members (chat_id, user_id, role)
  VALUES (p_channel_id, p_user_id, p_role)
  ON CONFLICT (chat_id, user_id) DO UPDATE
  SET role = EXCLUDED.role;
  
  RAISE NOTICE 'Usuário % adicionado ao canal % como %', p_user_id, p_channel_id, p_role;
END;
$$;

-- ==============================================================================
-- 4. RPC: Remover Membro do Canal
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.remove_channel_member(
  p_channel_id UUID,
  p_user_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.chat_members
  WHERE chat_id = p_channel_id AND user_id = p_user_id;
  
  RAISE NOTICE 'Usuário % removido do canal %', p_user_id, p_channel_id;
END;
$$;

-- ==============================================================================
-- 5. RPC: Atualizar Status do Workflow Card
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.update_workflow_status(
  p_card_id UUID,
  p_new_status TEXT,
  p_user_id UUID,
  p_observations TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_old_status TEXT;
BEGIN
  SELECT status INTO v_old_status FROM public.workflow_cards WHERE id = p_card_id;
  
  UPDATE public.workflow_cards
  SET 
    status = p_new_status,
    updated_at = NOW()
  WHERE id = p_card_id;
  
  INSERT INTO public.workflow_card_history (card_id, user_id, action, field_changed, old_value, new_value, observations)
  VALUES (p_card_id, p_user_id, 'Status alterado', 'status', v_old_status, p_new_status, p_observations);
  
  RAISE NOTICE 'Card % status alterado de % para %', p_card_id, v_old_status, p_new_status;
END;
$$;

-- ==============================================================================
-- 6. GRANT de permissões para as funções
-- ==============================================================================

GRANT EXECUTE ON FUNCTION public.delete_channel(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_channel(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_channel_member(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_channel_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_workflow_status(UUID, TEXT, UUID, TEXT) TO authenticated;

-- Verificar criação
SELECT 
  'delete_channel' as function_name,
  proname as name
FROM pg_proc
WHERE proname = 'delete_channel'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- ==============================================================================
-- Migration 038: Suporte ZIP no Storage + Ajustes Workflow
-- ==============================================================================
-- Adiciona MIME type application/zip ao bucket chat-media para permitir
-- upload de anexos comprimidos nos cards de workflow

-- 1. Adicionar application/zip e application/octet-stream ao bucket
UPDATE storage.buckets
SET allowed_mime_types = array_cat(
  allowed_mime_types,
  ARRAY['application/zip', 'application/x-zip-compressed', 'application/octet-stream']
)
WHERE id = 'chat-media'
  AND NOT ('application/zip' = ANY(allowed_mime_types));

-- 2. Aumentar file_size_limit para 50MB (ZIPs com múltiplos PDFs podem ser grandes)
UPDATE storage.buckets
SET file_size_limit = 52428800  -- 50 MB
WHERE id = 'chat-media';

-- ==============================================================================
-- FIX: Permitir que qualquer membro do canal atualize os cards (para que os Operadores possam assumir, arquivar e alterar status)
-- ==============================================================================

DROP POLICY IF EXISTS "Responsável atualiza cards" ON public.workflow_cards;

CREATE POLICY "Membros atualizam cards"
  ON public.workflow_cards FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.chat_members cm
      WHERE cm.chat_id = channel_id AND cm.user_id = auth.uid()
    )
  );

