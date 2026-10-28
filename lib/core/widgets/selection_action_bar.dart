import 'package:flutter/material.dart';

/// Realce e caixa de marcação em volta de uma mensagem enquanto a seleção
/// múltipla está ativa. Fora do modo seleção não desenha nada em volta.
class MessageSelectionWrapper extends StatelessWidget {
  final bool active;
  final bool selected;
  final Widget child;

  const MessageSelectionWrapper({
    super.key,
    required this.active,
    required this.selected,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return child;

    final theme = Theme.of(context);
    return Container(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 22,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Barra que substitui a AppBar enquanto a seleção múltipla está ativa.
///
/// Não conhece o modelo de mensagem: cada tela passa o que sabe fazer, então
/// DMs, grupos e canais compartilham exatamente a mesma barra.
class SelectionActionBar extends StatelessWidget
    implements PreferredSizeWidget {
  final int count;
  final VoidCallback onClose;
  final VoidCallback? onForward;
  final VoidCallback? onCopy;
  final VoidCallback? onStar;
  final VoidCallback? onDelete;

  /// Motivo pelo qual excluir está indisponível (ex.: seleção com mensagens de
  /// outra pessoa). Vira tooltip no botão desabilitado.
  final String? deleteDisabledReason;

  const SelectionActionBar({
    super.key,
    required this.count,
    required this.onClose,
    this.onForward,
    this.onCopy,
    this.onStar,
    this.onDelete,
    this.deleteDisabledReason,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = count > 0;

    return AppBar(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancelar seleção',
        onPressed: onClose,
      ),
      title: Text(
        count == 1 ? '1 selecionada' : '$count selecionadas',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      actions: [
        if (onForward != null)
          IconButton(
            icon: const Icon(Icons.shortcut),
            tooltip: 'Encaminhar',
            onPressed: hasSelection ? onForward : null,
          ),
        if (onStar != null)
          IconButton(
            icon: const Icon(Icons.star_outline),
            tooltip: 'Favoritar',
            onPressed: hasSelection ? onStar : null,
          ),
        if (onCopy != null)
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copiar',
            onPressed: hasSelection ? onCopy : null,
          ),
        if (onDelete != null || deleteDisabledReason != null)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: deleteDisabledReason ?? 'Excluir',
            onPressed: hasSelection ? onDelete : null,
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}
