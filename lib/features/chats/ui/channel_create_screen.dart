import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/channels/models/workspace_preset.dart';
import 'package:alinha_ja/features/channels/providers/channels_list_provider.dart';
import 'package:alinha_ja/features/channels/providers/workspace_presets_provider.dart';
import 'package:alinha_ja/features/channels/ui/widgets/workflow_stage_builder.dart';
import 'package:alinha_ja/features/channels/ui/widgets/workspace_identity_fields.dart';
import 'package:alinha_ja/features/channels/ui/widgets/workspace_membership_section.dart';
import 'package:alinha_ja/features/channels/ui/workspace_preset_editor_screen.dart';
import 'package:alinha_ja/features/channels/ui/workspace_preset_manager_screen.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';

/// Criação de workspace a partir de um preset.
///
/// Os "tipos de workflow" deixaram de ser um mapa fixo no código: vêm de
/// `public.workspace_presets`, então a empresa cria e mantém os próprios
/// modelos. O preset é só o ponto de partida — tudo (identidade, formulário do
/// card, etapas, operadores) continua ajustável antes de confirmar.
class ChannelCreateScreen extends ConsumerStatefulWidget {
  const ChannelCreateScreen({super.key});

  @override
  ConsumerState<ChannelCreateScreen> createState() =>
      _ChannelCreateScreenState();
}

