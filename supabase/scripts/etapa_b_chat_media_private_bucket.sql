-- ============================================================
-- ETAPA B — chat-media vira bucket PRIVADO
--            (achado de segurança 1.1, parte 2 de 2)
--
-- ⚠️  ESTE ARQUIVO NÃO É UMA MIGRATION — de propósito.
--     Ele mora em supabase/scripts/ para NÃO ser aplicado por
--     `supabase db push` junto com o lote. Rode-o à mão, no SQL Editor,
--     só quando as condições abaixo estiverem satisfeitas.
--
-- ⚠️  NÃO EXECUTE ANTES DE:
--     1. A ETAPA A (20260803130000) estar aplicada;
--     2. O bucket de avatares (20260803150000) estar aplicado E o script
--        scripts/migrate_avatars_bucket.js ter rodado com --apply; e
--     3. O app com MediaUrlResolver estar PUBLICADO em produção
--        (web + Android), não apenas compilado.
--
-- Motivo: enquanto houver cliente montando URL pública, virar o bucket
-- para privado faz toda a mídia responder 400/404 na hora — imagem,
-- áudio, vídeo, PDF e anexo de workflow, em todas as conversas.
--
-- O MediaUrlResolver foi escrito para tolerar as duas configurações:
-- com o bucket público ele assina e a URL assinada também funciona, então
-- publicar o app antes desta migration é seguro e não muda nada para o
-- usuário. A ordem correta é: etapa A → publicar app → etapa B.
--
-- COMO VALIDAR ANTES (com o bucket ainda público)
--   Abra o app publicado, envie uma imagem e confirme no DevTools que a
--   URL requisitada contém "/object/sign/" e "?token=". Se ainda aparecer
--   "/object/public/", há caminho não migrado — não aplique esta etapa.
--
-- COMO REVERTER (se algo escapar)
--   UPDATE storage.buckets SET public = true WHERE id = 'chat-media';
--   A reversão é instantânea e não perde arquivo algum.
-- ============================================================

-- ── 1. Guarda: a etapa A precisa estar aplicada ──────────────
-- Sem a policy de membership, virar privado deixaria o bucket sem
-- NENHUMA regra de leitura — ninguém enxergaria a própria mídia.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'storage'
       AND tablename  = 'objects'
       AND policyname = 'Leitura de mídia por membro do contexto'
  ) THEN
    RAISE EXCEPTION
      'Etapa A ausente: aplique 20260803130000_chat_media_membership_policies.sql antes desta migration.';
  END IF;
END $$;

-- ── 2. O flip ────────────────────────────────────────────────
UPDATE storage.buckets
   SET public = false
 WHERE id = 'chat-media';

-- ── 3. Confirmação no log do apply ───────────────────────────
DO $$
DECLARE
  v_public boolean;
BEGIN
  SELECT public INTO v_public FROM storage.buckets WHERE id = 'chat-media';

  IF v_public IS NULL THEN
    RAISE WARNING 'Bucket chat-media não existe nesta base — nada a fazer.';
  ELSIF v_public THEN
    RAISE WARNING 'Bucket chat-media continua PÚBLICO. Verifique permissões.';
  ELSE
    RAISE NOTICE 'chat-media agora é privado. Acesso apenas por URL assinada, sujeita à policy de membership.';
  END IF;
END $$;
