-- ==============================================================================
-- Migration 048: Create Message Actions and Stats RPC
-- ==============================================================================
-- 1. Cria a tabela genérica `message_actions` para armazenar confirmações e votos,
--    substituindo a antiga `message_acknowledgements` que limitava as ações.
-- 2. Define chaves estrangeiras com ON DELETE CASCADE.
-- 3. Cria uma função RPC otimizada para o Dashboard de Anúncios.
-- ==============================================================================

-- Remover a tabela antiga (cuidado, limpará dados de teste de acks se existirem)
DROP TABLE IF EXISTS public.message_acknowledgements CASCADE;

-- 1. Criar Tabela `message_actions`
CREATE TABLE IF NOT EXISTS public.message_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL, -- Ex: 'acknowledge', 'poll_vote'
    action_value TEXT,         -- Ex: 'confirmed', ou texto do voto na enquete
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Restringe à apenas 1 ação de um dado tipo por usuário por mensagem
    UNIQUE (message_id, user_id, action_type)
);

CREATE INDEX IF NOT EXISTS idx_msg_actions_message ON public.message_actions(message_id);
CREATE INDEX IF NOT EXISTS idx_msg_actions_user    ON public.message_actions(user_id);
CREATE INDEX IF NOT EXISTS idx_msg_actions_type    ON public.message_actions(action_type);

-- RLS para message_actions
ALTER TABLE public.message_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Usuários veem ações das mensagens que tem acesso"
  ON public.message_actions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = message_actions.message_id
        AND public.is_chat_member(m.chat_id)
    )
  );

CREATE POLICY "Usuários criam suas próprias ações"
  ON public.message_actions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Usuários alteram suas próprias ações"
  ON public.message_actions FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Usuários excluem suas próprias ações (toggle)"
  ON public.message_actions FOR DELETE
  USING (auth.uid() = user_id);

-- 2. Criar RPC Otimizada `get_announcement_stats`
-- Puxa dados mastigados de visualização/confirmação
CREATE OR REPLACE FUNCTION public.get_announcement_stats(p_message_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_chat_id UUID;
    v_sender_id UUID;
    v_msg_created_at TIMESTAMPTZ;
    v_total INT := 0;
    v_acknowledged INT := 0;
    v_pending INT := 0;
    v_viewed_count INT := 0;
    
    v_acknowledged_users JSONB := '[]'::jsonb;
    v_pending_users JSONB := '[]'::jsonb;
    v_viewed_users JSONB := '[]'::jsonb;
    v_not_viewed_users JSONB := '[]'::jsonb;
BEGIN
    -- Pegar info base da mensagem
    SELECT chat_id, sender_id, created_at
    INTO v_chat_id, v_sender_id, v_msg_created_at
    FROM public.messages
    WHERE id = p_message_id;

    IF NOT FOUND THEN
        RETURN '{}'::jsonb;
    END IF;

    -- Popular Arrays Agregados em uma única query massiva
    WITH member_info AS (
        SELECT 
            cm.user_id,
            cm.last_read_at,
            u.full_name,
            u.avatar_url,
            (SELECT created_at FROM public.message_actions ma WHERE ma.message_id = p_message_id AND ma.user_id = cm.user_id AND ma.action_type = 'acknowledge') as ack_at
        FROM public.chat_members cm
        JOIN public.users u ON u.id = cm.user_id
        WHERE cm.chat_id = v_chat_id
    )
    SELECT
        COUNT(*),
        COUNT(ack_at),
        COUNT(*) - COUNT(ack_at),
        COALESCE(
            jsonb_agg(
                jsonb_build_object('id', user_id, 'full_name', full_name, 'avatar_url', avatar_url, 'acknowledged_at', ack_at)
            ) FILTER (WHERE ack_at IS NOT NULL),
            '[]'::jsonb
        ),
        COALESCE(
            jsonb_agg(
                jsonb_build_object('id', user_id, 'full_name', full_name, 'avatar_url', avatar_url)
            ) FILTER (WHERE ack_at IS NULL AND user_id != v_sender_id),
            '[]'::jsonb
        ),
        COALESCE(
            jsonb_agg(
                jsonb_build_object('id', user_id, 'full_name', full_name, 'avatar_url', avatar_url)
            ) FILTER (WHERE last_read_at > v_msg_created_at),
            '[]'::jsonb
        ),
        COALESCE(
            jsonb_agg(
                jsonb_build_object('id', user_id, 'full_name', full_name, 'avatar_url', avatar_url)
            ) FILTER (WHERE (last_read_at IS NULL OR last_read_at <= v_msg_created_at) AND user_id != v_sender_id),
            '[]'::jsonb
        )
    INTO v_total, v_acknowledged, v_pending, v_acknowledged_users, v_pending_users, v_viewed_users, v_not_viewed_users
    FROM member_info;

    -- Obter viewed_count total
    v_viewed_count := jsonb_array_length(v_viewed_users);

    RETURN jsonb_build_object(
        'total', v_total,
        'acknowledged', v_acknowledged,
        'pending', v_pending,
        'acknowledged_users', v_acknowledged_users,
        'pending_users', v_pending_users,
        'viewed_users', v_viewed_users,
        'not_viewed_users', v_not_viewed_users,
        'viewed_count', v_viewed_count,
        'is_sender', (v_sender_id = auth.uid())
    );
END;
$$;
