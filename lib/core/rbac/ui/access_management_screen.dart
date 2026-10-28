import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/rbac_permission.dart';
import '../models/rbac_role.dart';
import '../models/user_role_assignment.dart';
import '../providers/rbac_provider.dart';
import '../services/rbac_repository.dart';

/// Rótulos e ícones amigáveis por módulo de permissão.
const _moduleMeta = <String, ({String label, IconData icon})>{
  'admin_panel': (label: 'Painel de Administração', icon: Icons.admin_panel_settings_outlined),
  'admin_users': (label: 'Gestão de Usuários', icon: Icons.people_alt_outlined),
  'admin_cadastro': (label: 'Novo Cadastro', icon: Icons.person_add_outlined),
  'admin_acessos': (label: 'Acessos (Perfis & Permissões)', icon: Icons.lock_person_outlined),
  'admin_auditoria': (label: 'Auditoria', icon: Icons.policy_outlined),
  'admin_moderacao': (label: 'Moderação', icon: Icons.shield_outlined),
  'admin_relatorios': (label: 'Relatórios de Uso', icon: Icons.analytics_outlined),
  'admin_ai_keys': (label: 'Chaves de IA', icon: Icons.vpn_key),
  'admin_backup': (label: 'Backup', icon: Icons.save_alt_rounded),
  'location': (label: 'Localização da Equipe', icon: Icons.location_on_rounded),
  'workflow': (label: 'Workflow', icon: Icons.account_tree_outlined),
  'comunicacao_canais': (label: 'Canais de Comunicação', icon: Icons.campaign_outlined),
  'comunicacao_conversas': (label: 'Conversas Diretas', icon: Icons.chat_bubble_outline_rounded),
  'comunicacao_chamadas': (label: 'Chamadas de Vídeo', icon: Icons.videocam_outlined),
  'rh_banco_talentos': (label: 'Banco de Talentos', icon: Icons.badge_outlined),
  'rh_funcionarios': (label: 'Quadro de Funcionários', icon: Icons.contact_page_outlined),
  'rh_documentos': (label: 'Documentos', icon: Icons.folder_shared_outlined),
  'rh_onboarding': (label: 'Onboarding', icon: Icons.assignment_outlined),
  'rh_alertas': (label: 'Alertas RH', icon: Icons.warning_amber_rounded),
  'rh_ponto': (label: 'Controle de Ponto', icon: Icons.access_time_outlined),
  'rh_holerites': (label: 'Holerites', icon: Icons.receipt_long_outlined),
  'rh_desempenho': (label: 'Desempenho', icon: Icons.trending_up_outlined),
  'rh_beneficios': (label: 'Benefícios', icon: Icons.card_giftcard_outlined),
  'rh_ausencias': (label: 'Ausências e Férias', icon: Icons.event_busy_outlined),
  'rh_automacoes': (label: 'Comunicação e Automações', icon: Icons.mark_email_read_outlined),
  'fin_dashboard': (label: 'Visão Geral Financeiro', icon: Icons.account_balance_wallet_outlined),
  'fin_pagar': (label: 'Contas a Pagar', icon: Icons.money_off_outlined),
  'fin_receber': (label: 'Contas a Receber', icon: Icons.attach_money_outlined),
  'fin_movimentacoes': (label: 'Fluxo de Caixa', icon: Icons.sync_alt_outlined),
  'helpdesk': (label: 'Helpdesk TI', icon: Icons.support_agent_outlined),
};

({String label, IconData icon}) _metaFor(String module) =>
    _moduleMeta[module] ?? (label: module.toUpperCase(), icon: Icons.tune_rounded);

String _actionLabel(String action) => switch (action) {
      'view' => 'Visualizar',
      'manage' => 'Gerenciar',
      _ => action[0].toUpperCase() + action.substring(1),
    };

enum _Mode { perfis, usuarios }

/// Painel unificado de Gerenciamento de Acessos (RBAC).
/// Sem Scaffold — pensado para viver como aba dentro do Painel Admin.
class AccessManagementScreen extends ConsumerStatefulWidget {
  const AccessManagementScreen({super.key});

  @override
  ConsumerState<AccessManagementScreen> createState() =>
      _AccessManagementScreenState();
}

