import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// O `photo_manager` não tem implementação Web e usa `dart:io` internamente;
// o import condicional garante que ele nunca entre no bundle do navegador.
// Mesmo idioma de `image_compress_stub.dart`.
import 'recent_photos_strip_stub.dart'
    if (dart.library.io) 'recent_photos_strip_native.dart' as impl;

/// Tira de fotos e vídeos recentes do aparelho, exibida no menu de anexo para
/// enviar em um toque.
///
/// Onde a galeria não é legível (Web), [isSupported] é `false` e o widget não
/// ocupa espaço — o botão "Galeria" continua sendo o caminho.
class RecentPhotosStrip extends StatelessWidget {
  /// Recebe o arquivo escolhido; a tela decide o que fazer com ele
  /// (normalmente abrir o preview antes de enviar).
  final ValueChanged<XFile> onPicked;

  /// Abre o seletor completo do sistema ("Ver tudo").
  final VoidCallback onOpenGallery;

  const RecentPhotosStrip({
    super.key,
    required this.onPicked,
    required this.onOpenGallery,
  });

  /// Se vale a pena montar a tira nesta plataforma.
  static bool get isSupported => impl.recentPhotosSupported;

  @override
  Widget build(BuildContext context) => impl.buildRecentPhotosStrip(
        onPicked: onPicked,
        onOpenGallery: onOpenGallery,
      );
}
