-- CONSOLIDATED MIGRATIONS 045 to 048

-- ============================================================
-- Migration 045: FIX CRÍTICO — Trigger handle_new_user
-- PROBLEMA: Usuários auto-cadastrados entravam sem aprovação TI.
-- CAUSA: 1) Trigger desatualizado no banco, 2) coluna is_active DEFAULT true
-- SOLUÇÃO: Recriar trigger com is_active=false + banned_until + dados completos
-- ============================================================

-- 1. Coluna is_active DEFAULT deve ser FALSE (segurança: ninguém nasce ativo)
ALTER TABLE public.users ALTER COLUMN is_active SET DEFAULT false;

-- 2. Recriar a trigger COMPLETA (copia dados do metadata corretamente)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_role user_role_level := 'staff';
  v_is_active BOOLEAN := false;  -- SEMPRE inativo por padrão
  v_branch_id UUID := NULL;
  v_job_function TEXT := NULL;
  v_phone TEXT := NULL;
  v_department TEXT := NULL;
  v_cpf TEXT := NULL;
  v_sexo TEXT := NULL;
  v_data_nascimento DATE := NULL;
  v_branch_str TEXT;
  v_dn_str TEXT;
BEGIN
  -- Extrair metadados do signup (raw_user_meta_data)
  v_branch_str := NEW.raw_user_meta_data ->> 'branch_id';
  IF v_branch_str IS NOT NULL AND v_branch_str != '' THEN
    BEGIN
      v_branch_id := v_branch_str::UUID;
    EXCEPTION WHEN invalid_text_representation THEN
      -- Se branch_id não for UUID válido (ex: fallback string), tenta buscar pelo nome
      SELECT id INTO v_branch_id FROM public.branches WHERE name = v_branch_str LIMIT 1;
    END;
  END IF;

  v_job_function := NEW.raw_user_meta_data ->> 'job_function';
  v_phone := NEW.raw_user_meta_data ->> 'phone';
  v_department := NEW.raw_user_meta_data ->> 'department';
  v_cpf := NEW.raw_user_meta_data ->> 'cpf';
  v_sexo := NEW.raw_user_meta_data ->> 'sexo';

  v_dn_str := NEW.raw_user_meta_data ->> 'data_nascimento';
  IF v_dn_str IS NOT NULL AND v_dn_str != '' THEN
    BEGIN
      v_data_nascimento := v_dn_str::DATE;
    EXCEPTION WHEN invalid_datetime_format THEN
      v_data_nascimento := NULL;
    END;
  END IF;

  INSERT INTO public.users (
    id,
    full_name,
    avatar_url,
    role_level,
    is_active,
    branch_id,
    job_function,
    phone,
    department,
    cpf,
    sexo,
    data_nascimento,
    email
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
    v_role,
    v_is_active,
    v_branch_id,
    v_job_function,
    v_phone,
    v_department,
    v_cpf,
    v_sexo,
    v_data_nascimento,
    NEW.email
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.users.full_name),
    branch_id = COALESCE(EXCLUDED.branch_id, public.users.branch_id),
    job_function = COALESCE(EXCLUDED.job_function, public.users.job_function),
    phone = COALESCE(EXCLUDED.phone, public.users.phone),
    department = COALESCE(EXCLUDED.department, public.users.department),
    cpf = COALESCE(EXCLUDED.cpf, public.users.cpf),
    sexo = COALESCE(EXCLUDED.sexo, public.users.sexo),
    data_nascimento = COALESCE(EXCLUDED.data_nascimento, public.users.data_nascimento),
    email = COALESCE(EXCLUDED.email, public.users.email);

  -- CRÍTICO: Se o cadastro não é o admin master, BANE o usuário até aprovação.
  IF v_is_active = false THEN
    UPDATE auth.users SET banned_until = '3000-01-01 00:00:00+00' WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- 3. Garantir que o trigger existe (idempotente)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 4. Permitir leitura de branches para usuários NÃO autenticados (necessário no signup)
-- Apenas SELECT, sem mutação
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'branches' AND policyname = 'branches_public_read'
  ) THEN
    CREATE POLICY branches_public_read ON public.branches
      FOR SELECT USING (true);
  END IF;
END $$;

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
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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

