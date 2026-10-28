-- ============================================================
-- Migração 004: Canais Oficiais e Assinatura Digital
-- ============================================================

-- ── 1. Tabela: message_acknowledgements ──────────────────────────────
-- Armazena o registro de ciência/assinatura digital de comunicados.
CREATE TABLE IF NOT EXISTS public.message_acknowledgements (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id      UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  acknowledged_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Campos para auditoria/rastreabilidade legal
  ip_address      TEXT,
  device_info     TEXT,
  UNIQUE(message_id, user_id) -- Um usuário só assina a mesma mensagem uma vez
);

CREATE INDEX IF NOT EXISTS idx_msg_ack_message ON public.message_acknowledgements(message_id);
CREATE INDEX IF NOT EXISTS idx_msg_ack_user    ON public.message_acknowledgements(user_id);

-- RLS
ALTER TABLE public.message_acknowledgements ENABLE ROW LEVEL SECURITY;

-- Usuários podem ver as assinaturas das mensagens dos chats que eles participam
CREATE POLICY "Membros veem assinaturas do seu chat"
  ON public.message_acknowledgements FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = message_id AND public.is_chat_member(m.chat_id)
    )
  );

-- Usuários só podem assinar por eles mesmos
CREATE POLICY "Usuário cria sua própria assinatura"
  ON public.message_acknowledgements FOR INSERT
  WITH CHECK (
    user_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = message_id AND public.is_chat_member(m.chat_id)
    )
  );

-- ── 2. RPC: acknowledge_message ───────────────────────────────────────
-- Função facilitadora para o app assinar uma mensagem.
CREATE OR REPLACE FUNCTION public.acknowledge_message(
  p_message_id UUID,
  p_ip_address TEXT DEFAULT NULL,
  p_device_info TEXT DEFAULT NULL
)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  -- Verifica se a mensagem exige assinatura
  IF NOT EXISTS (
    SELECT 1 FROM public.messages 
    WHERE id = p_message_id AND (metadata->>'requires_acknowledgement')::boolean = true
  ) THEN
    RAISE EXCEPTION 'This message does not require acknowledgement.';
  END IF;

  INSERT INTO public.message_acknowledgements (message_id, user_id, ip_address, device_info)
  VALUES (p_message_id, auth.uid(), p_ip_address, p_device_info)
  ON CONFLICT (message_id, user_id) DO NOTHING;

  RETURN TRUE;
END;
$$;

-- ── 3. RPC: create_company_channel ────────────────────────────────────
-- Cria um "Megalofone" (canal) e adiciona TODOS os usuários da empresa.
-- Apenas admins/diretores deveriam chamar isso.
CREATE OR REPLACE FUNCTION public.create_company_channel(
  p_name TEXT,
  p_description TEXT
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_chat_id UUID;
  v_user RECORD;
BEGIN
  -- Cria o chat do tipo canal
  INSERT INTO public.chats (type, name, description, created_by)
  VALUES ('channel', p_name, p_description, auth.uid())
  RETURNING id INTO v_chat_id;

  -- Adiciona o criador como 'owner'
  INSERT INTO public.chat_members (chat_id, user_id, role)
  VALUES (v_chat_id, auth.uid(), 'owner');

  -- Adiciona todos os outros usuários como 'member'
  FOR v_user IN SELECT id FROM public.users WHERE id != auth.uid() LOOP
    INSERT INTO public.chat_members (chat_id, user_id, role)
    VALUES (v_chat_id, v_user.id, 'member')
    ON CONFLICT (chat_id, user_id) DO NOTHING;
  END LOOP;

  RETURN v_chat_id;
END;
$$;

-- ── 4. Trigger: Auto-adicionar novos colaboradores em Canais ─────────
-- Sempre que uma nova pessoa entra na empresa, ela é adicionada 
-- automaticamente em todos os chats do tipo 'channel'.
CREATE OR REPLACE FUNCTION public.add_new_user_to_channels()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_channel RECORD;
BEGIN
  FOR v_channel IN SELECT id FROM public.chats WHERE type = 'channel' LOOP
    INSERT INTO public.chat_members (chat_id, user_id, role)
    VALUES (v_channel.id, NEW.id, 'member')
    ON CONFLICT (chat_id, user_id) DO NOTHING;
  END LOOP;
  RETURN NEW;
END;
$$;

-- Aplica o trigger na tabela public.users
DROP TRIGGER IF EXISTS on_user_created_add_to_channels ON public.users;
CREATE TRIGGER on_user_created_add_to_channels
  AFTER INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.add_new_user_to_channels();
