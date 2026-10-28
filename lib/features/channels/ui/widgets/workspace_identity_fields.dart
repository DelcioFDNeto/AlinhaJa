import 'package:flutter/material.dart';
import 'package:alinha_ja/core/utils/icon_registry.dart';
import 'package:alinha_ja/features/channels/models/workspace_preset.dart';
import 'package:alinha_ja/features/channels/ui/widgets/workflow_stage_builder.dart';

/// Cartão de pré-visualização da identidade do workspace: mostra como ele vai
/// aparecer na lista de canais enquanto o usuário edita.
class WorkspacePreviewCard extends StatelessWidget {
  final String name;
  final String? description;
  final String icon;
  final String color;
  final String category;
  final bool workflowEnabled;
  final int stageCount;

  const WorkspacePreviewCard({
    super.key,
    required this.name,
    this.description,
    required this.icon,
    required this.color,
    required this.category,
    required this.workflowEnabled,
    this.stageCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = WorkspacePalette.toColor(color);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.12), theme.colorScheme.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(IconRegistry.resolve(icon), color: accent, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.trim().isEmpty ? 'Nome do workspace' : name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (description != null && description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        WorkspaceCategories.label(category).toUpperCase(),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: accent),
                      ),
                    ),
                    if (workflowEnabled)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.dashboard_customize,
                              size: 14, color: theme.colorScheme.outline),
                          const SizedBox(width: 4),
                          Text(
                            stageCount > 0
                                ? 'Workflow · $stageCount etapas'
                                : 'Workflow',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                        ],
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum_outlined,
                              size: 14, color: theme.colorScheme.outline),
                          const SizedBox(width: 4),
                          Text('Somente comunicação',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.outline)),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha com os botões de aparência (ícone e cor) do workspace.
class WorkspaceAppearanceRow extends StatelessWidget {
  final String icon;
  final String color;
  final ValueChanged<String> onIconChanged;
  final ValueChanged<String> onColorChanged;

  const WorkspaceAppearanceRow({
    super.key,
    required this.icon,
    required this.color,
    required this.onIconChanged,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = WorkspacePalette.toColor(color);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showIconPicker(
                context,
                current: icon,
                names: IconRegistry.workspaceIconNames,
                tint: accent,
              );
              if (picked != null) onIconChanged(picked);
            },
            icon: Icon(IconRegistry.resolve(icon), color: accent),
            label: const Text('Ícone'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showStagePalettePicker(context, color);
              if (picked != null) onColorChanged(picked);
            },
            icon: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            label: const Text('Cor'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Seletor de categoria do workspace (alimenta os filtros da aba de canais).
class WorkspaceCategorySelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const WorkspaceCategorySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: WorkspaceCategories.labels.keys.map((key) {
        final isSelected = selected == key;
        final color = theme.colorScheme.primary;

        return GestureDetector(
          onTap: () => onChanged(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color:
                  isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
              border: Border.all(
                  color: isSelected ? color : theme.colorScheme.outlineVariant,
                  width: isSelected ? 2 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  IconRegistry.resolve(WorkspaceCategories.icons[key]),
                  size: 18,
                  color: isSelected ? color : theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 8),
                Text(
                  WorkspaceCategories.label(key),
                  style: TextStyle(
                    color: isSelected ? color : null,
                    fontWeight: isSelected ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
