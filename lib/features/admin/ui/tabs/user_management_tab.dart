import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:cached_network_image/cached_network_image.dart';

final adminUsersProvider =
    FutureProvider.autoDispose<List<UserModel>>((ref) async {
  final response = await supabase
      .from('users')
      .select(UserModel.selectWithOrg)
      .order('full_name');

  // CPF/nascimento/sexo/telefone não vêm mais no SELECT: o privilégio de
  // coluna foi revogado para `authenticated` (migrations 20260803170000 e
  // 20260903140000). O painel admin
  // recebe esses campos pela RPC, que confere o papel e registra o acesso em
  // rh_access_log — é o que permite responder a um titular quem consultou
  // seus dados.
  final Map<String, Map<String, dynamic>> piiById = {};
  try {
    final pii = await supabase.rpc('admin_list_users_pii');
    for (final row in (pii as List)) {
      final map = Map<String, dynamic>.from(row as Map);
      final id = map['user_id'] as String?;
      if (id != null) piiById[id] = map;
    }
  } catch (e) {
    // Sem permissão ou RPC ausente: a lista continua funcionando sem os
    // dados sensíveis, em vez de a tela inteira falhar.
    debugPrint('PII de usuários indisponível: $e');
  }

  final List<UserModel> users = [];
  for (final e in response) {
    try {
      final base = UserModel.fromJson(e);
      final pii = piiById[base.id];
      users.add(pii == null
          ? base
          : base.copyWith(
              cpf: pii['cpf'] as String?,
              dataNascimento: pii['data_nascimento'] != null
                  ? DateTime.tryParse(pii['data_nascimento'] as String)
                  : null,
              sexo: pii['sexo'] as String?,
              phone: pii['phone'] as String?,
            ));
    } catch (_) {
      // Ignora registros com id nulo
    }
  }
  return users;
});

enum _UserFilter { all, pending }

class UserManagementTab extends ConsumerStatefulWidget {
  const UserManagementTab({super.key});

  @override
  ConsumerState<UserManagementTab> createState() => _UserManagementTabState();
}

class _UserManagementTabState extends ConsumerState<UserManagementTab> {
  String _searchQuery = '';
  _UserFilter _filter = _UserFilter.all;

