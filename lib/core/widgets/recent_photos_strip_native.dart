import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

/// Leitura da galeria só existe onde o `photo_manager` tem implementação.
/// Neste projeto isso significa Android — as demais plataformas nativas caem
/// no seletor do sistema, como antes.
bool get recentPhotosSupported => Platform.isAndroid;

Widget buildRecentPhotosStrip({
  required ValueChanged<XFile> onPicked,
  required VoidCallback onOpenGallery,
}) =>
    _RecentPhotosStrip(onPicked: onPicked, onOpenGallery: onOpenGallery);

/// Tira horizontal com as fotos e vídeos mais recentes do aparelho.
class _RecentPhotosStrip extends StatefulWidget {
  /// Recebe o arquivo escolhido; a tela decide o que fazer (normalmente abrir
  /// o preview antes de enviar).
  final ValueChanged<XFile> onPicked;

  /// Abre o seletor completo do sistema ("Ver tudo").
  final VoidCallback onOpenGallery;

  const _RecentPhotosStrip({
    required this.onPicked,
    required this.onOpenGallery,
  });

  @override
  State<_RecentPhotosStrip> createState() => _RecentPhotosStripState();
}

class _RecentPhotosStripState extends State<_RecentPhotosStrip> {
  static const _thumbCount = 20;
  static const _stripHeight = 104.0;

  List<AssetEntity> _assets = const [];
  bool _loading = true;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      // `hasAccess` cobre o acesso parcial do Android 14, em que o usuário
      // libera apenas algumas fotos — ainda dá para montar a tira.
      if (!permission.hasAccess) {
        if (mounted) {
          setState(() {
            _loading = false;
            _denied = true;
          });
        }
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      if (albums.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final recent =
          await albums.first.getAssetListPaged(page: 0, size: _thumbCount);
      if (!mounted) return;
      setState(() {
        _assets = recent;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Aviso: falha ao carregar fotos recentes -> $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(AssetEntity asset) async {
    final file = await asset.file;
    if (file == null) return;
    widget.onPicked(XFile(file.path));
  }

  @override
  Widget build(BuildContext context) {
    // Sem permissão ou sem fotos, o menu de anexo continua igual ao de antes.
    if (_denied || (!_loading && _assets.isEmpty)) {
      return const SizedBox.shrink();
    }

    if (_loading) {
      return const SizedBox(
        height: _stripHeight,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return SizedBox(
      height: _stripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _assets.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == _assets.length) {
            return _OpenGalleryTile(onTap: widget.onOpenGallery);
          }
          return _AssetThumb(
            asset: _assets[index],
            onTap: () => _pick(_assets[index]),
          );
        },
      ),
    );
  }
}

class _AssetThumb extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onTap;

  const _AssetThumb({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 88,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List?>(
                future: asset.thumbnailDataWithSize(
                  const ThumbnailSize.square(200),
                ),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    );
                  }
                  return Image.memory(bytes, fit: BoxFit.cover);
                },
              ),

              // Vídeo ganha marcação de duração, como na galeria do sistema.
              if (asset.type == AssetType.video)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _formatDuration(asset.videoDuration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _OpenGalleryTile extends StatelessWidget {
  final VoidCallback onTap;

  const _OpenGalleryTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 88,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text(
              'Ver tudo',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
