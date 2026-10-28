-- ============================================================
-- 021: Threads e Bots
-- Adiciona suporte a sub-conversas (threads) e mensagens de bot
-- na tabela messages, e cria o usuário-bot do sistema.
-- ============================================================

-- 1. Adicionar colunas na tabela messages
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS thread_id UUID REFERENCES public.messages(id);
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_bot BOOLEAN DEFAULT false;

-- Índice parcial para buscar replies de uma thread rapidamente
CREATE INDEX IF NOT EXISTS idx_messages_thread
  ON public.messages(thread_id, created_at ASC)
  WHERE thread_id IS NOT NULL;

-- 1.5. Garantir que as colunas necessárias pelo trigger 'handle_new_user' existam
-- (Caso alguma migration anterior como a 007 ou 015 tenha sido pulada)
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS department TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS cpf TEXT;

-- 2. Criar o usuário-bot do sistema
-- Inserir na tabela auth.users para satisfazer a foreign key
-- A trigger `handle_new_user` do banco fará o insert automático no public.users.
INSERT INTO auth.users (
  id, 
  instance_id, 
  aud, 
  role, 
  email, 
  encrypted_password, 
  email_confirmed_at, 
  raw_user_meta_data, 
  created_at, 
  updated_at
)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'bot@bysabel.com.br',
  crypt('bot_bysabel_password_123!!', gen_salt('bf')),
  now(),
  '{"full_name": "BySabel Bot"}'::jsonb,
  now(),
  now()
)
ON CONFLICT (id) DO NOTHING;

-- Atualizar/Inserir dados complementares do bot no schema public.users
INSERT INTO public.users (id, full_name, avatar_url, job_function, role_level)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'BySabel Bot',
  NULL,
  'Sistema Automatizado',
  'staff'
)
ON CONFLICT (id) DO UPDATE SET 
  full_name = EXCLUDED.full_name,
  job_function = EXCLUDED.job_function,
  role_level = EXCLUDED.role_level;

-- 3. Atualizar RPC get_chats_with_preview para excluir threads
-- Mensagens em threads NÃO devem aparecer como last_message nem contar como unread
CREATE OR REPLACE FUNCTION get_chats_with_preview()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t)) INTO v_result
  FROM (
    SELECT
      c.id,
      c.type,
      c.name,
      c.description,
      c.avatar_url,
      c.created_by,
      c.metadata,
      c.created_at,
      cm.last_read_at,
      cm.is_pinned,
      -- Última mensagem (excluindo threads)
      (
        SELECT row_to_json(lm)
        FROM (
          SELECT m.id, m.sender_id, m.content, m.content_type,
                 m.media_url, m.created_at, m.is_bot
          FROM messages m
          WHERE m.chat_id = c.id
            AND m.deleted_at IS NULL
            AND m.thread_id IS NULL  -- Exclui mensagens de thread
          ORDER BY m.created_at DESC
          LIMIT 1
        ) lm
      ) AS last_message,
      -- Contagem de não-lidas (excluindo threads)
      (
        SELECT COUNT(*)::int
        FROM messages m
        WHERE m.chat_id = c.id
          AND m.deleted_at IS NULL
          AND m.thread_id IS NULL  -- Exclui mensagens de thread
          AND m.sender_id != v_user_id
          AND m.created_at > cm.last_read_at
      ) AS unread_count,
      -- Outro usuário (para DMs)
      CASE WHEN c.type = 'direct' THEN (
        SELECT row_to_json(ou)
        FROM (
          SELECT u.id, u.full_name, u.avatar_url, u.is_online,
                 u.last_seen_at, u.role_level, u.job_function,
                 b.name AS branch_name
          FROM chat_members cm2
          JOIN users u ON u.id = cm2.user_id
          LEFT JOIN branches b ON b.id = u.branch_id
          WHERE cm2.chat_id = c.id AND cm2.user_id != v_user_id
          LIMIT 1
        ) ou
      ) ELSE NULL END AS other_user
    FROM chat_members cm
    JOIN chats c ON c.id = cm.chat_id
    WHERE cm.user_id = v_user_id
    ORDER BY cm.is_pinned DESC, (
      SELECT m2.created_at FROM messages m2
      WHERE m2.chat_id = c.id AND m2.deleted_at IS NULL AND m2.thread_id IS NULL
      ORDER BY m2.created_at DESC LIMIT 1
    ) DESC NULLS LAST
  ) t;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;