class _ChannelCreateScreenState extends ConsumerState<ChannelCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String? _presetId;
  String _category = 'operacional';
  String _icon = 'workspaces_rounded';
  String _color = '#3B82F6';
  String _cardType = 'generic';
  String _assignmentMode = 'operator_pool';
  bool _workflowEnabled = true;
  List<WorkflowStageDraft> _stages = [];

  /// `true` enquanto o usuário não digitou um nome — permite que a escolha do
  /// preset preencha o campo sem sobrescrever o que já foi digitado.
  bool _nameUntouched = true;

  bool _isLoading = false;
  bool _presetApplied = false;

  List<UserModel> _contacts = [];
  bool _isLoadingContacts = false;
  final Set<String> _selectedIds = {};
  final Set<String> _operatorIds = {};
  bool _addEveryone = true;

  @override
  void initState() {
    super.initState();
    _checkSecurity();
    _loadContacts();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _checkSecurity() {
    final user = ref.read(currentUserProvider).value;
    if (user == null || !AppPermissions.canCreateChannel(user.roleLevel)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Acesso Negado: Apenas TI ou Diretores podem criar canais.')),
        );
        context.pop();
      });
    }
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoadingContacts = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      final data = await supabase
          .from('users')
          .select('${UserModel.selectColumns}, branches(name)')
          .neq('id', userId ?? '')
          .eq('is_active', true)
          .order('full_name');

      if (!mounted) return;
      setState(() {
        _contacts = (data as List)
            .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
            .toList();
        _isLoadingContacts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingContacts = false);
    }
  }

  void _applyPreset(WorkspacePreset preset) {
    setState(() {
      _presetId = preset.id;
      _category = preset.category;
      _icon = preset.icon;
      _color = preset.color;
      _cardType = preset.cardType;
      _workflowEnabled = preset.workflowEnabled;
      _assignmentMode = preset.assignmentMode == 'manual'
          ? 'operator_pool'
          : preset.assignmentMode;
      _stages = preset.freshStages();
      if (_nameUntouched) {
        _nameCtrl.text = preset.name;
      }
      if (_descCtrl.text.trim().isEmpty && preset.description != null) {
        _descCtrl.text = preset.description!;
      }
      _presetApplied = true;
    });
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

  Future<void> _createChannel() async {
    if (!_formKey.currentState!.validate()) return;

    final stageError = _validateStages();
    if (stageError != null) {
      _snack(stageError, isError: true);
      return;
    }

    if (_workflowEnabled &&
        _assignmentMode == 'single_operator' &&
        _operatorIds.length != 1) {
      _snack('Escolha exatamente 1 operador para este canal.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser!.id;
      final operatorIds = _workflowEnabled ? _operatorIds.toList() : <String>[];
      final defaultOperatorId =
          _assignmentMode == 'single_operator' && operatorIds.isNotEmpty
              ? operatorIds.first
              : null;

      final memberIds = <String>{
        if (_addEveryone) ..._contacts.map((u) => u.id) else ..._selectedIds,
        userId,
        ...operatorIds,
      }.toList();

      await supabase.rpc('create_workspace', params: {
        'p_name': _nameCtrl.text.trim(),
        'p_description': _descCtrl.text.trim(),
        'p_metadata': <String, dynamic>{
          'workspace': 'shineray_operations',
          'workflow_enabled': _workflowEnabled,
          'posting_permission': 'everyone',
          'card_type': _cardType,
          'category': _category,
          'assignment_mode': _workflowEnabled ? _assignmentMode : 'manual',
          'operator_ids': operatorIds,
          'default_operator_id': defaultOperatorId,
          'operator_count': operatorIds.length,
          'color': _color,
          'icon': _icon,
        },
        'p_member_ids': memberIds,
        'p_status_config': _workflowEnabled ? stagesToJson(_stages) : const [],
        'p_preset_id': _presetId,
      });

      if (!mounted) return;
      ref.invalidate(channelsListProvider);
      ref.invalidate(workspacePresetsProvider);
      _snack('Canal "${_nameCtrl.text.trim()}" criado com sucesso!');
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Erro ao criar canal: ${describePresetError(e)}', isError: true);
    }
  }

  Future<void> _saveAsPreset() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkspacePresetEditorScreen(
          seed: WorkspacePreset(
            id: '',
            name: _nameCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            category: _category,
            icon: _icon,
            color: _color,
            cardType: _cardType,
            workflowEnabled: _workflowEnabled,
            assignmentMode: _assignmentMode,
            stages: _stages.map((s) => s.detached()).toList(),
          ),
        ),
      ),
    );
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presetsAsync = ref.watch(workspacePresetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo Workspace'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            IconButton(
              tooltip: 'Salvar esta configuração como preset',
              onPressed: _saveAsPreset,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
            IconButton(
              tooltip: 'Gerenciar presets',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const WorkspacePresetManagerScreen()),
              ),
              icon: const Icon(Icons.tune),
            ),
          ],
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
              _label(theme, 'Começar a partir de um preset'),
              presetsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text(
                  'Não foi possível carregar os presets: ${describePresetError(e)}',
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
                data: (presets) => _buildPresetPicker(theme, presets),
              ),
              const SizedBox(height: 24),
              _label(theme, 'Nome do workspace'),
              TextFormField(
                controller: _nameCtrl,
                onChanged: (v) => setState(() => _nameUntouched = v.isEmpty),
                decoration: _inputDecoration('Ex: Liberação Contas a Pagar'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Nome é obrigatório' : null,
              ),
              const SizedBox(height: 16),
              _label(theme, 'Descrição'),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: _inputDecoration('Descreva o propósito deste canal'),
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
                    ? 'Cards e acompanhamento operacional'
                    : 'Apenas mensagens, anúncios e enquetes'),
                value: _workflowEnabled,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() {
                  _workflowEnabled = v;
                  if (v && _stages.isEmpty) {
                    _stages = _fallbackStages();
                  }
                }),
              ),
              if (_workflowEnabled) ...[
                const SizedBox(height: 16),
                _label(theme, 'Etapas do Kanban'),
                WorkflowStageBuilder(
                  stages: _stages,
                  onChanged: (s) => setState(() => _stages = s),
                ),
              ],
              const Divider(height: 32),
              WorkspaceMembershipSection(
                contacts: _contacts,
                isLoadingContacts: _isLoadingContacts,
                addEveryone: _addEveryone,
                onAddEveryoneChanged: (v) =>
                    setState(() => _addEveryone = v),
                selectedIds: _selectedIds,
                onSelectionChanged: () => setState(() {}),
                showOperators: _workflowEnabled,
                assignmentMode: _assignmentMode,
                onAssignmentModeChanged: (v) =>
                    setState(() => _assignmentMode = v),
                operatorIds: _operatorIds,
                onOperatorsChanged: () => setState(() {}),
                currentUser: ref.watch(currentUserProvider).valueOrNull,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _isLoading ? null : _createChannel,
                icon: const Icon(Icons.add),
                label: const Text('Criar Workspace'),
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

  static List<WorkflowStageDraft> _fallbackStages() => [
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

  Widget _buildPresetPicker(ThemeData theme, List<WorkspacePreset> presets) {
    if (presets.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                  'Nenhum preset disponível — monte as etapas manualmente abaixo.'),
            ),
          ],
        ),
      );
    }

    // Primeiro toque na tela: adota o preset mais usado, para o formulário já
    // nascer preenchido em vez de exigir uma escolha antes de qualquer coisa.
    if (!_presetApplied) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_presetApplied) _applyPreset(presets.first);
      });
    }

    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final preset = presets[index];
          final selected = _presetId == preset.id;
          final accent = preset.colorValue;

          return SizedBox(
            width: 190,
            child: InkWell(
              onTap: () => _applyPreset(preset),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? accent
                        : theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.6),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(preset.iconData, color: accent, size: 22),
                        const Spacer(),
                        if (selected)
                          Icon(Icons.check_circle, color: accent, size: 18),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      preset.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      preset.workflowEnabled
                          ? '${preset.stages.length} etapas · ${preset.categoryLabel}'
                          : 'Sem workflow · ${preset.categoryLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
