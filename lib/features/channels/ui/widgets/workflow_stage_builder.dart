import 'package:flutter/material.dart';
import 'package:alinha_ja/core/utils/icon_registry.dart';
import 'package:alinha_ja/features/channels/models/workspace_preset.dart';

/// Editor visual das etapas do Kanban (o "funil" do workspace).
///
/// É o mesmo componente usado na criação do workspace, na edição de um
/// workspace já existente e no editor de presets — por isso ele não fala com o
/// Supabase: recebe a lista de rascunhos e devolve a lista alterada.
///
/// Quando [cardCounts] é informado, cada etapa mostra quantos cards existem
/// nela e a remoção passa por [onBeforeRemove], onde a tela pai decide o
/// destino dos cards.
class WorkflowStageBuilder extends StatefulWidget {
  final List<WorkflowStageDraft> stages;
  final ValueChanged<List<WorkflowStageDraft>> onChanged;

  /// Contagem de cards por nome de etapa (chave em minúsculas).
  final Map<String, int> cardCounts;

  /// Chamado antes de remover uma etapa. Retorne `false` para abortar.
  final Future<bool> Function(
    WorkflowStageDraft stage,
    List<WorkflowStageDraft> remaining,
  )? onBeforeRemove;

  final bool readOnly;

  const WorkflowStageBuilder({
    super.key,
    required this.stages,
    required this.onChanged,
    this.cardCounts = const {},
    this.onBeforeRemove,
    this.readOnly = false,
  });

  @override
  State<WorkflowStageBuilder> createState() => _WorkflowStageBuilderState();
}

class _WorkflowStageBuilderState extends State<WorkflowStageBuilder> {
  /// Controllers por `localKey` — mantê-los estáveis evita que o cursor pule
  /// para o começo do campo a cada rebuild da lista.
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(WorkflowStageDraft stage) {
    return _controllers.putIfAbsent(
      stage.localKey,
      () => TextEditingController(text: stage.status),
    );
  }

  void _emit() => widget.onChanged(List.of(widget.stages));

  void _addStage() {
    final stage = WorkflowStageDraft(
      status: 'Nova etapa',
      color: '#6B7280',
      icon: 'circle',
    );
    // Etapas novas entram antes das de cancelamento, que ficam sempre no fim.
    final insertAt = widget.stages.lastIndexWhere((s) => !s.isCancelled) + 1;
    setState(() => widget.stages.insert(insertAt, stage));
    _emit();
  }

  Future<void> _removeStage(int index) async {
    final stage = widget.stages[index];

    if (widget.stages.where((s) => !s.isCancelled).length <= 1 &&
        !stage.isCancelled) {
      _warn('O workflow precisa de pelo menos uma etapa ativa.');
      return;
    }

    final remaining = List.of(widget.stages)..removeAt(index);
    final allowed = await widget.onBeforeRemove?.call(stage, remaining) ?? true;
    if (!allowed || !mounted) return;

    setState(() {
      _controllers.remove(stage.localKey)?.dispose();
      widget.stages.removeAt(index);
      _ensureInvariants();
    });
    _emit();
  }

