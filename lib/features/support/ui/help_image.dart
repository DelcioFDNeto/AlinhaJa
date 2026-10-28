import 'package:flutter/material.dart';

/// Captura de tela usada nos Guias e no Manual.
///
/// As imagens de ajuda são telas cheias reduzidas a alguns centímetros: sem
/// ampliação, o usuário não consegue ler o rótulo do botão que o passo manda
/// procurar. Tocar abre o visualizador em tela cheia com zoom e arrasto.
///
/// Assets ausentes degradam para nada (`SizedBox.shrink`) em vez de quebrar a
/// tela — um guia sem captura ainda é um guia utilizável.
class HelpImage extends StatelessWidget {
  /// Caminho completo do asset (ex.: `assets/images/help/shots/x.webp`).
  final String asset;

  /// Legenda exibida no visualizador em tela cheia.
  final String? caption;

  const HelpImage({super.key, required this.asset, this.caption});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: caption == null ? 'Ampliar captura' : 'Ampliar captura: $caption',
      child: Tooltip(
        message: 'Toque para ampliar',
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.zoom_out_map_rounded,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _HelpImageViewer(asset: asset, caption: caption),
    );
  }
}

class _HelpImageViewer extends StatelessWidget {
  final String asset;
  final String? caption;

  const _HelpImageViewer({required this.asset, this.caption});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filledTonal(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Fechar',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          if (caption != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  caption!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
