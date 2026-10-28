import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart' as drift;
import 'package:alinha_ja/core/database/drift_database.dart';
import 'package:alinha_ja/core/services/media_url_resolver.dart';
import 'package:http/http.dart' as http;

class MediaCacheManager {
  // Configuração recomendada pelo plano (500MB imagens, 1GB vídeos)
  static const int maxImageCacheSizeBytes = 500 * 1024 * 1024; // 500 MB
  static const int maxVideoCacheSizeBytes = 1000 * 1024 * 1024; // 1 GB

  /// Arquivos já resolvidos nesta sessão, por chave canônica.
  ///
  /// `getOrDownloadMedia` é chamado de dentro de `build()` (o `FutureBuilder`
  /// do balão de mídia). Sem este memo, cada rebuild da lista refazia, por
  /// imagem visível, um SELECT no Drift + um `File.exists()` + um UPDATE de
  /// `lastAccessedAt` — e a lista rebuilda a cada indicador de digitação,
  /// reação ou recibo de leitura, não só a cada mensagem nova.
  static final Map<String, File> _resolvedFiles = {};

  /// Buscas em andamento, para que N widgets pedindo a mesma mídia
  /// compartilhem um único download em vez de dispararem N.
  static final Map<String, Future<File?>> _inFlight = {};

  /// Arquivo local já conhecido para [mediaUrl], sem tocar em disco nem banco.
  ///
  /// Deixa a UI pintar a imagem já no primeiro frame do rebuild em vez de
  /// voltar ao spinner do `FutureBuilder` a cada reconstrução.
  static File? cachedFileFor(String mediaUrl) {
    if (kIsWeb || mediaUrl.isEmpty) return null;
    return _resolvedFiles[MediaUrlResolver.canonicalize(mediaUrl)];
  }

  /// Retorna o arquivo local se existir no cache, senão baixa e salva no cache
  static Future<File?> getOrDownloadMedia({
    required String mediaUrl,
    required String messageId,
    required String chatId,
    required String mediaType, // 'image', 'video', etc
  }) {
    if (kIsWeb) {
      // Na web, não salvamos no sistema de arquivos local com File
      return Future.value(null);
    }

    final cacheKey = MediaUrlResolver.canonicalize(mediaUrl);

    final memoized = _resolvedFiles[cacheKey];
    if (memoized != null) return Future.value(memoized);

    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;

    final future = _fetchMedia(
      mediaUrl: mediaUrl,
      cacheKey: cacheKey,
      messageId: messageId,
      chatId: chatId,
      mediaType: mediaType,
    ).whenComplete(() => _inFlight.remove(cacheKey));

    _inFlight[cacheKey] = future;
    return future;
  }

