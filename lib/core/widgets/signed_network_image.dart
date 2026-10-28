import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:alinha_ja/core/services/media_url_resolver.dart';

/// `CachedNetworkImage` que assina a URL antes de buscar.
///
/// Substitui o uso direto de `CachedNetworkImage(imageUrl: message.mediaUrl!)`
/// para mídia do bucket `chat-media`, que é privado: a URL pública gravada em
/// `media_url` não é mais suficiente e precisa virar URL assinada, emitida
/// apenas se a policy de membership permitir.
///
/// Para URLs fora do bucket (avatar em bucket público, link externo) o
/// resolver devolve a própria URL e o comportamento é idêntico ao de antes.
///
/// A assinatura é cacheada em memória por path, então trocar de tela ou
/// rolar a conversa não gera requisição nova.
class SignedNetworkImage extends StatelessWidget {
  /// URL como está gravada no banco (pública ou já assinada).
  final String storedUrl;

  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;

  const SignedNetworkImage({
    super.key,
    required this.storedUrl,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    // URL fora do bucket (avatar público, link externo) ou assinatura ainda
    // válida em cache: resolve sem `Future`. `resolve` é async e só completa
    // num microtask posterior, então sem este atalho o placeholder piscaria a
    // cada rebuild da lista mesmo com o cache quente.
    final ready = MediaUrlResolver.peek(storedUrl);
    if (ready != null) return _image(context, ready);

    return FutureBuilder<String>(
      // resolve() nunca lança: em caso de falha devolve storedUrl.
      future: MediaUrlResolver.resolve(storedUrl),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return placeholder?.call(context, storedUrl) ??
              Container(
                width: width,
                height: height,
                color: Colors.black12,
                child: const Center(child: CircularProgressIndicator()),
              );
        }

        return _image(context, snapshot.data!);
      },
    );
  }

  Widget _image(BuildContext context, String url) {
    if (kIsWeb) {
      return Image.network(
        url,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (ctx, err, stack) =>
            errorWidget?.call(ctx, url, err) ?? const Icon(Icons.broken_image),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      // A URL assinada troca de token a cada renovação; sem uma chave
      // estável o cache de imagem do dispositivo rebaixaria o mesmo
      // arquivo a cada expiração.
      cacheKey: MediaUrlResolver.canonicalize(storedUrl),
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
  }
}
