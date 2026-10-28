import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/channels/models/workspace_preset.dart';
import 'package:alinha_ja/features/channels/providers/active_channel_provider.dart';
import 'package:alinha_ja/features/channels/providers/channel_info_provider.dart';
import 'package:alinha_ja/features/channels/providers/channels_list_provider.dart';
import 'package:alinha_ja/features/channels/providers/workspace_presets_provider.dart';
import 'package:alinha_ja/features/channels/ui/widgets/workflow_stage_builder.dart';
import 'package:alinha_ja/features/channels/ui/widgets/workspace_identity_fields.dart';
import 'package:alinha_ja/features/channels/ui/workspace_preset_editor_screen.dart';
import 'package:alinha_ja/features/workflow/models/workflow_enums.dart';
import 'package:alinha_ja/features/workflow/providers/workflow_provider.dart';

/// Edição completa de um workspace já criado.
///
/// Até aqui só era possível trocar nome e descrição: categoria, ícone, cor e
/// principalmente as etapas do Kanban ficavam congeladas desde a criação. Esta
/// tela fecha essa lacuna chamando `update_workspace`, que sincroniza as etapas
/// e migra os cards afetados dentro da mesma transação.
class WorkspaceEditScreen extends ConsumerStatefulWidget {
  final String channelId;
  final String channelName;

  const WorkspaceEditScreen({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  ConsumerState<WorkspaceEditScreen> createState() =>
      _WorkspaceEditScreenState();
}

class _WorkspaceEditScreenState extends ConsumerState<WorkspaceEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _category = 'operacional';
  String _icon = 'workspaces_rounded';
  String _color = '#3B82F6';
  String _cardType = 'generic';
  bool _workflowEnabled = true;
  bool _adminsOnlyPosting = false;
  bool _isPrivate = false;
  List<WorkflowStageDraft> _stages = [];

  /// Contagem de cards por etapa (chave em minúsculas), usada para avisar
  /// antes de remover uma etapa ocupada.
  Map<String, int> _cardCounts = {};

  /// Redirecionamentos escolhidos pelo usuário ao remover etapas com cards.
  final List<Map<String, String>> _migrations = [];

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final channel = await supabase
          .from('channels')
          .select('name, description, metadata, posting_permission, visibility')
          .eq('id', widget.channelId)
          .maybeSingle();

      if (channel == null) {
        throw Exception('Workspace não encontrado.');
      }

      final statuses = await supabase
          .from('workflow_status_config')
          .select('*')
          .eq('channel_id', widget.channelId)
          .order('status_order');

      final usage = await supabase
          .rpc('workspace_status_usage', params: {'p_channel_id': widget.channelId});

      final metadata =
          Map<String, dynamic>.from(channel['metadata'] as Map? ?? {});

      if (!mounted) return;
      setState(() {
        _nameCtrl.text = channel['name']?.toString() ?? widget.channelName;
        _descCtrl.text = channel['description']?.toString() ?? '';
        _category = metadata['category']?.toString() ?? 'operacional';
        _icon = metadata['icon']?.toString() ?? 'workspaces_rounded';
        _color = metadata['color']?.toString() ?? '#3B82F6';
        _cardType = metadata['card_type']?.toString() ?? 'generic';
        _workflowEnabled = metadata['workflow_enabled'] == true ||
            metadata['workflow_enabled']?.toString() == 'true';
        _adminsOnlyPosting =
            channel['posting_permission']?.toString() == 'admins';
        // A coluna só existe após a migration 20260821100000; em banco antigo
        // o campo vem ausente e o workspace segue público, como antes.
        _isPrivate = channel['visibility']?.toString() == 'private';
        _stages = (statuses as List)
            .map((e) =>
                WorkflowStageDraft.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _cardCounts = {
          for (final row in (usage as List? ?? []))
            (row['status']?.toString() ?? '').toLowerCase().trim():
                int.tryParse(row['card_count']?.toString() ?? '0') ?? 0,
        };
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = describePresetError(e);
        _loading = false;
      });
    }
  }

  /// Chamado pelo builder antes de remover uma etapa. Quando ela ainda tem
  /// cards, pede o destino e registra a migração que vai junto no salvamento.
  Future<bool> _handleStageRemoval(
      WorkflowStageDraft stage, List<WorkflowStageDraft> remaining) async {
    final count = _cardCounts[stage.status.toLowerCase().trim()] ?? 0;
    if (count == 0) return true;

    final targets = remaining
        .where((s) => s.status.trim().isNotEmpty && s.status != stage.status)
        .toList();

    if (targets.isEmpty) {
      _snack('Não há outra etapa para receber os $count card(s).',
          isError: true);
      return false;
    }

    final destination = await showDialog<WorkflowStageDraft>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mover $count card${count == 1 ? '' : 's'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'A etapa "${stage.status}" ainda tem $count card(s). '
                'Escolha para onde eles vão antes de removê-la:'),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: Column(
                  children: targets
                      .map((t) => ListTile(
                            dense: true,
                            leading: Icon(t.iconData, color: t.colorValue),
                            title: Text(t.status),
                            onTap: () => Navigator.pop(ctx, t),
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
        ],
      ),
    );

    if (destination == null) return false;

    _migrations.add({
      'from_status': stage.status,
      'to_status': destination.status,
    });
    return true;
  }

