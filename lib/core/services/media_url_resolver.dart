import 'dart:developer';

import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';

/// Converte URLs armazenadas do bucket `chat-media` em URLs **assinadas**.
///
/// ## Por quê
/// O bucket era público: qualquer pessoa com a URL — sem login — baixava
/// mídia de DM privada e anexo de workflow com CPF/CNPJ. Com o bucket
/// privado, o acesso passa a exigir uma URL assinada, e a assinatura só é
/// emitida se a policy de SELECT (membership no chat/canal) permitir.
///
/// ## Compatibilidade com o que já está gravado
/// `messages.media_url` guarda a URL pública completa desde sempre. Em vez
/// de migrar milhares de linhas, extraímos o path da URL e assinamos na
/// hora. Vale tanto para URL pública quanto para uma já assinada (a query
/// string é descartada antes de reassinar).
///
/// ## Fail-safe deliberado
/// Se a assinatura falhar por qualquer motivo (offline, bucket ainda
/// público, path fora do bucket), devolvemos a URL original em vez de
/// lançar. É isso que permite publicar este código **antes** de virar o
/// bucket para privado: nesta janela nada muda de comportamento.
class MediaUrlResolver {
  MediaUrlResolver._();

  /// Validade da assinatura. Uma jornada de trabalho — longo o bastante
  /// para não quebrar imagem em conversa aberta o dia todo, curto o
  /// bastante para que uma URL vazada não valha para sempre.
  static const Duration signedFor = Duration(hours: 8);

  /// Margem para reassinar antes de expirar de fato.
  static const Duration _renewBefore = Duration(minutes: 30);

  static final Map<String, _CachedUrl> _cache = {};

  /// Assinaturas em andamento, por path.
  ///
  /// Sem isto, N widgets pedindo a mesma mídia ao mesmo tempo — o caso comum
  /// quando uma lista rebuilda — disparam N chamadas `createSignedUrl` para o
  /// mesmo objeto.
  static final Map<String, Future<String>> _inFlight = {};

  /// Resolução **síncrona** de [storedUrl], quando já é possível.
  ///
  /// Devolve a URL utilizável sem passar por `Future` em dois casos: a URL não
  /// pertence ao bucket (nada a assinar) ou já existe assinatura válida em
  /// cache. Devolve `null` quando só a rede resolve.
  ///
  /// Existe para a UI não recair no placeholder do `FutureBuilder` a cada
  /// rebuild: `resolve` é `async` e sempre completa num microtask posterior,
  /// então mesmo com cache quente o primeiro frame sairia sem imagem.
  static String? peek(String storedUrl) {
    if (storedUrl.isEmpty) return storedUrl;

    final path = pathOf(storedUrl);
    if (path == null) return storedUrl;

    final cached = _cache[path];
    if (cached != null && !cached.needsRenewal) return cached.url;

    return null;
  }

  /// Extrai o path do objeto dentro do bucket a partir de uma URL.
  ///
  /// Devolve `null` se a URL não pertencer ao bucket (ex.: avatar de
  /// serviço externo, link colado pelo usuário) — nesse caso não há o que
  /// assinar e a URL deve ser usada como está.
  static String? pathOf(String url) {
    const marker = '/${AppConstants.storageBucket}/';
    final idx = url.indexOf(marker);
    if (idx == -1) return null;

    final path = url.substring(idx + marker.length).split('?').first;
    return path.isEmpty ? null : path;
  }

  /// Forma estável de uma URL, para uso como chave.
  ///
  /// Uma URL assinada muda a cada renovação (token novo). Usá-la como chave
  /// de cache faria o mesmo arquivo ser rebaixado a cada 8h. Esta função
  /// devolve o path do objeto quando ele pertence ao bucket, ou a URL sem
  /// query string caso contrário.
  static String canonicalize(String url) {
    return pathOf(url) ?? url.split('?').first;
  }

