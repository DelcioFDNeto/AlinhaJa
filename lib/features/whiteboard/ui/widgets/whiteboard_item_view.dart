import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alinha_ja/core/services/media_url_resolver.dart';
import 'package:alinha_ja/core/widgets/signed_network_image.dart';
import 'package:alinha_ja/features/whiteboard/models/whiteboard_item.dart';

/// Um anexo desenhado sobre o quadro.
///
/// Fica **abaixo** da camada de traços de propósito: o objetivo do anexo é
/// servir de base para o desenho (marcar a foto da prateleira, circular o
/// item da planta), então o risco tem que cair por cima dele.
///
/// Só recebe toque quando o quadro está no modo mover — nas ferramentas de
/// desenho a camada de traços cobre a tela inteira e é ela quem captura o
/// gesto.
class WhiteboardItemView extends StatelessWidget {
  const WhiteboardItemView({
    super.key,
    required this.item,
    required this.scale,
    required this.interactive,
    required this.onDrag,
    required this.onResize,
    required this.onGestureEnd,
    required this.onRemove,
  });

  final WhiteboardItem item;

  /// Pixels de tela por unidade do quadro. Converte o delta do dedo, que vem
  /// em pixels, para o espaço lógico onde o anexo é gravado.
  final double scale;

  /// Modo mover ativo: arrasta, redimensiona e mostra as alças.
  final bool interactive;

  final void Function(Offset boardDelta) onDrag;
  final void Function(Offset boardDelta) onResize;
  final VoidCallback onGestureEnd;
  final VoidCallback onRemove;

  /// Lado da alça de redimensionar, em pixels de tela.
  static const double _handleSize = 26;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = item.isImage
        ? _ImageBody(item: item)
        : _FileBody(item: item, interactive: interactive);

    final framed = DecoratedBox(
      decoration: BoxDecoration(
        border: interactive
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: content,
    );

    if (!interactive) return framed;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onDrag(d.delta / scale),
            onPanEnd: (_) => onGestureEnd(),
            onPanCancel: onGestureEnd,
            child: framed,
          ),
        ),

        // Remover: canto superior direito, fora da moldura para não cobrir a
        // imagem.
        Positioned(
          top: -12,
          right: -12,
          child: _HandleButton(
            icon: Icons.close,
            tooltip: 'Remover anexo do quadro',
            background: theme.colorScheme.error,
            foreground: theme.colorScheme.onError,
            onTap: onRemove,
          ),
        ),

        // Redimensionar: canto inferior direito, o lugar onde todo mundo já
        // procura essa alça.
        Positioned(
          bottom: -12,
          right: -12,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onResize(d.delta / scale),
            onPanEnd: (_) => onGestureEnd(),
            onPanCancel: onGestureEnd,
            child: Container(
              width: _handleSize,
              height: _handleSize,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.open_in_full_rounded,
                  size: 12, color: theme.colorScheme.onPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class _HandleButton extends StatelessWidget {
  const _HandleButton({
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Icon(icon, size: 14, color: foreground),
        ),
      ),
    );
  }
}

class _ImageBody extends StatelessWidget {
  const _ImageBody({required this.item});

  final WhiteboardItem item;

  @override
  Widget build(BuildContext context) {
    return SignedNetworkImage(
      storedUrl: item.mediaUrl,
      fit: BoxFit.fill,
      placeholder: (_, __) => const ColoredBox(
        color: Color(0xFFF1F1F4),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: Color(0xFFF1F1F4),
        child: Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}

/// Anexo que não é imagem: PDF, planilha, ZIP.
///
/// Vira cartão em vez de sumir do quadro — o arquivo faz parte da conversa
/// que o desenho está explicando, e mandá-lo separado no chat quebraria essa
/// ligação.
class _FileBody extends StatelessWidget {
  const _FileBody({required this.item, required this.interactive});

  final WhiteboardItem item;
  final bool interactive;

  Future<void> _open() async {
    try {
      final resolved = await MediaUrlResolver.resolve(
        item.mediaUrl,
        downloadFileName: item.fileName,
      );
      final uri = Uri.tryParse(resolved);
      if (uri == null) return;
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (e) {
      debugPrint('Erro ao abrir anexo do quadro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.insert_drive_file_outlined,
              size: 30, color: theme.colorScheme.primary),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              item.fileName ?? 'Arquivo',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // No modo mover o gesto é arrastar; abrir o arquivo a cada toque
          // atrapalharia o posicionamento.
          if (!interactive)
            TextButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.open_in_new_rounded, size: 14),
              label: const Text('Abrir', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
        ],
      ),
    );
  }
}