  Future<void> _approveUser(UserModel user) async {
    try {
      await supabase.rpc('admin_toggle_user_status', params: {
        'p_target_user_id': user.id,
        'p_is_active': true,
      });

      ref.invalidate(adminUsersProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${user.fullName} aprovado com sucesso!'),
            backgroundColor: AppConstants.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao aprovar: $e'),
            backgroundColor: AppConstants.danger,
          ),
        );
      }
    }
  }

  Future<void> _rejectUser(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar Cadastro?'),
        content: Text(
          'O cadastro de "${user.fullName}" será desativado permanentemente. '
          'O usuário precisará se cadastrar novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppConstants.danger),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Usa RPC SECURITY DEFINER para deletar o registro (bypassa RLS)
      await supabase.rpc('admin_reject_user', params: {
        'p_target_user_id': user.id,
      });

      ref.invalidate(adminUsersProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.fullName} foi rejeitado.'),
            backgroundColor: AppConstants.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao rejeitar: $e'),
            backgroundColor: AppConstants.danger,
          ),
        );
      }
    }
  }

  Future<void> _toggleActive(UserModel user) async {
    final newStatus = !user.isActive;
    final action = newStatus ? 'Reativar' : 'Desativar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action ${user.fullName}?'),
        content: Text(newStatus
            ? 'O colaborador voltará a ter acesso ao AlinhaJá.'
            : 'O acesso ao AlinhaJá será bloqueado imediatamente para este colaborador.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action,
                style: TextStyle(
                    color: newStatus
                        ? AppConstants.success
                        : AppConstants.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await supabase.rpc('admin_toggle_user_status', params: {
        'p_target_user_id': user.id,
        'p_is_active': newStatus,
      });
      ref.invalidate(adminUsersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus
                ? '✅ ${user.fullName} reativado!'
                : '🚫 ${user.fullName} desativado!'),
            backgroundColor:
                newStatus ? AppConstants.success : AppConstants.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: $e'), backgroundColor: AppConstants.danger));
      }
    }
  }

  Future<void> _promoteToAdmin(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promover a TI Admin?'),
        content: Text(
            'Deseja promover ${user.fullName} ao nível TI Admin?\n\nEle terá acesso total ao Dashboard Administrativo, gestão de usuários e governança de canais.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Promover', style: TextStyle(color: Colors.purple)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await supabase.rpc('admin_update_user_role', params: {
        'p_target_user_id': user.id,
        'p_new_role': 'admin',
      });
      ref.invalidate(adminUsersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('👑 ${user.fullName} promovido a TI Admin!'),
            backgroundColor: Colors.purple,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: $e'), backgroundColor: AppConstants.danger));
      }
    }
  }

  Future<void> _demoteFromAdmin(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rebaixar para Staff?'),
        content: Text(
            '${user.fullName} perderá imediatamente o acesso ao Dashboard Administrativo e todas as suas capacidades de governança.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Rebaixar', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await supabase.rpc('admin_update_user_role', params: {
        'p_target_user_id': user.id,
        'p_new_role': 'member',
      });
      ref.invalidate(adminUsersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.fullName} rebaixado para Staff.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: $e'), backgroundColor: AppConstants.danger));
      }
    }
  }

  void _showGovernanceSheet(UserModel user) {
    final isMe = user.id == supabase.auth.currentUser?.id;
    final isAdmin = AppPermissions.canAccessAdmin(user.roleLevel);
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header do Colaborador
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: user.avatarUrl != null
                          ? CachedNetworkImageProvider(user.avatarUrl!, maxWidth: 320)
                          : null,
                      child: user.avatarUrl == null
                          ? Text(user.initials,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 20))
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.fullName,
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          Text(
                              (user.jobPositionName ?? 'Sem função definida')
                                  .toUpperCase(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5)),
                          if (user.branchName != null)
                            Text(user.branchName!,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.primary)),
                        ],
                      ),
                    ),
                    _buildRoleBadge(context, user.roleLevel),
                  ],
                ),

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),

                // Dados Pessoais do Colaborador (Visível somente pela TI)
                if (user.cpf != null ||
                    user.dataNascimento != null ||
                    user.sexo != null) ...[
                  Text('Dados Pessoais',
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.outline)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (user.cpf != null && user.cpf!.isNotEmpty)
                        Chip(
                          avatar: const Icon(Icons.credit_card, size: 16),
                          label: Text('CPF: ${user.cpfMasked}'),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (user.dataNascimento != null)
                        Chip(
                          avatar: const Icon(Icons.cake, size: 16),
                          label: Text(
                              '${user.dataNascimentoFormatted} (${user.age} anos)'),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (user.sexo != null)
                        Chip(
                          avatar: const Icon(Icons.wc, size: 16),
                          label: Text(user.sexoLabel),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                ],

                // Ações de Governança
                Text('Ações de Governança',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),

                // Toggle: Ativar / Desativar Conta
                ListTile(
                  leading: Icon(
                    user.isActive ? Icons.toggle_on : Icons.toggle_off,
                    size: 36,
                    color: user.isActive
                        ? AppConstants.success
                        : AppConstants.danger,
                  ),
                  title:
                      Text(user.isActive ? 'Conta Ativa' : 'Conta Desativada'),
                  subtitle: Text(user.isActive
                      ? 'Toque para desativar o acesso'
                      : 'Toque para reativar o acesso'),
                  enabled: !isMe,
                  onTap: isMe
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _toggleActive(user);
                        },
                ),

                // Toggle: Promover / Rebaixar Admin
                ListTile(
                  leading: Icon(
                    isAdmin
                        ? Icons.admin_panel_settings
                        : Icons.shield_outlined,
                    size: 36,
                    color: isAdmin ? Colors.purple : Colors.grey,
                  ),
                  title: Text(isAdmin ? 'TI Admin' : 'Promover a Admin'),
                  subtitle: Text(isAdmin
                      ? 'Toque para rebaixar a Staff'
                      : 'Toque para conceder acesso total'),
                  enabled: !isMe,
                  onTap: isMe
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          if (isAdmin) {
                            _demoteFromAdmin(user);
                          } else {
                            _promoteToAdmin(user);
                          }
                        },
                ),

                const SizedBox(height: 8),

                // Editar Perfil
                ListTile(
                  leading: const Icon(Icons.edit_outlined, size: 30),
                  title: const Text('Editar Perfil Funcional'),
                  subtitle: const Text('Alterar nome, cargo, filial e nível'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await context.push('/admin/edit', extra: user);
                    ref.invalidate(adminUsersProvider);
                  },
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final usersState = ref.watch(adminUsersProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        // ── Filtro Pendentes / Todos ──────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: usersState.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (users) {
              final pendingCount = users.where((u) => !u.isActive).length;
              return SegmentedButton<_UserFilter>(
                segments: [
                  ButtonSegment(
                    value: _UserFilter.all,
                    label: Text('Todos (${users.length})'),
                    icon: const Icon(Icons.people_alt_outlined),
                  ),
                  ButtonSegment(
                    value: _UserFilter.pending,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Pendentes'),
                        if (pendingCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppConstants.danger,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$pendingCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    icon: const Icon(Icons.pending_actions_rounded),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (val) =>
                    setState(() => _filter = val.first),
              );
            },
          ),
        ),

        // ── Barra de busca ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Buscar por nome...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (val) =>
                setState(() => _searchQuery = val.toLowerCase()),
          ),
        ),

        // ── Lista de Usuários ────────────────────────────────
        Expanded(
          child: usersState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) =>
                Center(child: Text('Erro ao carregar colaboradores:\n$e')),
            data: (users) {
              var filtered = users.where((u) {
                final matchesSearch =
                    u.fullName.toLowerCase().contains(_searchQuery);
                final matchesFilter = _filter == _UserFilter.all || !u.isActive;
                return matchesSearch && matchesFilter;
              }).toList();

              // Pendentes primeiro quando no filtro "todos"
              if (_filter == _UserFilter.all) {
                filtered.sort((a, b) {
                  if (a.isActive == b.isActive) {
                    return a.fullName.compareTo(b.fullName);
                  }
                  return a.isActive ? 1 : -1; // Inativos primeiro
                });
              }

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _filter == _UserFilter.pending
                            ? Icons.check_circle_outline
                            : Icons.people_outline,
                        size: 48,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _filter == _UserFilter.pending
                            ? 'Nenhum cadastro pendente!'
                            : 'Nenhum colaborador encontrado.',
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async => ref.refresh(adminUsersProvider.future),
                child: ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final user = filtered[index];
                    final isMe = user.id == supabase.auth.currentUser?.id;
                    final isPending = !user.isActive;

                    return _ExpandableUserCard(
                      user: user,
                      isMe: isMe,
                      isPending: isPending,
                      theme: theme,
                      onApprove: () => _approveUser(user),
                      onReject: () => _rejectUser(user),
                      onGovernance: () => _showGovernanceSheet(user),
                      buildRoleBadge: _buildRoleBadge,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRoleBadge(BuildContext context, String role) {
    Color color;
    String label;

    switch (role) {
      case 'super_admin':
        color = Colors.purple;
        label = 'Super Admin';
        break;
      case 'admin':
        color = Colors.orange;
        label = 'Administrador';
        break;
      case 'manager':
        color = Colors.teal;
        label = 'Gestor';
        break;
      default:
        color = Colors.grey;
        label = 'Colaborador';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

// ─── Card Expansível do Usuário ─────────────────────────────────

class _ExpandableUserCard extends StatefulWidget {
  final UserModel user;
  final bool isMe;
  final bool isPending;
  final ThemeData theme;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onGovernance;
  final Widget Function(BuildContext, String) buildRoleBadge;

  const _ExpandableUserCard({
    required this.user,
    required this.isMe,
    required this.isPending,
    required this.theme,
    required this.onApprove,
    required this.onReject,
    required this.onGovernance,
    required this.buildRoleBadge,
  });

  @override
  State<_ExpandableUserCard> createState() => _ExpandableUserCardState();
}

class _ExpandableUserCardState extends State<_ExpandableUserCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final theme = widget.theme;
    final isPending = widget.isPending;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isPending
            ? BorderSide(
                color: AppConstants.danger.withValues(alpha: 0.4), width: 1.5)
            : BorderSide.none,
      ),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Column(
        children: [
          // ── Header (sempre visível) ──
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            onLongPress: isPending ? null : widget.onGovernance,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Avatar
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: isPending
                            ? AppConstants.danger.withValues(alpha: 0.2)
                            : theme.colorScheme.primaryContainer,
                        backgroundImage: user.avatarUrl != null
                            ? CachedNetworkImageProvider(user.avatarUrl!, maxWidth: 320)
                            : null,
                        child: user.avatarUrl == null
                            ? Text(
                                user.fullName.isNotEmpty
                                    ? user.fullName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: isPending
                                      ? AppConstants.danger
                                      : theme.colorScheme.onPrimaryContainer,
                                ),
                              )
                            : null,
                      ),
                      if (isPending)
                        Positioned(
                          right: -1,
                          top: -1,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: AppConstants.danger,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: theme.colorScheme.surface, width: 2),
                            ),
                            child: const Icon(Icons.schedule,
                                size: 8, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),

                  // Nome + Cargo resumido
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.fullName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: theme.colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.isMe) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'VOCÊ',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        theme.colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          (user.jobPositionName ?? 'Sem função definida')
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Status + Role chips
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (isPending)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppConstants.danger.withValues(alpha: 0.12),
                            border: Border.all(
                                color:
                                    AppConstants.danger.withValues(alpha: 0.5)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'PENDENTE',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppConstants.danger),
                          ),
                        )
                      else
                        widget.buildRoleBadge(context, user.roleLevel),
                      const SizedBox(height: 6),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 20,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Corpo Expansível (Dados do Perfil) ──
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedContent(theme, user, isPending),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(
      ThemeData theme, UserModel user, bool isPending) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Divider(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 8),

          // Grid de informações do perfil
          _ProfileRow(
              icon: Icons.business_rounded,
              label: 'Filial',
              value: user.branchName ?? user.branchId ?? 'Não informada',
              theme: theme),
          _ProfileRow(
              icon: Icons.domain_rounded,
              label: 'Departamento',
              value:
                  user.departmentName ?? user.departmentId ?? 'Não informado',
              theme: theme),
          _ProfileRow(
              icon: Icons.work_outline_rounded,
              label: 'Cargo',
              value: (user.jobPositionName ??
                      user.jobPositionId ??
                      'Não informado')
                  .toUpperCase(),
              theme: theme),
          if (user.cpf != null && user.cpf!.isNotEmpty)
            _ProfileRow(
                icon: Icons.credit_card_rounded,
                label: 'CPF',
                value: user.cpfMasked,
                theme: theme),
          if (user.phone != null && user.phone!.isNotEmpty)
            _ProfileRow(
                icon: Icons.phone_outlined,
                label: 'Telefone',
                value: user.phone!,
                theme: theme),
          if (user.dataNascimento != null)
            _ProfileRow(
                icon: Icons.cake_rounded,
                label: 'Nascimento',
                value: '${user.dataNascimentoFormatted} (${user.age} anos)',
                theme: theme),
          if (user.sexo != null)
            _ProfileRow(
                icon: Icons.wc_rounded,
                label: 'Sexo',
                value: user.sexoLabel,
                theme: theme),

          const SizedBox(height: 12),

          // Botões de ação
          if (isPending)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onReject,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Rejeitar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.danger,
                      side: const BorderSide(color: AppConstants.danger),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.onApprove,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Aprovar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.success,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onGovernance,
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                label: const Text('Ações de Governança'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Linha de dado do perfil ────────────────────────────

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: theme.colorScheme.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 10),
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