class _AccessManagementScreenState
    extends ConsumerState<AccessManagementScreen> {
  _Mode _mode = _Mode.perfis;

  bool _loading = true;
  String? _error;
  List<RbacRole> _roles = [];
  List<RbacPermission> _permissions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(rbacRepositoryProvider);
      final results = await Future.wait([
        repo.getSystemPermissions(),
        repo.getOrganizationRoles(),
      ]);
      if (!mounted) return;
      setState(() {
        _permissions = results[0] as List<RbacPermission>;
        _roles = results[1] as List<RbacRole>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Cabeçalho compacto + alternador ──────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gerenciamento de Acessos',
                      style: GoogleFonts.outfit(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                  Text(
                    _mode == _Mode.perfis
                        ? 'Defina o que cada perfil pode acessar.'
                        : 'Atribua perfis aos colaboradores.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              SegmentedButton<_Mode>(
                segments: const [
                  ButtonSegment(
                    value: _Mode.perfis,
                    label: Text('Perfis & Permissões'),
                    icon: Icon(Icons.shield_outlined),
                  ),
                  ButtonSegment(
                    value: _Mode.usuarios,
                    label: Text('Usuários'),
                    icon: Icon(Icons.group_outlined),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody(theme)),
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    if (_roles.isEmpty) {
      return _EmptyRolesState(onCreated: _load);
    }
    return switch (_mode) {
      _Mode.perfis => _RolesAndPermissions(
          roles: _roles,
          permissions: _permissions,
          onRolesChanged: _load,
        ),
      _Mode.usuarios => _UsersAndRoles(roles: _roles),
    };
  }
}

// ══════════════════════════════════════════════════════════════
//  PERFIS & PERMISSÕES
// ══════════════════════════════════════════════════════════════

class _RolesAndPermissions extends ConsumerStatefulWidget {
  final List<RbacRole> roles;
  final List<RbacPermission> permissions;
  final Future<void> Function() onRolesChanged;

  const _RolesAndPermissions({
    required this.roles,
    required this.permissions,
    required this.onRolesChanged,
  });

  @override
  ConsumerState<_RolesAndPermissions> createState() =>
      _RolesAndPermissionsState();
}

class _RolesAndPermissionsState extends ConsumerState<_RolesAndPermissions> {
  RbacRole? _selected;
  Set<String> _granted = {};
  Set<String> _original = {};
  bool _loadingPerms = false;
  bool _saving = false;

  bool get _dirty =>
      _granted.length != _original.length ||
      !_granted.containsAll(_original);

  @override
  void initState() {
    super.initState();
    _select(widget.roles.first);
  }

  @override
  void didUpdateWidget(covariant _RolesAndPermissions old) {
    super.didUpdateWidget(old);
    // Se a lista de perfis mudou e o selecionado sumiu, volta pro primeiro.
    if (_selected != null && !widget.roles.any((r) => r.id == _selected!.id)) {
      if (widget.roles.isNotEmpty) _select(widget.roles.first);
    }
  }

  Future<void> _select(RbacRole role) async {
    setState(() {
      _selected = role;
      _loadingPerms = true;
    });
    try {
      final ids =
          await ref.read(rbacRepositoryProvider).getRolePermissions(role.id);
      if (!mounted) return;
      setState(() {
        _granted = ids.toSet();
        _original = ids.toSet();
        _loadingPerms = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPerms = false);
    }
  }

  Future<void> _save() async {
    final role = _selected;
    if (role == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(rbacRepositoryProvider)
          .updateRolePermissions(role.id, _granted.toList());
      ref.invalidate(myPermissionsProvider);
      if (!mounted) return;
      setState(() {
        _original = {..._granted};
        _saving = false;
      });
      _snack('Permissões de "${role.name}" salvas.', ok: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Erro ao salvar: $e', ok: false);
    }
  }

  Future<void> _createRole() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateRoleDialog(),
    );
    if (created == true) await widget.onRolesChanged();
  }

  Future<void> _deleteRole(RbacRole role) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir "${role.name}"?'),
        content: const Text(
            'O perfil e suas permissões serão removidos. Usuários com este perfil perdem os acessos concedidos por ele.'),
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
    if (ok != true) return;
    try {
      await ref.read(rbacRepositoryProvider).deleteRole(role.id);
      _snack('Perfil excluído.', ok: true);
      await widget.onRolesChanged();
    } catch (e) {
      _snack('Erro: $e', ok: false);
    }
  }

  void _snack(String msg, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 760;
        final rolesPanel = _RolesList(
          roles: widget.roles,
          selectedId: _selected?.id,
          horizontal: !wide,
          onSelect: _select,
          onCreate: _createRole,
          onDelete: _deleteRole,
        );
        final matrix = _buildMatrix(context);

        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 280, child: rolesPanel),
                const SizedBox(width: 20),
                Expanded(child: matrix),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              rolesPanel,
              const SizedBox(height: 16),
              Expanded(child: matrix),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMatrix(BuildContext context) {
    final theme = Theme.of(context);
    final role = _selected;
    if (role == null) {
      return const SizedBox.shrink();
    }

    // Agrupa permissões por módulo preservando a ordem de _moduleMeta.
    final grouped = <String, List<RbacPermission>>{};
    for (final p in widget.permissions) {
      (grouped[p.module] ??= []).add(p);
    }
    final modules = grouped.keys.toList()
      ..sort((a, b) {
        final ia = _moduleMeta.keys.toList().indexOf(a);
        final ib = _moduleMeta.keys.toList().indexOf(b);
        return (ia == -1 ? 999 : ia).compareTo(ib == -1 ? 999 : ib);
      });

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header do perfil selecionado
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(role.name,
                                style: GoogleFonts.outfit(
                                    fontSize: 18, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (role.isSystem) ...[
                            const SizedBox(width: 8),
                            _SystemChip(theme: theme),
                          ],
                        ],
                      ),
                      if (role.description != null)
                        Text(role.description!,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (_dirty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('Alterações não salvas',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600)),
                  ),
                FilledButton.icon(
                  onPressed: (_saving || !_dirty) ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Salvar'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loadingPerms
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final m in modules)
                        _ModuleCard(
                          module: m,
                          perms: grouped[m]!,
                          granted: _granted,
                          onToggle: (id, val) => setState(() {
                            if (val) {
                              _granted.add(id);
                            } else {
                              _granted.remove(id);
                            }
                          }),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final String module;
  final List<RbacPermission> perms;
  final Set<String> granted;
  final void Function(String id, bool value) onToggle;

  const _ModuleCard({
    required this.module,
    required this.perms,
    required this.granted,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = _metaFor(module);
    final activeCount = perms.where((p) => granted.contains(p.id)).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(meta.icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(meta.label,
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                Text('$activeCount/${perms.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          for (final p in perms)
            SwitchListTile(
              dense: true,
              value: granted.contains(p.id),
              onChanged: (v) => onToggle(p.id, v),
              title: Text(_actionLabel(p.action),
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: p.description != null
                  ? Text(p.description!, style: const TextStyle(fontSize: 12))
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
        ],
      ),
    );
  }
}

class _RolesList extends StatelessWidget {
  final List<RbacRole> roles;
  final String? selectedId;
  final bool horizontal;
  final void Function(RbacRole) onSelect;
  final VoidCallback onCreate;
  final void Function(RbacRole) onDelete;

  const _RolesList({
    required this.roles,
    required this.selectedId,
    required this.horizontal,
    required this.onSelect,
    required this.onCreate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Layout compacto (mobile): chips horizontais + botão criar.
    if (horizontal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Perfis',
                  style: GoogleFonts.outfit(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Novo'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final r in roles)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: r.id == selectedId,
                      onSelected: (_) => onSelect(r),
                      avatar: r.isSystem
                          ? const Icon(Icons.lock_outline, size: 14)
                          : null,
                      label: Text(r.name),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    // Layout amplo (desktop): painel lateral.
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Text('Perfis de Acesso',
                    style: GoogleFonts.outfit(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Criar novo perfil',
                  onPressed: onCreate,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: roles.length,
              itemBuilder: (context, i) {
                final r = roles[i];
                final selected = r.id == selectedId;
                return ListTile(
                  selected: selected,
                  selectedTileColor:
                      theme.colorScheme.primary.withValues(alpha: 0.1),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      r.isSystem ? Icons.verified_user : Icons.group,
                      size: 16,
                      color: selected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: Text(r.name,
                      style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.w500)),
                  subtitle: r.description != null
                      ? Text(r.description!,
                          maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  trailing: r.isSystem
                      ? Tooltip(
                          message: 'Perfil de sistema',
                          child: Icon(Icons.lock_outline,
                              size: 16, color: theme.colorScheme.outline),
                        )
                      : IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Excluir perfil',
                          onPressed: () => onDelete(r),
                        ),
                  onTap: () => onSelect(r),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateRoleDialog extends ConsumerStatefulWidget {
  const _CreateRoleDialog();

  @override
  ConsumerState<_CreateRoleDialog> createState() => _CreateRoleDialogState();
}

class _CreateRoleDialogState extends ConsumerState<_CreateRoleDialog> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Informe o nome do perfil');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(rbacRepositoryProvider)
          .createRole(_name.text.trim(), description: _desc.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '$e'.replaceFirst('PostgrestException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo perfil de acesso'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Nome', hintText: 'Ex.: Recepção, Financeiro'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(
                labelText: 'Descrição (opcional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Criar'),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  USUÁRIOS & PERFIS
// ══════════════════════════════════════════════════════════════

class _UsersAndRoles extends ConsumerStatefulWidget {
  final List<RbacRole> roles;
  const _UsersAndRoles({required this.roles});

  @override
  ConsumerState<_UsersAndRoles> createState() => _UsersAndRolesState();
}

class _UsersAndRolesState extends ConsumerState<_UsersAndRoles> {
  late Future<List<UserRoleAssignment>> _future;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = ref.read(rbacRepositoryProvider).getUsersWithRoles();
  }

  void _reload() {
    setState(() {
      _future = ref.read(rbacRepositoryProvider).getUsersWithRoles();
    });
  }

  Future<void> _editRoles(UserRoleAssignment u) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AssignRolesSheet(user: u, roles: widget.roles),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rolesById = {for (final r in widget.roles) r.id: r};

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Buscar colaborador...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<UserRoleAssignment>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _ErrorState(
                    message: '${snap.error}', onRetry: _reload);
              }
              final users = (snap.data ?? [])
                  .where((u) => u.fullName.toLowerCase().contains(_search))
                  .toList();
              if (users.isEmpty) {
                return Center(
                  child: Text('Nenhum colaborador encontrado.',
                      style: TextStyle(color: theme.colorScheme.outline)),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _UserRoleCard(
                    user: users[i],
                    rolesById: rolesById,
                    onEdit: () => _editRoles(users[i]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UserRoleCard extends StatelessWidget {
  final UserRoleAssignment user;
  final Map<String, RbacRole> rolesById;
  final VoidCallback onEdit;

  const _UserRoleCard({
    required this.user,
    required this.rolesById,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = user.roleIds
        .map((id) => rolesById[id])
        .whereType<RbacRole>()
        .toList();

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage: user.avatarUrl != null
                  ? CachedNetworkImageProvider(user.avatarUrl!, maxWidth: 320)
                  : null,
              child: user.avatarUrl == null
                  ? Text(user.initials,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                      overflow: TextOverflow.ellipsis),
                  if (user.jobTitle != null)
                    Text(user.jobTitle!.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  if (roles.isEmpty)
                    Text('Sem perfil atribuído',
                        style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.error))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final r in roles)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Text(r.name,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Perfis'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignRolesSheet extends ConsumerStatefulWidget {
  final UserRoleAssignment user;
  final List<RbacRole> roles;
  const _AssignRolesSheet({required this.user, required this.roles});

  @override
  ConsumerState<_AssignRolesSheet> createState() => _AssignRolesSheetState();
}

class _AssignRolesSheetState extends ConsumerState<_AssignRolesSheet> {
  late Set<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.user.roleIds.toSet();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(rbacRepositoryProvider)
          .setUserRoles(widget.user.userId, _selected.toList());
      // Se o usuário editado for o próprio logado, atualiza a sidebar.
      ref.invalidate(myPermissionsProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Perfis de ${widget.user.fullName}',
                style: GoogleFonts.outfit(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Marque os perfis que este colaborador terá.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final r in widget.roles)
                      CheckboxListTile(
                        value: _selected.contains(r.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(r.id);
                          } else {
                            _selected.remove(r.id);
                          }
                        }),
                        title: Text(r.name),
                        subtitle: r.description != null
                            ? Text(r.description!,
                                maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                        secondary: r.isSystem
                            ? Icon(Icons.lock_outline,
                                size: 18, color: theme.colorScheme.outline)
                            : null,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  ESTADOS AUXILIARES
// ══════════════════════════════════════════════════════════════

class _SystemChip extends StatelessWidget {
  final ThemeData theme;
  const _SystemChip({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('SISTEMA',
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSecondaryContainer)),
    );
  }
}

class _EmptyRolesState extends ConsumerStatefulWidget {
  final Future<void> Function() onCreated;
  const _EmptyRolesState({required this.onCreated});

  @override
  ConsumerState<_EmptyRolesState> createState() => _EmptyRolesStateState();
}

class _EmptyRolesStateState extends ConsumerState<_EmptyRolesState> {
  bool _busy = false;

  Future<void> _setup() async {
    setState(() => _busy = true);
    try {
      await ref.read(rbacRepositoryProvider).setupDefaultRoles();
      await widget.onCreated();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_moon_outlined,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Nenhum perfil configurado',
                style: GoogleFonts.outfit(
                    fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Crie os perfis-padrão (Super Admin, RH, Gestor e Colaborador) '
              'com permissões já definidas. Você pode ajustá-los depois.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _setup,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_fix_high_rounded),
              label: const Text('Criar perfis padrão'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Não foi possível carregar',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
