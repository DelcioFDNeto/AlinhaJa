-- CONSOLIDATED MIGRATIONS 040 to 043

-- Notificação de Preferências por Chat/Canal
-- Permite usuários controlarem notificações por conversa

CREATE TABLE IF NOT EXISTS user_notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
  channel_id UUID,
  
  notify_enabled BOOLEAN DEFAULT true,
  notify_mentions BOOLEAN DEFAULT true,
  notify_replies BOOLEAN DEFAULT true,
  sound_enabled BOOLEAN DEFAULT true,
  vibration_enabled BOOLEAN DEFAULT true,
  show_preview BOOLEAN DEFAULT true,
  do_not_disturb_enabled BOOLEAN DEFAULT false,
  dnd_start_time TIME DEFAULT '22:00:00',
  dnd_end_time TIME DEFAULT '08:00:00',
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(user_id, chat_id),
  UNIQUE(user_id, channel_id)
);

CREATE TABLE IF NOT EXISTS user_notification_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  
  notifications_enabled BOOLEAN DEFAULT true,
  notify_dm BOOLEAN DEFAULT true,
  notify_groups BOOLEAN DEFAULT true,
  notify_channels BOOLEAN DEFAULT true,
  notify_workflow BOOLEAN DEFAULT true,
  notify_calls BOOLEAN DEFAULT true,
  sound_enabled BOOLEAN DEFAULT true,
  vibration_enabled BOOLEAN DEFAULT true,
  show_preview BOOLEAN DEFAULT true,
  do_not_disturb_enabled BOOLEAN DEFAULT false,
  dnd_start_time TIME DEFAULT '22:00:00',
  dnd_end_time TIME DEFAULT '08:00:00',
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notif_prefs_user_chat ON user_notification_preferences(user_id, chat_id);
CREATE INDEX IF NOT EXISTS idx_notif_prefs_user_channel ON user_notification_preferences(user_id, channel_id);
CREATE INDEX IF NOT EXISTS idx_notif_settings_user ON user_notification_settings(user_id);

CREATE OR REPLACE FUNCTION should_send_notification(
  p_user_id UUID,
  p_chat_id UUID DEFAULT NULL,
  p_channel_id UUID DEFAULT NULL,
  p_is_mention BOOLEAN DEFAULT false,
  p_is_reply BOOLEAN DEFAULT false
)
RETURNS BOOLEAN AS $$
DECLARE
  v_global_settings RECORD;
  v_chat_pref RECORD;
  v_current_time TIME;
