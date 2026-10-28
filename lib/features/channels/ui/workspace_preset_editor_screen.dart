import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/channels/models/workspace_preset.dart';
import 'package:alinha_ja/features/channels/providers/workspace_presets_provider.dart';
import 'package:alinha_ja/features/channels/ui/widgets/workflow_stage_builder.dart';
import 'package:alinha_ja/features/channels/ui/widgets/workspace_identity_fields.dart';
import 'package:alinha_ja/features/workflow/models/workflow_enums.dart';

/// Editor de preset de workspace: cria um novo, edita um existente ou salva
/// uma configuração montada na tela de criação como modelo reutilizável.
///
/// Presets de sistema nunca chegam aqui em modo de edição — a lista oferece
/// "Duplicar", que abre esta tela já como preset novo.
class WorkspacePresetEditorScreen extends ConsumerStatefulWidget {
  /// Preset sendo editado. `null` cria um novo.
  final WorkspacePreset? preset;

  /// Configuração de partida para "Salvar como preset" e para "Duplicar".
  final WorkspacePreset? seed;

  const WorkspacePresetEditorScreen({super.key, this.preset, this.seed});

  @override
  ConsumerState<WorkspacePresetEditorScreen> createState() =>
      _WorkspacePresetEditorScreenState();
}

class _WorkspacePresetEditorScreenState
    extends ConsumerState<WorkspacePresetEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  late String _category;
  late String _icon;
  late String _color;
  late String _cardType;
  late String _assignmentMode;
  late bool _workflowEnabled;
  late bool _isShared;
  late List<WorkflowStageDraft> _stages;

  bool _saving = false;

  WorkspacePreset? get _base => widget.preset ?? widget.seed;

  @override
  void initState() {
    super.initState();
    final base = _base;
    _nameCtrl = TextEditingController(text: base?.name ?? '');
    _descCtrl = TextEditingController(text: base?.description ?? '');
    _category = base?.category ?? 'operacional';
    _icon = base?.icon ?? 'workspaces_rounded';
    _color = base?.color ?? '#3B82F6';
    _cardType = base?.cardType ?? 'generic';
    _assignmentMode = base?.assignmentMode ?? 'operator_pool';
    _workflowEnabled = base?.workflowEnabled ?? true;
    _isShared = widget.preset?.isShared ?? true;
    _stages = base?.freshStages() ?? _defaultStages();
  }

  static List<WorkflowStageDraft> _defaultStages() => [
        WorkflowStageDraft(
            status: 'Novo',
            color: '#3B82F6',
            icon: 'add_circle',
            isInitial: true),
        WorkflowStageDraft(
            status: 'Em andamento', color: '#F59E0B', icon: 'autorenew'),
        WorkflowStageDraft(
            status: 'Concluído',
            color: '#22C55E',
            icon: 'task_alt',
            isFinal: true),
        WorkflowStageDraft(
            status: 'Cancelado',
            color: '#EF4444',
            icon: 'cancel',
            isCancelled: true),
      ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String? _validateStages() {
    if (!_workflowEnabled) return null;
    if (_stages.isEmpty) return 'Adicione pelo menos uma etapa ao funil.';

    final names = <String>{};
    for (final stage in _stages) {
      final trimmed = stage.status.trim();
      if (trimmed.isEmpty) return 'Existe uma etapa sem nome.';
      if (!names.add(trimmed.toLowerCase())) {
        return 'A etapa "$trimmed" está repetida.';
      }
    }
    if (!_stages.any((s) => !s.isCancelled)) {
      return 'O funil precisa de pelo menos uma etapa ativa.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final stageError = _validateStages();
    if (stageError != null) {
      _snack(stageError, isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(workspacePresetServiceProvider).save(
            id: widget.preset?.id,
            name: _nameCtrl.text,
            description: _descCtrl.text,
            category: _category,
            icon: _icon,
            color: _color,
            cardType: _cardType,
            workflowEnabled: _workflowEnabled,
            assignmentMode: _workflowEnabled ? _assignmentMode : 'manual',
            stages: _workflowEnabled ? _stages : const [],
            isShared: _isShared,
          );

      if (!mounted) return;
      _snack(widget.preset == null
          ? 'Preset criado com sucesso.'
          : 'Preset atualizado.');
      context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(describePresetError(e), isError: true);
      }
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.preset != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Preset' : 'Novo Preset'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: ResponsiveWidthContainer(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              WorkspacePreviewCard(
                name: _nameCtrl.text,
                description: _descCtrl.text,
                icon: _icon,
                color: _color,
                category: _category,
                workflowEnabled: _workflowEnabled,
                stageCount: _stages.length,
              ),
              const SizedBox(height: 24),
              _label(theme, 'Nome do preset'),
              TextFormField(
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                decoration: _inputDecoration('Ex: Aprovação de Compras'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Nome é obrigatório'
                    : null,
              ),
              const SizedBox(height: 16),
              _label(theme, 'Descrição'),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration:
                    _inputDecoration('Para que serve este modelo de workspace'),
              ),
              const SizedBox(height: 24),
              _label(theme, 'Aparência'),
              WorkspaceAppearanceRow(
                icon: _icon,
                color: _color,
                onIconChanged: (v) => setState(() => _icon = v),
                onColorChanged: (v) => setState(() => _color = v),
              ),
              const SizedBox(height: 24),
              _label(theme, 'Categoria'),
              WorkspaceCategorySelector(
                selected: _category,
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Habilitar workflow'),
                subtitle: Text(_workflowEnabled
                    ? 'Cards, Kanban e acompanhamento operacional'
                    : 'Apenas mensagens, anúncios e enquetes'),
                value: _workflowEnabled,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _workflowEnabled = v),
              ),
              if (_workflowEnabled) ...[
                const SizedBox(height: 8),
                _label(theme, 'Formulário do card'),
                _buildCardTypeSelector(theme),
                const SizedBox(height: 24),
                _label(theme, 'Modo de atribuição'),
                _buildAssignmentSelector(theme),
                const SizedBox(height: 24),
                _label(theme, 'Etapas do Kanban'),
                WorkflowStageBuilder(
                  stages: _stages,
                  onChanged: (s) => setState(() => _stages = s),
                ),
              ],
              const Divider(height: 32),
              SwitchListTile(
                title: const Text('Compartilhar com a empresa'),
                subtitle: Text(_isShared
                    ? 'Qualquer gestor pode usar este preset'
                    : 'Somente você enxerga este preset'),
                value: _isShared,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _isShared = v),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? 'Salvar alterações' : 'Criar preset'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _buildCardTypeSelector(ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: WorkflowCardType.values.map((type) {
        final selected = _cardType == type.value;
        return ChoiceChip(
          selected: selected,
          label: Text(type.label),
          onSelected: (_) => setState(() => _cardType = type.value),
        );
      }).toList(),
    );
  }

  Widget _buildAssignmentSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              selected: _assignmentMode == 'single_operator',
              avatar: const Icon(Icons.person_outline, size: 18),
              label: const Text('1 operador'),
              onSelected: (_) =>
                  setState(() => _assignmentMode = 'single_operator'),
            ),
            ChoiceChip(
              selected: _assignmentMode == 'operator_pool',
              avatar: const Icon(Icons.groups_outlined, size: 18),
              label: const Text('Equipe'),
              onSelected: (_) =>
                  setState(() => _assignmentMode = 'operator_pool'),
            ),
            ChoiceChip(
              selected: _assignmentMode == 'manual',
              avatar: const Icon(Icons.campaign_outlined, size: 18),
              label: const Text('Sem fila'),
              onSelected: (_) => setState(() => _assignmentMode = 'manual'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          switch (_assignmentMode) {
            'single_operator' =>
              'Cards novos já nascem atribuídos ao operador escolhido no workspace.',
            'manual' =>
              'Sem fila de atendimento — indicado para canais de aviso.',
            _ => 'Cards novos ficam sem responsável até alguém da equipe assumir.',
          },
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
