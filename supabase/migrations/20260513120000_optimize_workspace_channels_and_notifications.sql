-- Optimize dedicated workspace/channel reads and push recipient lookup.

CREATE INDEX IF NOT EXISTS idx_channel_members_user_channel
  ON public.channel_members (user_id, channel_id);

CREATE INDEX IF NOT EXISTS idx_channels_last_message_at
  ON public.channels (last_message_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_channel_messages_channel_created
  ON public.channel_messages (channel_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_channel_messages_thread_sender
  ON public.channel_messages (thread_id, sender_id)
  WHERE thread_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_user_id
  ON public.user_fcm_tokens (user_id);