  static Future<File?> _fetchMedia({
    required String mediaUrl,
    required String cacheKey,
    required String messageId,
    required String chatId,
    required String mediaType,
  }) async {
    try {
      // 1. Verifica no Drift se já existe registro.
      // A chave é a forma canônica (path do objeto), não a URL recebida:
      // URL assinada troca de token a cada renovação e usá-la como chave
      // faria o mesmo arquivo ser rebaixado a cada expiração.
      final cachedEntry = await (driftDb.select(driftDb.mediaCache)
            ..where((t) => t.remoteUrl.equals(cacheKey)))
          .getSingleOrNull();

      if (cachedEntry != null && cachedEntry.localPath != null) {
        final file = File(cachedEntry.localPath!);
        if (await file.exists()) {
          // Atualiza a data de último acesso. Roda uma vez por mídia por
          // sessão: a partir daqui o memo responde sem tocar no banco, e o
          // arquivo já está quente de qualquer forma para efeito de LRU.
          await (driftDb.update(driftDb.mediaCache)
                ..where((t) => t.id.equals(cachedEntry.id)))
              .write(MediaCacheCompanion(
            lastAccessedAt: drift.Value(DateTime.now()),
          ));
          _resolvedFiles[cacheKey] = file;
          return file;
        } else {
          // Arquivo foi apagado manualmente, limpa do banco
          await (driftDb.delete(driftDb.mediaCache)
                ..where((t) => t.id.equals(cachedEntry.id)))
              .go();
        }
      }

      // 2. Não existe ou foi apagado. Faz o download.
      // Assina a URL antes de baixar: com o bucket privado, a URL pública
      // gravada em media_url não é mais suficiente. Se não houver o que
      // assinar, resolve() devolve a própria URL (ver MediaUrlResolver).
      final downloadUrl = await MediaUrlResolver.resolve(mediaUrl);
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) return null;

      // 3. Salva no disco
      final dir = await getApplicationDocumentsDirectory();
      final extension = mediaUrl.split('.').last.split('?').first;
      final fileName = '$messageId.$extension';
      final file = File('${dir.path}/media_cache/$chatId/$fileName');

      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      await file.writeAsBytes(response.bodyBytes);
      final sizeBytes = await file.length();

      // 4. Salva registro no Drift (indexado pela forma canônica)
      await driftDb.into(driftDb.mediaCache).insert(
            MediaCacheCompanion.insert(
              id: messageId,
              remoteUrl: cacheKey,
              localPath: drift.Value(file.path),
              mediaType: mediaType,
              sizeBytes: sizeBytes,
              chatId: chatId,
              downloadedAt: DateTime.now(),
              lastAccessedAt: DateTime.now(),
            ),
          );

      // 5. Verifica se ultrapassou o limite e limpa os mais antigos se necessário
      await _enforceCacheLimits(mediaType);

      _resolvedFiles[cacheKey] = file;
      return file;
    } catch (e) {
      debugPrint('MediaCacheManager Erro: $e');
      return null;
    }
  }

  /// Registra um arquivo local diretamente no cache (usado logo após um upload bem-sucedido)
  static Future<void> cacheLocalFile({
    required String localPath,
    required String mediaUrl,
    required String messageId,
    required String chatId,
    required String mediaType,
  }) async {
    if (kIsWeb) return;

    try {
      final file = File(localPath);
      if (!await file.exists()) return;

      // Copia para a pasta de cache se já não estiver lá
      final dir = await getApplicationDocumentsDirectory();
      final extension = mediaUrl.split('.').last.split('?').first;
      final fileName = '$messageId.$extension';
      final cacheFile = File('${dir.path}/media_cache/$chatId/$fileName');

      if (!await cacheFile.parent.exists()) {
        await cacheFile.parent.create(recursive: true);
      }

      if (file.path != cacheFile.path) {
        await file.copy(cacheFile.path);
      }

      final sizeBytes = await cacheFile.length();

      // Salva ou atualiza no Drift (mesma chave canônica do download,
      // senão o arquivo recém-enviado não seria reconhecido na leitura)
      await driftDb.into(driftDb.mediaCache).insertOnConflictUpdate(
            MediaCacheCompanion.insert(
              id: messageId,
              remoteUrl: MediaUrlResolver.canonicalize(mediaUrl),
              localPath: drift.Value(cacheFile.path),
              mediaType: mediaType,
              sizeBytes: sizeBytes,
              chatId: chatId,
              downloadedAt: DateTime.now(),
              lastAccessedAt: DateTime.now(),
            ),
          );

      _resolvedFiles[MediaUrlResolver.canonicalize(mediaUrl)] = cacheFile;

      await _enforceCacheLimits(mediaType);
    } catch (e) {
      debugPrint('MediaCacheManager Erro ao salvar arquivo local: $e');
    }
  }

  /// Descarta o memo em memória. Usar no logout, junto de
  /// [MediaUrlResolver.clear]: os arquivos referenciados pertencem à sessão
  /// que está terminando.
  static void clearResolvedCache() {
    _resolvedFiles.clear();
    _inFlight.clear();
  }

  /// Remove do cache local a mídia correspondente a [pathOrUrl] — arquivo em
  /// disco e registro no Drift.
  ///
  /// Usado quando a mídia foi destruída no servidor (visualização única,
  /// exclusão, expiração): sem isso a cópia local sobreviveria ao purge remoto
  /// e o "some depois de ver" seria falso em qualquer aparelho que já a baixou.
  ///
  /// Aceita tanto o path do objeto (`chats/<id>/<uuid>.webp`) quanto a URL
  /// completa, já que o cache é indexado pela URL remota.
  static Future<void> evict(String pathOrUrl) async {
    if (pathOrUrl.isEmpty) return;

    // Descarta a assinatura em memória mesmo na Web (onde não há cache em
    // disco): uma URL assinada ainda válida não pode sobreviver ao purge.
    MediaUrlResolver.invalidate(pathOrUrl);

    if (kIsWeb) return;

    try {
      final needle = pathOrUrl.split('?').first;

      final entries = await (driftDb.select(driftDb.mediaCache)
            ..where((t) => t.remoteUrl.like('%$needle')))
          .get();

      for (final entry in entries) {
        if (entry.localPath != null) {
          final file = File(entry.localPath!);
          if (await file.exists()) {
            await file.delete();
          }
        }
        await (driftDb.delete(driftDb.mediaCache)
              ..where((t) => t.id.equals(entry.id)))
            .go();
        // Sem isto o memo continuaria devolvendo um File já apagado e a
        // mídia de visualização única sobreviveria ao purge na tela.
        _resolvedFiles.remove(entry.remoteUrl);
      }
    } catch (e) {
      debugPrint('MediaCacheManager Erro ao remover mídia do cache: $e');
    }
  }

  /// Limpa automaticamente o cache se ele passar dos limites estabelecidos
  static Future<void> runStorageCleanup() async {
    if (kIsWeb) return;
    await _enforceCacheLimits('image');
    await _enforceCacheLimits('video');
    await _enforceCacheLimits('audio');
    await _enforceCacheLimits('document');
  }

  /// Verifica e impõe os limites de tamanho de cache baseados no tipo de mídia
  static Future<void> _enforceCacheLimits(String mediaType) async {
    if (kIsWeb) return;

    try {
      final maxSizeBytes = mediaType == 'video'
          ? maxVideoCacheSizeBytes
          : maxImageCacheSizeBytes;

      // Soma o tamanho total atual daquele tipo
      final query = driftDb.select(driftDb.mediaCache)
        ..where((t) => t.mediaType.equals(mediaType))
        ..orderBy([(t) => drift.OrderingTerm.asc(t.lastAccessedAt)]);

      final items = await query.get();

      int totalSize = 0;
      for (var item in items) {
        totalSize += item.sizeBytes;
      }

      // Se passou do limite, apaga os mais antigos até voltar pro limite
      if (totalSize > maxSizeBytes) {
        int bytesToRemove = totalSize - maxSizeBytes;

        for (var item in items) {
          if (bytesToRemove <= 0) break;

          if (item.localPath != null) {
            final file = File(item.localPath!);
            if (await file.exists()) {
              await file.delete();
            }
          }

          await (driftDb.delete(driftDb.mediaCache)
                ..where((t) => t.id.equals(item.id)))
              .go();
          _resolvedFiles.remove(item.remoteUrl);

          bytesToRemove -= item.sizeBytes;
        }
      }
    } catch (e) {
      debugPrint('Erro ao limpar cache de mídia: $e');
    }
  }

  /// Retorna o uso atual de cache por tipo em megabytes
  static Future<Map<String, double>> getCacheUsageMB() async {
    final Map<String, double> usage = {};
    if (kIsWeb) return usage;

    final items = await driftDb.select(driftDb.mediaCache).get();
    for (var item in items) {
      usage[item.mediaType] =
          (usage[item.mediaType] ?? 0) + (item.sizeBytes / (1024 * 1024));
    }
    return usage;
  }
}
