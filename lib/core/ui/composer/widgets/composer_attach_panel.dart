import 'package:flutter/material.dart';

import 'package:alinha_ja/core/ui/composer/composer_action.dart';

/// Painel de anexos: grade de ações que cresce acima do campo de texto.
///
/// O número de colunas vem da largura disponível, não de uma constante: 4 no
/// celular, até 8 em tablet/desktop. Em tela baixa (celular deitado) a grade
/// rola em vez de estourar o layout.
class ComposerAttachPanel extends StatelessWidget {
  final List<ComposerActionId> actions;
  final ValueChanged<ComposerActionId> onAction;

  /// Tira de fotos recentes, quando a plataforma suporta.
  final Widget? recentPhotos;

  /// Ações desenhadas como ligadas.
  final Set<ComposerActionId> highlighted;

  const ComposerAttachPanel({
    super.key,
    required this.actions,
    required this.onAction,
    this.recentPhotos,
    this.highlighted = const {},
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxPanelHeight = MediaQuery.sizeOf(context).height * 0.45;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxPanelHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (recentPhotos != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: recentPhotos,
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Alvo de ~84px por item; nunca menos de 4 colunas para não
                    // virar uma lista vertical no celular estreito.
                    final columns =
                        (constraints.maxWidth / 84).floor().clamp(4, 8);
                    const gap = 8.0;
                    final itemWidth =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;

                    return Wrap(
                      spacing: gap,
                      runSpacing: 4,
                      children: [
                        for (final id in actions)
                          SizedBox(
                            width: itemWidth,
                            child: _AttachOption(
                              spec: composerActionSpecs[id]!,
                              active: highlighted.contains(id),
                              onTap: () => onAction(id),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  final ComposerActionSpec spec;
  final bool active;
  final VoidCallback onTap;

  const _AttachOption({
    required this.spec,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: spec.color.withValues(alpha: active ? 0.9 : 0.15),
                shape: BoxShape.circle,
                border: active ? Border.all(color: spec.color, width: 2) : null,
              ),
              child: Icon(
                spec.icon,
                size: 22,
                color: active ? Colors.white : spec.color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              spec.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