  /// Devolve uma URL utilizável para [storedUrl].
  ///
  /// Assinada quando o objeto pertence ao bucket; a própria [storedUrl]
  /// caso contrário ou se a assinatura falhar.
  ///
  /// Se [downloadFileName] for informado, anexa o parâmetro `download`
  /// para que o Supabase Storage e o navegador salvem o arquivo com o
  /// nome e extensão corretos (Content-Disposition: attachment; filename="...").
  static Future<String> resolve(
    String storedUrl, {
    String? downloadFileName,
  }) async {
    if (storedUrl.isEmpty) return storedUrl;

    final path = pathOf(storedUrl);
    String baseSignedUrl;

    if (path == null) {
      baseSignedUrl = storedUrl;
    } else {
      final cached = _cache[path];
      if (cached != null && !cached.needsRenewal) {
        baseSignedUrl = cached.url;
      } else {
        // Uma assinatura em voo atende todos os chamadores do mesmo path.
        var pending = _inFlight[path];
        if (pending == null) {
          pending = _sign(path, storedUrl)
              .whenComplete(() => _inFlight.remove(path));
          _inFlight[path] = pending;
        }
        baseSignedUrl = await pending;
      }
    }

    if (downloadFileName != null && downloadFileName.trim().isNotEmpty) {
      final sanitizedName = downloadFileName.trim();
      final uri = Uri.tryParse(baseSignedUrl);
      if (uri != null) {
        final queryParams = Map<String, String>.from(uri.queryParameters);
        queryParams['download'] = sanitizedName;
        return uri.replace(queryParameters: queryParams).toString();
      }
    }

    return baseSignedUrl;
  }

  /// Emite (e cacheia) a assinatura de [path].
  ///
  /// Nunca lança: em caso de falha devolve [fallbackUrl], mantendo o
  /// fail-safe descrito na documentação da classe.
  static Future<String> _sign(String path, String fallbackUrl) async {
    try {
      final signed = await supabase.storage
          .from(AppConstants.storageBucket)
          .createSignedUrl(path, signedFor.inSeconds);

      _cache[path] = _CachedUrl(
        url: signed,
        expiresAt: DateTime.now().add(signedFor),
      );
      return signed;
    } catch (e) {
      // Sem acesso (não é membro) ou offline. Devolver a original mantém
      // o comportamento anterior em vez de derrubar a tela.
      log('MediaUrlResolver: falha ao assinar "$path": $e');
      return fallbackUrl;
    }
  }

  /// Versão em lote — uma ida à rede para várias mídias.
  ///
  /// Preserva a ordem de [storedUrls]. Usar ao carregar uma página de
  /// mensagens ou a galeria de mídias, evitando N requisições.
  static Future<List<String>> resolveAll(List<String> storedUrls) async {
    if (storedUrls.isEmpty) return const [];

    // Só precisam de rede os paths do bucket ainda não cacheados.
    final pending = <String>{};
    for (final url in storedUrls) {
      final path = pathOf(url);
      if (path == null) continue;
      final cached = _cache[path];
      if (cached == null || cached.needsRenewal) {
        pending.add(path);
      }
    }

    if (pending.isNotEmpty) {
      try {
        final signed = await supabase.storage
            .from(AppConstants.storageBucket)
            .createSignedUrls(pending.toList(), signedFor.inSeconds);

        final expiresAt = DateTime.now().add(signedFor);
        for (final item in signed) {
          final signedUrl = item.signedUrl;
          final path = item.path;
          if (path.isEmpty || signedUrl.isEmpty) continue;
          // createSignedUrls devolve o path com o bucket na frente em
          // algumas versões do SDK; normaliza para a mesma chave de pathOf.
          final key = path.startsWith('${AppConstants.storageBucket}/')
              ? path.substring(AppConstants.storageBucket.length + 1)
              : path;
          _cache[key] = _CachedUrl(url: signedUrl, expiresAt: expiresAt);
        }
      } catch (e) {
        log('MediaUrlResolver: falha ao assinar lote: $e');
        // Segue adiante: o map abaixo devolve as originais.
      }
    }

    return storedUrls.map((url) {
      final path = pathOf(url);
      if (path == null) return url;
      final cached = _cache[path];
      if (cached == null || cached.isExpired) return url;
      return cached.url;
    }).toList(growable: false);
  }

  /// Descarta a assinatura cacheada de um objeto.
  ///
  /// Chamar quando a mídia é destruída no servidor (visualização única,
  /// exclusão) para que uma URL ainda válida não seja reutilizada da
  /// memória do processo.
  static void invalidate(String pathOrUrl) {
    final path = pathOf(pathOrUrl) ?? pathOrUrl;
    _cache.remove(path);
  }

  /// Limpa todas as assinaturas. Usar no logout: as URLs foram emitidas
  /// para a sessão que está terminando.
  static void clear() {
    _cache.clear();
    _inFlight.clear();
  }
}

class _CachedUrl {
  final String url;
  final DateTime expiresAt;

  const _CachedUrl({required this.url, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get needsRenewal => DateTime.now()
      .isAfter(expiresAt.subtract(MediaUrlResolver._renewBefore));
}
