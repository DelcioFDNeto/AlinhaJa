-- ============================================================
-- Correção get_announcement_stats: suporte híbrido (canais + chats) e checagem de channel_message_id
--
-- PROBLEMA
-- 1. get_announcement_stats buscava confirmações apenas com `ma.message_id = p_message_id`.
--    Para mensagens de canal, a chave estrangeira em message_actions é `channel_message_id`.
--    Como resultado, `ack_at` era sempre NULL em canais, fazendo o painel exibir
--    "0 confirmaram" e colocar todo usuário em "Pendentes", duplicando nomes no painel.
-- 2. get_announcement_stats funcionava apenas para `channel_messages`, retornando vazio
--    quando invocado para um anúncio em chat 1:1 ou grupo (`messages`).
--
-- SOLUÇÃO
-- 1. Tornar get_announcement_stats híbrido: checa `channel_messages` e depois `messages`.
-- 2. Checar `(ma.channel_message_id = p_message_id OR ma.message_id = p_message_id)` nas confirmações.
-- 3. Classificar corretamente visualizações (`last_read_at >= v_msg_created_at OR ack_at IS NOT NULL`).
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_announcement_stats(p_message_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_channel_id UUID;
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
    -- 1. Busca em channel_messages primeiro
    SELECT channel_id, sender_id, created_at
    INTO v_channel_id, v_sender_id, v_msg_created_at
    FROM public.channel_messages
    WHERE id = p_message_id;

    -- 2. Se não for mensagem de canal, busca em messages (DMs/Grupos)
    IF NOT FOUND THEN
        SELECT chat_id, sender_id, created_at
        INTO v_chat_id, v_sender_id, v_msg_created_at
        FROM public.messages
        WHERE id = p_message_id;
    END IF;

    IF v_channel_id IS NULL AND v_chat_id IS NULL THEN
        RETURN '{}'::jsonb;
    END IF;

    IF v_channel_id IS NOT NULL THEN
        -- CANAL: busca membros em channel_members
        WITH member_info AS (
            SELECT 
                cm.user_id,
                cm.last_read_at,
                u.full_name,
                u.avatar_url,
                (
                    SELECT ma.created_at 
                    FROM public.message_actions ma 
                    WHERE (ma.channel_message_id = p_message_id OR ma.message_id = p_message_id)
                      AND ma.user_id = cm.user_id 
                      AND ma.action_type = 'acknowledge' 
                    LIMIT 1
                ) AS ack_at
            FROM public.channel_members cm
            JOIN public.users u ON u.id = cm.user_id
            WHERE cm.channel_id = v_channel_id
              AND cm.user_id != v_sender_id
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
                ) FILTER (WHERE ack_at IS NULL),
                '[]'::jsonb
            ),
            COALESCE(
                jsonb_agg(
                    jsonb_build_object('id', user_id, 'full_name', full_name, 'avatar_url', avatar_url)
                ) FILTER (WHERE last_read_at >= v_msg_created_at OR ack_at IS NOT NULL),
                '[]'::jsonb
            ),
            COALESCE(
                jsonb_agg(
                    jsonb_build_object('id', user_id, 'full_name', full_name, 'avatar_url', avatar_url)
                ) FILTER (WHERE (last_read_at IS NULL OR last_read_at < v_msg_created_at) AND ack_at IS NULL),
                '[]'::jsonb
            )
        INTO v_total, v_acknowledged, v_pending, v_acknowledged_users, v_pending_users, v_viewed_users, v_not_viewed_users
        FROM member_info;

    ELSE
        -- CHAT (1:1 / Grupo): busca membros em chat_members
        WITH member_info AS (
            SELECT 
                cm.user_id,
                cm.last_read_at,
                u.full_name,
                u.avatar_url,
                (
                    SELECT ma.created_at 
                    FROM public.message_actions ma 
                    WHERE (ma.message_id = p_message_id OR ma.channel_message_id = p_message_id)
                      AND ma.user_id = cm.user_id 
                      AND ma.action_type = 'acknowledge' 
                    LIMIT 1
                ) AS ack_at
            FROM public.chat_members cm
            JOIN public.users u ON u.id = cm.user_id
            WHERE cm.chat_id = v_chat_id
              AND cm.user_id != v_sender_id
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
                ) FILTER (WHERE ack_at IS NULL),
                '[]'::jsonb
            ),
            COALESCE(
                jsonb_agg(
                    jsonb_build_object('id', user_id, 'full_name', full_name, 'avatar_url', avatar_url)
                ) FILTER (WHERE last_read_at >= v_msg_created_at OR ack_at IS NOT NULL),
                '[]'::jsonb
            ),
            COALESCE(
                jsonb_agg(
                    jsonb_build_object('id', user_id, 'full_name', full_name, 'avatar_url', avatar_url)
                ) FILTER (WHERE (last_read_at IS NULL OR last_read_at < v_msg_created_at) AND ack_at IS NULL),
                '[]'::jsonb
            )
        INTO v_total, v_acknowledged, v_pending, v_acknowledged_users, v_pending_users, v_viewed_users, v_not_viewed_users
        FROM member_info;
    END IF;

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
