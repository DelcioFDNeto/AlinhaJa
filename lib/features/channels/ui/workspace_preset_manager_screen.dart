import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/channels/models/workspace_preset.dart';
import 'package:alinha_ja/features/channels/providers/workspace_presets_provider.dart';
import 'package:alinha_ja/features/channels/ui/workspace_preset_editor_screen.dart';

/// Biblioteca de presets de workspace.
///
/// Presets de sistema aparecem como somente leitura (com ação "Duplicar");
/// os criados pela empresa podem ser editados e excluídos pelo dono ou por um
/// admin global — a RPC revalida isso no banco.
class WorkspacePresetManagerScreen extends ConsumerWidget {
  const WorkspacePresetManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final presetsAsync = ref.watch(workspacePresetsProvider);
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final userId = supabase.auth.currentUser?.id;
    final isGlobalAdmin =
        AppPermissions.canCreateChannel(currentUser?.roleLevel);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Presets de Workspace'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            onPressed: () => ref.invalidate(workspacePresetsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'preset_fab',
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Novo Preset'),
      ),
      body: presetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: describePresetError(e),
          onRetry: () => ref.invalidate(workspacePresetsProvider),
        ),
        data: (presets) {
          if (presets.isEmpty) {
            return _EmptyView(onCreate: () => _openEditor(context));
          }

          final system = presets.where((p) => p.isSystem).toList();
          final custom = presets.where((p) => !p.isSystem).toList();

          return ResponsiveWidthContainer(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  'Um preset guarda a identidade do workspace, o formulário do '
                  'card, o modo de atribuição e todas as etapas do Kanban. '
                  'Ao criar um workspace você escolhe um preset e ainda pode '
                  'ajustar tudo antes de confirmar.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                if (custom.isNotEmpty) ...[
                  _SectionHeader(
                      title: 'Da empresa', count: custom.length, theme: theme),
                  ...custom.map((p) => _PresetTile(
                        preset: p,
                        canEdit: p.canEdit(userId, isGlobalAdmin: isGlobalAdmin),
                        onEdit: () => _openEditor(context, preset: p),
                        onDuplicate: () => _duplicate(context, ref, p),
                        onDelete: () => _confirmDelete(context, ref, p),
                      )),
                  const SizedBox(height: 20),
                ],
                _SectionHeader(
                    title: 'Modelos do sistema',
                    count: system.length,
                    theme: theme),
                ...system.map((p) => _PresetTile(
                      preset: p,
                      canEdit: false,
                      onEdit: null,
                      onDuplicate: () => _duplicate(context, ref, p),
                      onDelete: null,
                    )),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor(BuildContext context,
      {WorkspacePreset? preset, WorkspacePreset? seed}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            WorkspacePresetEditorScreen(preset: preset, seed: seed),
      ),
    );
  }

  Future<void> _duplicate(
      BuildContext context, WidgetRef ref, WorkspacePreset preset) async {
    // Abre o editor já preenchido, como preset novo — assim o usuário nomeia
    // e ajusta antes de gravar, em vez de criar uma cópia solta na lista.
    await _openEditor(
      context,
      seed: WorkspacePreset(
        id: '',
        name: '${preset.name} (cópia)',
        description: preset.description,
        category: preset.category,
        icon: preset.icon,
        color: preset.color,
        cardType: preset.cardType,
        workflowEnabled: preset.workflowEnabled,
        assignmentMode: preset.assignmentMode,
        postingPermission: preset.postingPermission,
        stages: preset.freshStages(),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, WorkspacePreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir preset'),
        content: Text(
            'Excluir "${preset.name}"? Os workspaces já criados a partir dele '
            'não são afetados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(workspacePresetServiceProvider).delete(preset.id);
      messenger.showSnackBar(
        SnackBar(
            content: Text('Preset "${preset.name}" excluído.'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
            content: Text(describePresetError(e)),
            backgroundColor: Colors.red),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final ThemeData theme;

  const _SectionHeader(
      {required this.title, required this.count, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$count', style: theme.textTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final WorkspacePreset preset;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;

  const _PresetTile({
    required this.preset,
    required this.canEdit,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = preset.colorValue;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canEdit ? onEdit : onDuplicate,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(preset.iconData, color: accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preset.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (preset.description != null) ...[
                      const SizedBox(height: 2),
                      Text(preset.description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Chip(
                            label: preset.categoryLabel,
                            color: accent,
                            theme: theme),
                        if (preset.workflowEnabled)
                          _Chip(
                              label: '${preset.stages.length} etapas',
                              color: theme.colorScheme.outline,
                              theme: theme)
                        else
                          _Chip(
                              label: 'Sem workflow',
                              color: theme.colorScheme.outline,
                              theme: theme),
                        if (preset.isSystem)
                          _Chip(
                              label: 'Sistema',
                              color: theme.colorScheme.primary,
                              theme: theme)
                        else if (!preset.isShared)
                          _Chip(
                              label: 'Privado',
                              color: theme.colorScheme.tertiary,
                              theme: theme),
                        if (preset.usageCount > 0)
                          _Chip(
                              label: 'Usado ${preset.usageCount}x',
                              color: theme.colorScheme.outline,
                              theme: theme),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit?.call();
                      break;
                    case 'duplicate':
                      onDuplicate();
                      break;
                    case 'delete':
                      onDelete?.call();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (canEdit)
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined, size: 20),
                        title: Text('Editar'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.copy_outlined, size: 20),
                      title: Text('Duplicar'),
                    ),
                  ),
                  if (onDelete != null) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline,
                            size: 20, color: Colors.redAccent),
                        title: Text('Excluir',
                            style: TextStyle(color: Colors.redAccent)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final ThemeData theme;

  const _Chip(
      {required this.label, required this.color, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyView({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dashboard_customize_outlined,
              size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('Nenhum preset disponível',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Crie um modelo com as etapas que sua operação usa e reaproveite '
              'em novos workspaces.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Criar preset'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente')),
        ],
      ),
    );
  }
}
