-- ============================================================
-- ETAPA B — chat-media passa a privado (achado de segurança 1.1, parte 2/2)
--
-- Esta é a etapa que `20260803130000_chat_media_membership_policies.sql`
-- anuncia no cabeçalho como "20260803140000". O arquivo nunca foi escrito de
-- propósito: virar o bucket antes de o app publicar URLs assinadas quebraria
-- toda a mídia de uma vez. Ganhou o timestamp de hoje porque aplicar uma
-- migration com data anterior às já aplicadas as coloca fora de ordem.
--
-- PRÉ-REQUISITOS — todos cumpridos em 20/08/2026
--   1. ETAPA A aplicada: as policies de membership existem e cobrem os três
--      prefixos de path (`avatars`, `chats/{uuid}`, `workflow_attachments`).
--   2. App com URLs assinadas publicado: `MediaUrlResolver` e
--      `SignedNetworkImage` estão na v1.3.5, no ar em alinha-ja-app e
--      alinhajadev desde 13/08/2026.
--   3. Prova empírica: o Fluxy — mesmo código de mídia — já roda com
--      `chat-media` privado.
--
-- POR QUE AGORA
-- Enquanto o bucket é público, o endpoint `/object/public/{path}` NÃO passa
-- por RLS: as policies da ETAPA A ficam inócuas e qualquer pessoa com a URL
-- lê foto de DM privada, áudio, PDF e anexo de workflow com CPF/CNPJ. Medido
-- em 20/08/2026: `chat-media` estava público em DEV e em PROD do AlinhaJá.
--
-- `avatars` fica público de propósito: o bucket foi criado assim em
-- `20260803150000_avatars_bucket.sql`, a foto de perfil é exibida em listas e
-- menções por toda a aplicação, e o mesmo vale no Fluxy — mudar só aqui
-- quebraria a paridade sem ganho de privacidade proporcional.
--
-- ROLLBACK
--   UPDATE storage.buckets SET public = true WHERE id = 'chat-media';
-- Reverter devolve a exposição pública; só use se a mídia sumir em massa, e
-- investigue o MediaUrlResolver em vez de deixar revertido.
-- ============================================================

DO $do$
DECLARE
  v_policies INT;
BEGIN
  -- Fail-closed: sem as policies da ETAPA A, virar o bucket privado tira a
  -- mídia do ar para TODO MUNDO (nada autoriza a assinatura). Melhor abortar
  -- a migration do que descobrir isso pelo suporte.
  SELECT COUNT(*) INTO v_policies
  FROM pg_policies
  WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND policyname IN (
      'Leitura de mídia por membro do contexto',
      'Upload de mídia por membro do contexto',
      'Update de mídia por membro do contexto'
    );

  IF v_policies < 3 THEN
    RAISE EXCEPTION
      'ETAPA A ausente: encontradas % de 3 policies de membership em storage.objects. Aplique 20260803130000_chat_media_membership_policies.sql antes desta.',
      v_policies;
  END IF;
END
$do$;

UPDATE storage.buckets
SET public = false
WHERE id = 'chat-media';

-- Confirma o efeito em vez de confiar no UPDATE: se o bucket não existir, o
-- UPDATE acima afeta 0 linhas e passaria silenciosamente.
DO $do$
DECLARE
  v_public BOOLEAN;
BEGIN
  SELECT public INTO v_public FROM storage.buckets WHERE id = 'chat-media';

  IF v_public IS NULL THEN
    RAISE EXCEPTION 'Bucket chat-media não existe neste banco.';
  END IF;

  IF v_public THEN
    RAISE EXCEPTION 'Bucket chat-media continua público após o UPDATE.';
  END IF;

  RAISE NOTICE 'chat-media agora é privado. A leitura passa pelas policies da ETAPA A.';
END
$do$;