  String? _validateStages() {
    if (!_workflowEnabled) return null;
    if (_stages.isEmpty) return 'O workflow precisa de pelo menos uma etapa.';

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
      // As migrações precisam apontar para etapas que ainda existem depois da
      // edição; se o destino também foi removido, a RPC recusa a operação.
      final result = await supabase.rpc('update_workspace', params: {
        'p_channel_id': widget.channelId,
        'p_name': _nameCtrl.text.trim(),
        'p_description': _descCtrl.text.trim(),
        'p_metadata': {
          'category': _category,
          'icon': _icon,
          'color': _color,
          'card_type': _cardType,
          'workflow_enabled': _workflowEnabled,
        },
        'p_posting_permission': _adminsOnlyPosting ? 'admins' : 'everyone',
        'p_status_config': _workflowEnabled ? stagesToJson(_stages) : null,
        'p_status_migrations': _migrations,
      });

      // Visibilidade tem RPC própria: acrescentar um parâmetro a
      // `update_workspace` criaria uma sobrecarga ambígua no Postgres, e
      // tornar um workspace público/privado é ato de segurança com entrada
      // auditada separada (ver 20260821100000).
      await supabase.rpc('set_channel_visibility', params: {
        'p_channel_id': widget.channelId,
        'p_visibility': _isPrivate ? 'private' : 'public',
      });

      if (!mounted) return;

      ref.invalidate(channelsListProvider);
      ref.invalidate(channelInfoProvider(widget.channelId));
      ref.invalidate(activeChannelProvider(ChannelArgs(channelId: widget.channelId)));
      ref.invalidate(workflowProvider(widget.channelId));

      final migrated = result is Map
          ? int.tryParse(result['cards_migrated']?.toString() ?? '0') ?? 0
          : 0;
      _snack(migrated > 0
          ? 'Workspace atualizado. $migrated card(s) movidos de etapa.'
          : 'Workspace atualizado.');
      context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(describePresetError(e), isError: true);
      }
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
            postingPermission: _adminsOnlyPosting ? 'admins' : 'everyone',
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
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Workspace'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (!_loading && _loadError == null)
            IconButton(
              tooltip: 'Salvar esta configuração como preset',
              onPressed: _saveAsPreset,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_loadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = null;
                  });
                  _load();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return ResponsiveWidthContainer(
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
            _label(theme, 'Nome do workspace'),
            TextFormField(
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              decoration: _inputDecoration('Nome exibido na lista de canais'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nome é obrigatório' : null,
            ),
            const SizedBox(height: 16),
            _label(theme, 'Descrição'),
            TextFormField(
              controller: _descCtrl,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: _inputDecoration('Propósito deste workspace'),
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
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Workspace privado'),
              subtitle: Text(_isPrivate
                  ? 'Só quem é membro encontra este workspace; entrada por convite'
                  : 'Qualquer pessoa da empresa encontra e pode solicitar entrada'),
              value: _isPrivate,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _isPrivate = v),
            ),
            SwitchListTile(
              title: const Text('Somente admins publicam'),
              subtitle: Text(_adminsOnlyPosting
                  ? 'Membros leem, mas não enviam mensagens'
                  : 'Todos os membros podem publicar'),
              value: _adminsOnlyPosting,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _adminsOnlyPosting = v),
            ),
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
              const SizedBox(height: 16),
              _label(theme, 'Formulário do card'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: WorkflowCardType.values.map((type) {
                  return ChoiceChip(
                    selected: _cardType == type.value,
                    label: Text(type.label),
                    onSelected: (_) => setState(() => _cardType = type.value),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              _label(theme, 'Etapas do Kanban'),
              WorkflowStageBuilder(
                stages: _stages,
                cardCounts: _cardCounts,
                onBeforeRemove: _handleStageRemoval,
                onChanged: (s) => setState(() => _stages = s),
              ),
              if (_migrations.isNotEmpty) ...[
                const SizedBox(height: 12),
                _MigrationSummary(migrations: _migrations),
              ],
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Membros e operadores continuam sendo gerenciados na tela '
                      'de informações do canal.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar alterações'),
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

class _MigrationSummary extends StatelessWidget {
  final List<Map<String, String>> migrations;

  const _MigrationSummary({required this.migrations});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz, size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Text('Cards que serão movidos ao salvar',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ...migrations.map((m) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• ${m['from_status']} → ${m['to_status']}',
                    style: theme.textTheme.bodySmall),
              )),
        ],
      ),
    );
  }
}
