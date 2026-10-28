-- ============================================================
-- Migration: Adicionar trigger para notificações (versão simplificada)
-- Executar no SQL Editor do Supabase Dashboard
-- ============================================================

-- 1. Primeiro, garantir que messages está no Realtime
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;

-- 2. Verificar se a Edge Function existe e está configurada
-- Se não existir, criar via: supabase functions deploy send-chat-notification

-- 3. Trigger simples que apenas logs (para debugging)
-- A Edge Function deve ser chamada pelo app Flutter diretamente após insert
-- ou via webhook configurado no Supabase Dashboard

-- Para ativar via Supabase Dashboard:
-- 1. Vá em Database -> Webhooks
-- 2. Create new webhook
-- 3. Table: messages
-- 4. Events: Insert
-- 4. URL: https://hzvmqsgpopgfkvdxyain.supabase.co/functions/v1/send-chat-notification

-- Por enquanto, o app Flutter deve chamar a Edge Function diretamente
-- após inserir uma mensagem (em chat_repository.dart)