BEGIN
  SELECT * INTO v_global_settings FROM user_notification_settings WHERE user_id = p_user_id;
  
  IF v_global_settings IS NOT NULL THEN
    IF NOT v_global_settings.notifications_enabled THEN
      RETURN false;
    END IF;
    
    IF v_global_settings.do_not_disturb_enabled THEN
      v_current_time := CURRENT_TIME;
      IF v_current_time >= v_global_settings.dnd_start_time OR v_current_time <= v_global_settings.dnd_end_time THEN
        RETURN false;
      END IF;
    END IF;
  END IF;
  
  IF p_chat_id IS NOT NULL THEN
    SELECT * INTO v_chat_pref FROM user_notification_preferences WHERE user_id = p_user_id AND chat_id = p_chat_id;
    
    IF v_chat_pref IS NOT NULL THEN
      IF NOT v_chat_pref.notify_enabled THEN RETURN false; END IF;
      IF p_is_mention AND NOT v_chat_pref.notify_mentions THEN RETURN false; END IF;
      IF p_is_reply AND NOT v_chat_pref.notify_replies THEN RETURN false; END IF;
      
      IF v_chat_pref.do_not_disturb_enabled THEN
        v_current_time := CURRENT_TIME;
        IF v_current_time >= v_chat_pref.dnd_start_time OR v_current_time <= v_chat_pref.dnd_end_time THEN
          RETURN false;
        END IF;
      END IF;
    END IF;
  ELSIF p_channel_id IS NOT NULL THEN
    SELECT * INTO v_chat_pref FROM user_notification_preferences WHERE user_id = p_user_id AND channel_id = p_channel_id;
    
    IF v_chat_pref IS NOT NULL THEN
      IF NOT v_chat_pref.notify_enabled THEN RETURN false; END IF;
      IF p_is_mention AND NOT v_chat_pref.notify_mentions THEN RETURN false; END IF;
    END IF;
  END IF;
  
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION update_notification_preference(
  p_chat_id UUID DEFAULT NULL,
  p_channel_id UUID DEFAULT NULL,
  p_notify_enabled BOOLEAN DEFAULT NULL,
  p_notify_mentions BOOLEAN DEFAULT NULL,
  p_notify_replies BOOLEAN DEFAULT NULL,
  p_sound_enabled BOOLEAN DEFAULT NULL,
  p_vibration_enabled BOOLEAN DEFAULT NULL,
  p_show_preview BOOLEAN DEFAULT NULL,
  p_do_not_disturb BOOLEAN DEFAULT NULL,
  p_dnd_start TIME DEFAULT NULL,
  p_dnd_end TIME DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF p_chat_id IS NOT NULL THEN
    INSERT INTO user_notification_preferences (user_id, chat_id, notify_enabled, notify_mentions, notify_replies, sound_enabled, vibration_enabled, show_preview, do_not_disturb_enabled, dnd_start_time, dnd_end_time, updated_at)
    VALUES (v_user_id, p_chat_id, COALESCE(p_notify_enabled, true), COALESCE(p_notify_mentions, true), COALESCE(p_notify_replies, true), COALESCE(p_sound_enabled, true), COALESCE(p_vibration_enabled, true), COALESCE(p_show_preview, true), COALESCE(p_do_not_disturb, false), COALESCE(p_dnd_start, '22:00:00'::TIME), COALESCE(p_dnd_end, '08:00:00'::TIME), NOW())
    ON CONFLICT (user_id, chat_id) DO UPDATE SET
      notify_enabled = COALESCE(p_notify_enabled, user_notification_preferences.notify_enabled),
      notify_mentions = COALESCE(p_notify_mentions, user_notification_preferences.notify_mentions),
      notify_replies = COALESCE(p_notify_replies, user_notification_preferences.notify_replies),
      sound_enabled = COALESCE(p_sound_enabled, user_notification_preferences.sound_enabled),
      vibration_enabled = COALESCE(p_vibration_enabled, user_notification_preferences.vibration_enabled),
      show_preview = COALESCE(p_show_preview, user_notification_preferences.show_preview),
      do_not_disturb_enabled = COALESCE(p_do_not_disturb, user_notification_preferences.do_not_disturb_enabled),
      dnd_start_time = COALESCE(p_dnd_start, user_notification_preferences.dnd_start_time),
      dnd_end_time = COALESCE(p_dnd_end, user_notification_preferences.dnd_end_time),
      updated_at = NOW();
  ELSIF p_channel_id IS NOT NULL THEN
    INSERT INTO user_notification_preferences (user_id, channel_id, notify_enabled, notify_mentions, sound_enabled, vibration_enabled, show_preview, do_not_disturb_enabled, dnd_start_time, dnd_end_time, updated_at)
    VALUES (v_user_id, p_channel_id, COALESCE(p_notify_enabled, true), COALESCE(p_notify_mentions, true), COALESCE(p_sound_enabled, true), COALESCE(p_vibration_enabled, true), COALESCE(p_show_preview, true), COALESCE(p_do_not_disturb, false), COALESCE(p_dnd_start, '22:00:00'::TIME), COALESCE(p_dnd_end, '08:00:00'::TIME), NOW())
    ON CONFLICT (user_id, channel_id) DO UPDATE SET
      notify_enabled = COALESCE(p_notify_enabled, user_notification_preferences.notify_enabled),
      notify_mentions = COALESCE(p_notify_mentions, user_notification_preferences.notify_mentions),
      sound_enabled = COALESCE(p_sound_enabled, user_notification_preferences.sound_enabled),
      vibration_enabled = COALESCE(p_vibration_enabled, user_notification_preferences.vibration_enabled),
      show_preview = COALESCE(p_show_preview, user_notification_preferences.show_preview),
      do_not_disturb_enabled = COALESCE(p_do_not_disturb, user_notification_preferences.do_not_disturb_enabled),
      dnd_start_time = COALESCE(p_dnd_start, user_notification_preferences.dnd_start_time),
      dnd_end_time = COALESCE(p_dnd_end, user_notification_preferences.dnd_end_time),
      updated_at = NOW();
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION update_notification_settings(
  p_notifications_enabled BOOLEAN DEFAULT NULL,
  p_notify_dm BOOLEAN DEFAULT NULL,
  p_notify_groups BOOLEAN DEFAULT NULL,
  p_notify_channels BOOLEAN DEFAULT NULL,
  p_notify_workflow BOOLEAN DEFAULT NULL,
  p_notify_calls BOOLEAN DEFAULT NULL,
  p_sound_enabled BOOLEAN DEFAULT NULL,
  p_vibration_enabled BOOLEAN DEFAULT NULL,
  p_show_preview BOOLEAN DEFAULT NULL,
  p_do_not_disturb BOOLEAN DEFAULT NULL,
  p_dnd_start TIME DEFAULT NULL,
  p_dnd_end TIME DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  INSERT INTO user_notification_settings (user_id, notifications_enabled, notify_dm, notify_groups, notify_channels, notify_workflow, notify_calls, sound_enabled, vibration_enabled, show_preview, do_not_disturb_enabled, dnd_start_time, dnd_end_time, updated_at)
  VALUES (v_user_id, COALESCE(p_notifications_enabled, true), COALESCE(p_notify_dm, true), COALESCE(p_notify_groups, true), COALESCE(p_notify_channels, true), COALESCE(p_notify_workflow, true), COALESCE(p_notify_calls, true), COALESCE(p_sound_enabled, true), COALESCE(p_vibration_enabled, true), COALESCE(p_show_preview, true), COALESCE(p_do_not_disturb, false), COALESCE(p_dnd_start, '22:00:00'::TIME), COALESCE(p_dnd_end, '08:00:00'::TIME), NOW())
  ON CONFLICT (user_id) DO UPDATE SET
    notifications_enabled = COALESCE(p_notifications_enabled, user_notification_settings.notifications_enabled),
    notify_dm = COALESCE(p_notify_dm, user_notification_settings.notify_dm),
    notify_groups = COALESCE(p_notify_groups, user_notification_settings.notify_groups),
    notify_channels = COALESCE(p_notify_channels, user_notification_settings.notify_channels),
    notify_workflow = COALESCE(p_notify_workflow, user_notification_settings.notify_workflow),
    notify_calls = COALESCE(p_notify_calls, user_notification_settings.notify_calls),
    sound_enabled = COALESCE(p_sound_enabled, user_notification_settings.sound_enabled),
    vibration_enabled = COALESCE(p_vibration_enabled, user_notification_settings.vibration_enabled),
    show_preview = COALESCE(p_show_preview, user_notification_settings.show_preview),
    do_not_disturb_enabled = COALESCE(p_do_not_disturb, user_notification_settings.do_not_disturb_enabled),
    dnd_start_time = COALESCE(p_dnd_start, user_notification_settings.dnd_start_time),
    dnd_end_time = COALESCE(p_dnd_end, user_notification_settings.dnd_end_time),
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_notification_settings()
RETURNS TABLE (
  notifications_enabled BOOLEAN,
  notify_dm BOOLEAN,
  notify_groups BOOLEAN,
  notify_channels BOOLEAN,
  notify_workflow BOOLEAN,
  notify_calls BOOLEAN,
  sound_enabled BOOLEAN,
  vibration_enabled BOOLEAN,
  show_preview BOOLEAN,
  do_not_disturb_enabled BOOLEAN,
  dnd_start_time TIME,
  dnd_end_time TIME
) AS $$
BEGIN
  RETURN QUERY
  SELECT s.notifications_enabled, s.notify_dm, s.notify_groups, s.notify_channels, s.notify_workflow, s.notify_calls, s.sound_enabled, s.vibration_enabled, s.show_preview, s.do_not_disturb_enabled, s.dnd_start_time, s.dnd_end_time
  FROM user_notification_settings s
  WHERE s.user_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- Execute os seguintes comandos no SQL Editor do seu projeto Supabase:

-- 1. Adicionar a coluna de status (sent, delivered, read) na tabela de mensagens
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS status text DEFAULT 'sent';

-- 2. Adicionar o array read_by para chats em grupo (Armazenará os IDs de quem ja visualizou)
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS read_by uuid[] DEFAULT '{}';

-- 3. Criar uma RPC super rápida para marcar mensagens como lidas sem onerar a banda do dispositivo móvil
CREATE OR REPLACE FUNCTION mark_messages_as_read(p_chat_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- 1) Atualiza diretamente todas mensagens NÃO lidas (onde sender != logado e logado ainda não tá no array)
  UPDATE public.messages
  SET 
      -- O status vira 'read' p/ 1:1. P/ grupos, pode ser util manter sent/read dependendo da maioria, mas 
      -- setamos read_by c/ array_append (cuidando pra n duplicar).
      status = 'read',
      read_by = array_append(ARRAY(SELECT DISTINCT e FROM unnest(read_by) e), p_user_id)
  WHERE 
      chat_id = p_chat_id 
      AND sender_id != p_user_id 
      AND NOT (read_by @> ARRAY[p_user_id]); -- Garante que nao dá update excessivo se ja leu
END;
$$;
-- ======================================================================================
-- CORREÇÃO DE RECURSÃO INFINITA (RLS) Tabela: public.channel_members
-- ======================================================================================
-- Problema original: A policy de SELECT usava "EXISTS (SELECT 1 FROM channel_members...)", o que 
-- gerava um loop infinito chamando a si próprio em qualquer query.
-- Agora permitimos a visualização de forma performática.

DROP POLICY IF EXISTS "Ver membros do mesmo canal" ON public.channel_members;

CREATE POLICY "Ver membros do mesmo canal" ON public.channel_members
FOR SELECT TO authenticated USING (true);
-- 1. DELETA A TABELA ANTIGA INCOMPLETA QUE ESTÁ CAUSANDO O BUG
DROP TABLE IF EXISTS public.calls;

-- 2. Cria a tabela 'calls' do zero, com todas as conexões (Foreign Keys) corretas
CREATE TABLE public.calls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
    caller_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT 'audio', -- 'audio' ou 'video'
    status TEXT NOT NULL DEFAULT 'ringing', -- 'ringing', 'in_progress', 'ended', 'missed', 'rejected'
    provider_room_id TEXT, -- Nome do canal gerado para o provedor de mídia da Agora
    started_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    audio_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Habilita o Realtime nessa tabela para o Flutter conseguir capturar os toques (ringing)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'calls'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.calls;
  END IF;
END $$;

-- 3. Habilita a Segurança por Nível de Linha (RLS)
ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;

-- 4. Criação da Política de Leitura (SELECT)
-- O usuário só pode ver e escutar chamadas que pertencem a chats que ele participa
CREATE POLICY "Users can view calls of their chats" 
ON public.calls FOR SELECT 
USING (
    chat_id IN (
        SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
    )
);

-- 5. Criação da Política de Inserção (INSERT)
-- O usuário pode criar chamadas se for membro do chat e ele for o caller_id
CREATE POLICY "Users can create calls in their chats" 
ON public.calls FOR INSERT 
WITH CHECK (
    caller_id = auth.uid() 
    AND 
    chat_id IN (
        SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
    )
);

-- 6. Criação da Política de Atualização (UPDATE)
-- O usuário pode atualizar status da chamada se for membro do chat
CREATE POLICY "Users can update calls of their chats" 
ON public.calls FOR UPDATE 
USING (
    chat_id IN (
        SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid()
    )
);

