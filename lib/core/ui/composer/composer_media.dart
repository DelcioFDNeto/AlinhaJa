import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:alinha_ja/core/widgets/media_preview_screen.dart';

/// Seleção de mídia + confirmação no preview, em um lugar só.
///
/// A mesma sequência (escolher → conferir no preview → enviar) estava escrita
/// em `chat_screen`, `thread_screen` e `message_input_bar`, cada uma com uma
/// diferença sutil. Aqui ela existe uma vez e todo mundo chama.
class ComposerMedia {
  ComposerMedia._();

  /// Câmera ou galeria. A galeria aceita seleção múltipla; a câmera devolve um
  /// arquivo só. Retorna `null` se o usuário desistir em qualquer etapa.
  static Future<MediaPreviewResult?> pickAndPreviewMedia(
    BuildContext context, {
    required ImageSource source,
    required String destinationName,
    bool allowViewOnce = false,
  }) async {
    final picker = ImagePicker();
    final List<XFile> picked;

    if (source == ImageSource.gallery) {
      picked = await picker.pickMultipleMedia(imageQuality: 80);
    } else {
      final shot = await picker.pickImage(source: source, imageQuality: 80);
      picked = shot == null ? const [] : [shot];
    }

    if (picked.isEmpty || !context.mounted) return null;

    return MediaPreviewScreen.show(
      context,
      files: picked,
      destinationName: destinationName,
      allowViewOnce: allowViewOnce,
    );
  }

  /// Documentos de qualquer tipo, com seleção múltipla.
  static Future<MediaPreviewResult?> pickAndPreviewDocuments(
    BuildContext context, {
    required String destinationName,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !context.mounted) return null;

    final files = toXFiles(result.files);
    if (files.isEmpty) return null;

    return MediaPreviewScreen.show(
      context,
      files: files,
      destinationName: destinationName,
    );
  }

  /// Preview de arquivos já em mãos (tira de recentes, arrastar-e-soltar).
  static Future<MediaPreviewResult?> previewFiles(
    BuildContext context, {
    required List<XFile> files,
    required String destinationName,
    bool allowViewOnce = false,
  }) {
    if (files.isEmpty) return Future.value(null);
    return MediaPreviewScreen.show(
      context,
      files: files,
      destinationName: destinationName,
      allowViewOnce: allowViewOnce,
    );
  }

  /// Converte o resultado do `file_picker` em [XFile].
  ///
  /// Na Web só existem os bytes; no desktop/mobile o caminho é o suficiente e
  /// evita carregar o arquivo inteiro na memória.
  static List<XFile> toXFiles(List<PlatformFile> files) => [
        for (final file in files)
          if (file.bytes != null)
            XFile.fromData(file.bytes!, name: file.name)
          else if (file.path != null && file.path!.isNotEmpty)
            XFile(file.path!),
      ];

  /// Distingue foto/vídeo de documento pelo nome do arquivo.
  static bool isVisualMedia(XFile file) {
    final name = (file.name.isNotEmpty ? file.name : file.path).toLowerCase();
    const visual = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.heic',
      '.bmp',
      '.mp4',
      '.mov',
      '.m4v',
      '.webm',
    ];
    return visual.any(name.endsWith);
  }
}
