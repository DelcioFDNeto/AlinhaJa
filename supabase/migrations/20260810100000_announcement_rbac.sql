-- ============================================================
-- Anúncios oficiais: permissão RBAC própria + trava no banco
--
-- CONTEXTO
-- O anúncio era um booleano no composer, liberado para quem administrava o
-- canal. Agora ele tem prioridade, prazo, público-alvo, anexo e botão de ação
-- (tudo em `metadata`), e passa a existir também em grupos — o que torna
-- "quem pode publicar" uma decisão de RH/Comunicação, não de quem gerencia a
-- lista de membros do canal.
--
-- POR QUE TRAVAR NO BANCO
-- Esconder o botão no app não impede nada: `metadata` é campo livre e
-- qualquer cliente autenticado pode inserir uma mensagem com
-- `type = 'announcement'` chamando a API direto. Sem esta migration a
-- permissão é decorativa.
-- ============================================================

-- ── 1. Permissões do módulo ──────────────────────────────────
INSERT INTO public.rbac_permissions (module, action, description) VALUES
  ('comunicacao_anuncios', 'create',
   'Pode publicar anúncios oficiais em canais e grupos'),
  ('comunicacao_anuncios', 'manage',
   'Pode encerrar, editar e remover anúncios de terceiros'),
  ('comunicacao_anuncios', 'view_stats',
   'Pode ver o painel de confirmações de leitura de qualquer anúncio')
ON CONFLICT (module, action) DO NOTHING;

-- ── 2. Helper de checagem ────────────────────────────────────
-- Espelha a regra que o app já usa em `RbacRepository.getMyPermissions()`:
-- admin e super_admin passam direto (senão um administrador consegue ficar
-- trancado fora do próprio painel), os demais dependem dos perfis atribuídos.
--
-- SECURITY DEFINER porque precisa ler `rbac_user_roles` e `users`, que têm RLS
-- própria; sem isso a checagem falharia para o usuário comum.
CREATE OR REPLACE FUNCTION public.has_rbac_permission(
  p_module TEXT,
  p_action TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid()
        AND u.role_level IN ('admin', 'super_admin')
    )
    OR EXISTS (
      SELECT 1
      FROM public.rbac_user_roles ur
      JOIN public.rbac_role_permissions rp ON rp.role_id = ur.role_id
      JOIN public.rbac_permissions p ON p.id = rp.permission_id
      WHERE ur.user_id = auth.uid()
        AND p.module = p_module
        AND p.action = p_action
    );
$$;

GRANT EXECUTE ON FUNCTION public.has_rbac_permission(TEXT, TEXT) TO authenticated;

-- ── 3. Trava de publicação ───────────────────────────────────
-- Policies RESTRICTIVE são combinadas com AND às permissivas que já existem,
-- então a regra de "membro pode enviar mensagem" continua intacta e ganha uma
-- condição extra só para o caso do anúncio. Recriar as policies permissivas
-- seria pior: elas já foram reescritas por outras migrations e o texto atual
-- no banco pode não bater com o do repositório.
--
-- Mensagem comum tem `metadata` sem `type` ou com outro valor e passa livre.
DROP POLICY IF EXISTS "Anuncio exige permissao RBAC" ON public.messages;
CREATE POLICY "Anuncio exige permissao RBAC"
  ON public.messages
  AS RESTRICTIVE
  FOR INSERT
  WITH CHECK (
    COALESCE(metadata->>'type', '') <> 'announcement'
    OR public.has_rbac_permission('comunicacao_anuncios', 'create')
  );

DROP POLICY IF EXISTS "Anuncio exige permissao RBAC" ON public.channel_messages;
CREATE POLICY "Anuncio exige permissao RBAC"
  ON public.channel_messages
  AS RESTRICTIVE
  FOR INSERT
  WITH CHECK (
    COALESCE(metadata->>'type', '') <> 'announcement'
    OR public.has_rbac_permission('comunicacao_anuncios', 'create')
  );

-- ── 4. Consulta dos anúncios vigentes ────────────────────────
-- `valid_until` (e não `expires_at`) é a chave de validade: `expires_at` já
-- significou "apague esta mensagem" no recurso de mensagem temporária, e um
-- anúncio vencido tem de continuar no histórico.
--
-- Índices parciais para a lista de anúncios fixados não varrer a conversa
-- inteira.
CREATE INDEX IF NOT EXISTS idx_messages_announcements
  ON public.messages (chat_id, created_at DESC)
  WHERE metadata->>'type' = 'announcement';

CREATE INDEX IF NOT EXISTS idx_channel_messages_announcements
  ON public.channel_messages (channel_id, created_at DESC)
  WHERE metadata->>'type' = 'announcement';

COMMENT ON FUNCTION public.has_rbac_permission(TEXT, TEXT) IS
  'Checa uma permissão RBAC do usuário logado. admin/super_admin passam direto.';

-- ── 5. Depois de aplicar ─────────────────────────────────────
-- As permissões nascem sem nenhum perfil vinculado: só admin e super_admin
-- publicam anúncio até que alguém atribua `comunicacao_anuncios:create` aos
-- perfis de RH/Comunicação na tela de Gestão de Acessos.
