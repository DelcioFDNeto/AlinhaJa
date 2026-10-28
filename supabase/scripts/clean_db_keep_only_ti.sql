-- ============================================================================
-- SCRIPT DE LIMPEZA E CONFIGURAÇÃO DE AMBIENTE LIMPO (TI APENAS)
-- ============================================================================
-- Este script:
-- 1. Executa o reset operacional truncando todos os dados transacionais/mock.
-- 2. Remove todos os usuários de teste adicionais (diretoria, vendedores, etc.),
--    preservando exclusivamente o usuário do perfil de TI (ti@alinhaja.com.br).
-- 3. Recria os canais de workflow base associando apenas o usuário de TI.
-- ============================================================================

BEGIN;

-- 1. Resetar todas as tabelas operacionais e transacionais
-- (Isso garante que não há mais nenhuma FK ativa apontando para os usuários que serão excluídos)
SELECT public.reset_operational_data(FALSE);

-- 2. Limpar DMs/Chats diretos adicionais (caso existam) e outros logs transacionais
TRUNCATE TABLE public.message_actions CASCADE;
TRUNCATE TABLE public.messages CASCADE;
TRUNCATE TABLE public.chat_members CASCADE;
TRUNCATE TABLE public.chats CASCADE;
TRUNCATE TABLE public.channel_messages CASCADE;
TRUNCATE TABLE public.workflow_cards CASCADE;
TRUNCATE TABLE public.support_tickets CASCADE;
TRUNCATE TABLE public.support_ticket_messages CASCADE;
TRUNCATE TABLE public.user_locations CASCADE;
TRUNCATE TABLE public.meetings CASCADE;

-- 3. Deletar os outros usuários do Auth e public (com exceção do TI)
-- O TI Administrador possui a ID '00000000-0000-0000-0000-111111111111'
DELETE FROM auth.identities WHERE user_id != '00000000-0000-0000-0000-111111111111';
DELETE FROM auth.users WHERE id != '00000000-0000-0000-0000-111111111111';
DELETE FROM public.users WHERE id != '00000000-0000-0000-0000-111111111111';

-- 4. Recriar os canais base e as configurações de status
-- Como o TI é o único usuário restante no banco, ele será o único membro e administrador de todos os canais
SELECT * FROM public.seed_base_workflow_channels(TRUE, FALSE);

COMMIT;
