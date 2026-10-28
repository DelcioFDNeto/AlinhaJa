import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:uuid/uuid.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'image_compress_stub.dart'
    if (dart.library.js_interop) 'image_compress_web.dart';

/// Resultado de um upload de mídia.
class MediaUploadResult {
  final String publicUrl;
  final String filePath;
  final int sizeBytes;
  final String mimeType;

  const MediaUploadResult({
    required this.publicUrl,
    required this.filePath,
    required this.sizeBytes,
    required this.mimeType,
  });
}

/// Serviço de processamento e upload de mídia.
///
/// Responsabilidade única: receber um [XFile] →
/// comprimir (se suportado pela plataforma) → upload para Supabase Storage
/// → retornar a URL pública.
///
/// Compatibilidade Web (CanvasKit):
/// - [XFile] funciona em todas as plataformas (Android, iOS, Web).
/// - `flutter_image_compress` usa codec nativo — disponível apenas em Android/iOS.
///   Na Web, o arquivo é enviado sem compressão (kIsWeb = true).
class MediaService {
  final _uuid = const Uuid();

  /// Comprime (mobile/web) e faz upload de uma imagem selecionada pelo usuário.
  Future<MediaUploadResult> compressAndUploadImage({
    required String chatId,
    required XFile file,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.05);

    Uint8List bytes;
    if (kIsWeb) {
      // Na web, comprime usando a Canvas API
      final rawBytes = await file.readAsBytes();
      bytes = await compressImageWeb(
        rawBytes,
        quality: AppConstants.imageQuality,
        maxWidth: AppConstants.imageMaxWidth,
      );
      onProgress?.call(0.30);
    } else {
      // Mobile: comprime primeiro, depois lê os bytes
      bytes = await _compressImageNative(file.path);
      onProgress?.call(0.30);
    }

    return _uploadBytes(
      chatId: chatId,
      bytes: bytes,
      mimeType: 'image/webp',
      onProgress: (p) => onProgress?.call(0.30 + p * 0.70),
    );
  }

  /// Auxiliar para determinar a extensão correta a partir do nome ou MIME.
  static String resolveExtension({String? fileName, String? mimeType}) {
    if (fileName != null && fileName.contains('.')) {
      final ext = fileName.split('.').last.trim().toLowerCase();
      if (ext.isNotEmpty && ext.length <= 10) return ext;
    }
    if (mimeType != null && mimeType.isNotEmpty) {
      if (mimeType == 'application/pdf') return 'pdf';
      if (mimeType.contains('wordprocessingml') || mimeType == 'application/msword') return 'docx';
      if (mimeType.contains('spreadsheetml') || mimeType == 'application/vnd.ms-excel') return 'xlsx';
      if (mimeType.contains('presentationml') || mimeType == 'application/vnd.ms-powerpoint') return 'pptx';
      if (mimeType == 'application/zip') return 'zip';
      if (mimeType == 'text/plain') return 'txt';
      if (mimeType == 'text/csv') return 'csv';
      final sub = mimeType.split('/').last.trim().toLowerCase();
      if (sub.isNotEmpty && sub != 'octet-stream') return sub;
    }
    return 'bin';
  }

  /// Auxiliar para resolver o MIME type a partir da extensão ou fallback.
  static String resolveMimeType({String? fileName, String? mimeType}) {
    if (mimeType != null && mimeType.isNotEmpty && mimeType != 'application/octet-stream') {
      return mimeType;
    }
    if (fileName != null && fileName.contains('.')) {
      final ext = fileName.split('.').last.trim().toLowerCase();
      switch (ext) {
        case 'pdf':
          return 'application/pdf';
        case 'doc':
          return 'application/msword';
        case 'docx':
          return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        case 'xls':
          return 'application/vnd.ms-excel';
        case 'xlsx':
          return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        case 'ppt':
          return 'application/vnd.ms-powerpoint';
        case 'pptx':
          return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
        case 'png':
          return 'image/png';
        case 'jpg':
        case 'jpeg':
          return 'image/jpeg';
        case 'gif':
          return 'image/gif';
        case 'webp':
          return 'image/webp';
        case 'mp4':
          return 'video/mp4';
        case 'mp3':
          return 'audio/mpeg';
        case 'txt':
          return 'text/plain';
        case 'csv':
          return 'text/csv';
        case 'zip':
          return 'application/zip';
      }
    }
    return mimeType ?? 'application/octet-stream';
  }

  /// Faz upload de um arquivo genérico sem compressão.
  Future<MediaUploadResult> uploadFile({
    required String chatId,
    required XFile file,
    String? mimeType,
    String? originalFileName,
    void Function(double progress)? onProgress,
  }) async {
    final name = originalFileName ?? file.name;
    final resolvedMime = resolveMimeType(fileName: name, mimeType: mimeType);
    final resolvedExt = resolveExtension(fileName: name, mimeType: resolvedMime);
    final bytes = await file.readAsBytes();
    return _uploadBytes(
      chatId: chatId,
      bytes: bytes,
      mimeType: resolvedMime,
      extension: resolvedExt,
      onProgress: onProgress,
    );
  }

  // ─── Private ───────────────────────────────────────────────

  /// Compressão nativa (Android/iOS) — retorna os bytes comprimidos.
  Future<Uint8List> _compressImageNative(String localPath) async {
    final dir = await getTemporaryDirectory();
    final targetPath = p.join(dir.path, '${_uuid.v4()}.webp');

    final result = await FlutterImageCompress.compressAndGetFile(
      localPath,
      targetPath,
      quality: AppConstants.imageQuality,
      minWidth: AppConstants.imageMaxWidth,
      format: CompressFormat.webp,
    );

    if (result == null) {
      // Fallback: lê o arquivo original sem compressão
      return XFile(localPath).readAsBytes();
    }
    return result.readAsBytes();
  }

  /// Upload de bytes para o Supabase Storage.
  Future<MediaUploadResult> _uploadBytes({
    required String chatId,
    required Uint8List bytes,
    required String mimeType,
    String? extension,
    void Function(double progress)? onProgress,
  }) async {
    final sizeBytes = bytes.length;

    if (sizeBytes > AppConstants.maxUploadSizeBytes) {
      throw Exception(
        'Arquivo muito grande: ${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB. '
        'Limite: 25 MB.',
      );
    }

    final ext = extension ??
        (mimeType.split('/').last == 'octet-stream' ? 'bin' : mimeType.split('/').last);
    final storagePath = 'chats/$chatId/${_uuid.v4()}.$ext';

    onProgress?.call(0.1);

    await supabase.storage.from(AppConstants.storageBucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    onProgress?.call(1.0);

    final publicUrl = supabase.storage
        .from(AppConstants.storageBucket)
        .getPublicUrl(storagePath);

    return MediaUploadResult(
      publicUrl: publicUrl,
      filePath: storagePath,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
    );
  }
}
