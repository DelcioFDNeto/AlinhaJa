-- ==============================================================================
-- Migration 009: Fix Announcement Stats
-- Corrige a contagem de confirmações excluindo o remetente do total.
-- ==============================================================================

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
          AND cm.user_id != v_sender_id -- <--- Correção: Exclui o remetente da contagem geral
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
            ) FILTER (WHERE last_read_at > v_msg_created_at),
            '[]'::jsonb
        ),
        COALESCE(
            jsonb_agg(
                jsonb_build_object('id', user_id, 'full_name', full_name, 'avatar_url', avatar_url)
            ) FILTER (WHERE last_read_at IS NULL OR last_read_at <= v_msg_created_at),
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
