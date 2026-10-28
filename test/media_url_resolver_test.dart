import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/core/services/media_cache_manager.dart';
import 'package:alinha_ja/core/services/media_url_resolver.dart';

/// Cobre os atalhos síncronos que evitam que a lista de mensagens volte ao
/// placeholder — e refaça trabalho de rede/disco — a cada rebuild.
///
/// `resolve` e `getOrDownloadMedia` dependem de Supabase e do Drift, então
/// aqui testamos apenas a parte pura: `peek`, `canonicalize` e o memo vazio.
void main() {
  const bucketUrl =
      'https://xyz.supabase.co/storage/v1/object/public/chat-media/chats/c1/foto.webp';

  setUp(() {
    MediaUrlResolver.clear();
    MediaCacheManager.clearResolvedCache();
  });

  group('MediaUrlResolver.peek', () {
    test('URL fora do bucket resolve na hora, sem Future', () {
      const external = 'https://exemplo.com/avatar.png';
      expect(MediaUrlResolver.peek(external), external);
    });

    test('URL vazia devolve ela mesma em vez de null', () {
      expect(MediaUrlResolver.peek(''), '');
    });

    test('URL do bucket sem assinatura em cache exige ida à rede', () {
      expect(MediaUrlResolver.peek(bucketUrl), isNull);
    });

    test('clear() descarta as assinaturas da sessão', () {
      MediaUrlResolver.clear();
      expect(MediaUrlResolver.peek(bucketUrl), isNull);
    });
  });

  group('MediaUrlResolver.canonicalize', () {
    test('URL do bucket vira o path do objeto', () {
      expect(MediaUrlResolver.canonicalize(bucketUrl), 'chats/c1/foto.webp');
    });

    test('assinaturas diferentes do mesmo objeto compartilham a chave', () {
      expect(
        MediaUrlResolver.canonicalize('$bucketUrl?token=aaa'),
        MediaUrlResolver.canonicalize('$bucketUrl?token=bbb'),
      );
    });

    test('URL externa perde só a query string', () {
      expect(
        MediaUrlResolver.canonicalize('https://exemplo.com/a.png?v=2'),
        'https://exemplo.com/a.png',
      );
    });
  });

  group('MediaCacheManager.cachedFileFor', () {
    test('mídia nunca resolvida não tem arquivo local', () {
      expect(MediaCacheManager.cachedFileFor(bucketUrl), isNull);
    });

    test('URL vazia não consulta o memo', () {
      expect(MediaCacheManager.cachedFileFor(''), isNull);
    });

    test('clearResolvedCache() esvazia o memo do logout', () {
      MediaCacheManager.clearResolvedCache();
      expect(MediaCacheManager.cachedFileFor(bucketUrl), isNull);
    });
  });
}
