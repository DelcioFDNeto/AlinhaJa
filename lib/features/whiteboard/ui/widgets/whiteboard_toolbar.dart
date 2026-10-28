import 'package:flutter/material.dart';

import 'package:alinha_ja/features/whiteboard/models/whiteboard_stroke.dart';

/// Barra de ferramentas do quadro branco (anexo, caneta, marca-texto,
/// borracha, mover, cor, espessura).
class WhiteboardToolbar extends StatelessWidget {
  final Color color;
  final double width;
  final WhiteboardTool tool;

  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<WhiteboardTool> onToolChanged;

  /// Anexar imagem (galeria/câmera) e arquivo. `null` desativa o botão —
  /// quadro trancado ou sem conversa dona.
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachCamera;
  final VoidCallback? onAttachFile;

  /// Upload em andamento: o botão vira progresso para o toque repetido não
  /// enfileirar dois envios.
  final bool isUploading;

  static const List<Color> palette = [
    Color(0xFF1A1A1A),
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
  ];

  const WhiteboardToolbar({
    super.key,
    required this.color,
    required this.width,
    required this.tool,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onToolChanged,
    this.onAttachImage,
    this.onAttachCamera,
    this.onAttachFile,
    this.isUploading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Anexar ──
            _AttachButton(
              isUploading: isUploading,
              onAttachImage: onAttachImage,
              onAttachCamera: onAttachCamera,
              onAttachFile: onAttachFile,
            ),

            const SizedBox(width: 8),

            // ── Ferramenta ──
            SegmentedButton<WhiteboardTool>(
              segments: const [
                ButtonSegment(
                  value: WhiteboardTool.pen,
                  icon: Icon(Icons.edit, size: 18),
                  tooltip: 'Caneta',
                ),
                ButtonSegment(
                  value: WhiteboardTool.highlighter,
                  icon: Icon(Icons.border_color, size: 18),
                  tooltip: 'Marca-texto',
                ),
                ButtonSegment(
                  value: WhiteboardTool.eraser,
                  icon: Icon(Icons.cleaning_services, size: 18),
                  tooltip: 'Borracha',
                ),
                ButtonSegment(
                  value: WhiteboardTool.move,
                  icon: Icon(Icons.open_with, size: 18),
                  tooltip: 'Mover anexos',
                ),
              ],
              selected: {tool},
              onSelectionChanged: (s) => onToolChanged(s.first),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 8)),
              ),
            ),

            const SizedBox(width: 12),

            // ── Cores (só quando a ferramenta pinta) ──
            if (tool == WhiteboardTool.pen ||
                tool == WhiteboardTool.highlighter)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final c in palette)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => onColorChanged(c),
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: color == c
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else
              const Spacer(),

            // ── Espessura ──
            PopupMenuButton<double>(
              initialValue: width,
              tooltip: 'Espessura do traço',
              onSelected: onWidthChanged,
              icon: Icon(Icons.line_weight,
                  color: theme.colorScheme.onSurfaceVariant),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 2.0, child: Text('Fino (2px)')),
                PopupMenuItem(value: 4.0, child: Text('Médio (4px)')),
                PopupMenuItem(value: 8.0, child: Text('Grosso (8px)')),
                PopupMenuItem(value: 16.0, child: Text('Muito grosso (16px)')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão de anexo: abre o menu de origem (galeria, câmera, arquivo).
///
/// Vira indicador de progresso durante o upload em vez de simplesmente ficar
/// desabilitado — sem isso, um anexo grande deixa a barra com a mesma cara de
/// "quadro trancado" e o usuário toca de novo.
class _AttachButton extends StatelessWidget {
  const _AttachButton({
    required this.isUploading,
    required this.onAttachImage,
    required this.onAttachCamera,
    required this.onAttachFile,
  });

  final bool isUploading;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachCamera;
  final VoidCallback? onAttachFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isUploading) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final enabled = onAttachImage != null || onAttachFile != null;

    return PopupMenuButton<VoidCallback>(
      enabled: enabled,
      tooltip: enabled
          ? 'Anexar imagem ou arquivo ao quadro'
          : 'O quadro está trancado',
      onSelected: (action) => action(),
      icon: Icon(
        Icons.add_photo_alternate,
        color: enabled
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
      ),
      itemBuilder: (_) => [
        if (onAttachImage != null)
          PopupMenuItem(
            value: onAttachImage,
            child: const ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.image),
              title: Text('Imagem da galeria'),
              subtitle: Text('Desenhe por cima dela'),
            ),
          ),
        if (onAttachCamera != null)
          PopupMenuItem(
            value: onAttachCamera,
            child: const ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.photo_camera),
              title: Text('Tirar foto'),
            ),
          ),
        if (onAttachFile != null)
          PopupMenuItem(
            value: onAttachFile,
            child: const ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.attach_file),
              title: Text('Arquivo'),
              subtitle: Text('PDF, planilha, documento'),
            ),
          ),
      ],
    );
  }
}