  void _warn(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
    );
  }

  /// Garante uma única etapa inicial e ao menos uma final entre as ativas —
  /// as mesmas invariantes que `normalize_workflow_statuses` aplica no banco.
  void _ensureInvariants() {
    final active = widget.stages.where((s) => !s.isCancelled).toList();
    if (active.isEmpty) return;

    if (!active.any((s) => s.isInitial)) {
      active.first.isInitial = true;
    }
    if (!active.any((s) => s.isFinal)) {
      active.last.isFinal = true;
    }
    for (final stage in widget.stages) {
      if (stage.isCancelled) {
        stage.isInitial = false;
        stage.isFinal = false;
      }
    }
  }

  void _setInitial(WorkflowStageDraft stage) {
    setState(() {
      for (final s in widget.stages) {
        s.isInitial = false;
      }
      stage.isInitial = true;
      stage.isCancelled = false;
      _ensureInvariants();
    });
    _emit();
  }

  void _toggleFinal(WorkflowStageDraft stage) {
    setState(() {
      stage.isFinal = !stage.isFinal;
      if (stage.isFinal) {
        stage.isCancelled = false;
        stage.isInitial = false;
      }
      _ensureInvariants();
    });
    _emit();
  }

  void _toggleCancelled(WorkflowStageDraft stage) {
    setState(() {
      stage.isCancelled = !stage.isCancelled;
      if (stage.isCancelled) {
        stage.isFinal = false;
        stage.isInitial = false;
        stage.color = '#EF4444';
        stage.icon = 'cancel';
      }
      _ensureInvariants();
    });
    _emit();
  }

  Future<void> _pickColor(WorkflowStageDraft stage) async {
    final picked = await showStagePalettePicker(context, stage.color);
    if (picked == null) return;
    setState(() => stage.color = picked);
    _emit();
  }

  Future<void> _pickIcon(WorkflowStageDraft stage) async {
    final picked = await showIconPicker(
      context,
      current: stage.icon,
      names: IconRegistry.stageIconNames,
      tint: stage.colorValue,
    );
    if (picked == null) return;
    setState(() => stage.icon = picked);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text('Etapas do funil',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ),
              if (!widget.readOnly)
                TextButton.icon(
                  onPressed: _addStage,
                  icon: const Icon(Icons.add_circle, size: 18),
                  label: const Text('Nova etapa'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.stages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nenhuma etapa configurada.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.stages.length,
              onReorder: widget.readOnly
                  ? (_, __) {}
                  : (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = widget.stages.removeAt(oldIndex);
                        widget.stages.insert(newIndex, item);
                        _ensureInvariants();
                      });
                      _emit();
                    },
              itemBuilder: (context, index) =>
                  _buildStageTile(theme, widget.stages[index], index),
            ),
          const SizedBox(height: 8),
          Text(
            'Arraste pelo ícone ☰ para reordenar. A etapa inicial é onde os '
            'cards nascem; a final conclui o atendimento; a de cancelamento '
            'sai do funil e não conta para o SLA.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildStageTile(
      ThemeData theme, WorkflowStageDraft stage, int index) {
    final color = stage.colorValue;
    final count = widget.cardCounts[stage.status.toLowerCase().trim()] ?? 0;

    return Container(
      key: ValueKey(stage.localKey),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (!widget.readOnly)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    child: Icon(Icons.drag_indicator,
                        color: Colors.grey, size: 20),
                  ),
                )
              else
                const SizedBox(width: 12),
              IconButton(
                tooltip: 'Ícone da etapa',
                onPressed: widget.readOnly ? null : () => _pickIcon(stage),
                icon: Icon(stage.iconData, color: color, size: 20),
              ),
              Expanded(
                child: TextFormField(
                  controller: _controllerFor(stage),
                  readOnly: widget.readOnly,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
                    hintText: 'Nome da etapa...',
                  ),
                  onChanged: (v) {
                    stage.status = v;
                    _emit();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Cor da etapa',
                onPressed: widget.readOnly ? null : () => _pickColor(stage),
                icon: Icon(Icons.palette_outlined, color: color, size: 20),
              ),
              if (!widget.readOnly)
                PopupMenuButton<String>(
                  tooltip: 'Opções da etapa',
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (value) {
                    switch (value) {
                      case 'initial':
                        _setInitial(stage);
                        break;
                      case 'final':
                        _toggleFinal(stage);
                        break;
                      case 'cancelled':
                        _toggleCancelled(stage);
                        break;
                      case 'remove':
                        _removeStage(index);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'initial',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.flag_outlined, size: 20),
                        title: Text('Definir como etapa inicial'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'final',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.task_alt, size: 20),
                        title: Text(stage.isFinal
                            ? 'Deixar de ser etapa final'
                            : 'Marcar como etapa final'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'cancelled',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cancel_outlined, size: 20),
                        title: Text(stage.isCancelled
                            ? 'Deixar de ser cancelamento'
                            : 'Marcar como cancelamento'),
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'remove',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline,
                            size: 20, color: Colors.redAccent),
                        title: Text('Remover etapa',
                            style: TextStyle(color: Colors.redAccent)),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (stage.isInitial || stage.isFinal || stage.isCancelled || count > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (stage.isInitial)
                    _StageBadge(
                        label: 'Inicial',
                        icon: Icons.flag_outlined,
                        color: theme.colorScheme.primary),
                  if (stage.isFinal)
                    const _StageBadge(
                        label: 'Conclusão',
                        icon: Icons.task_alt,
                        color: Color(0xFF22C55E)),
                  if (stage.isCancelled)
                    const _StageBadge(
                        label: 'Cancelamento',
                        icon: Icons.cancel_outlined,
                        color: Color(0xFFEF4444)),
                  if (count > 0)
                    _StageBadge(
                        label: '$count card${count == 1 ? '' : 's'}',
                        icon: Icons.style_outlined,
                        color: theme.colorScheme.outline),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StageBadge(
      {required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// Seletor de cor da paleta padrão. Devolve o hex escolhido ou `null`.
Future<String?> showStagePalettePicker(
    BuildContext context, String current) async {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cor'),
      content: SizedBox(
        width: 320,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: WorkspacePalette.colors.map((hex) {
            final color = WorkspacePalette.toColor(hex);
            final selected = hex.toUpperCase() == current.toUpperCase();
            return InkWell(
              onTap: () => Navigator.pop(ctx, hex),
              borderRadius: BorderRadius.circular(30),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)]
                      : null,
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
      ],
    ),
  );
}

/// Seletor de ícone limitado ao [IconRegistry] — assim nada é gravado no banco
/// sem que a UI consiga desenhar depois.
Future<String?> showIconPicker(
  BuildContext context, {
  required String current,
  required List<String> names,
  Color? tint,
}) async {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final color = tint ?? theme.colorScheme.primary;
      return AlertDialog(
        title: const Text('Ícone'),
        content: SizedBox(
          width: 360,
          height: 320,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: names.length,
            itemBuilder: (context, index) {
              final name = names[index];
              final selected = name == current;
              return InkWell(
                onTap: () => Navigator.pop(ctx, name),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? color
                          : theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(IconRegistry.resolve(name),
                      color: selected ? color : theme.colorScheme.onSurface,
                      size: 22),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
        ],
      );
    },
  );
}
