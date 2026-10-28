import 'package:flutter/material.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/features/profile/providers/users_provider.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/core/providers/presence_service.dart';
import 'package:timeago/timeago.dart' as timeago;

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _searchCtrl = TextEditingController();
  final _groupNameCtrl = TextEditingController();
  final Set<String> _selectedIds = {};

  bool _isLoading = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _groupNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _createChatOrGroup(List<UserModel> allUsers) async {
    if (_selectedIds.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      if (_selectedIds.length == 1) {
        // ─── Criação de DM (1-a-1) ───
        final targetUserId = _selectedIds.first;
        final targetUser = allUsers.firstWhere((u) => u.id == targetUserId);

        final response = await supabase.rpc(
          'create_direct_chat',
          params: {'other_user_id': targetUserId},
        );

        final chatId = response as String;

        if (mounted) {
          context.pushReplacement(
            '/chat/$chatId',
            extra: {'name': targetUser.fullName, 'isGroup': false},
          );
        }
      } else {
        // ─── Criação de Grupo ───
        final name = _groupNameCtrl.text.trim();
        // O nome não é obrigatório no RPC (fallback interno ou UI resolve), mas validamos se o usuário forneceu.

        final chatId = await supabase.rpc('create_group_chat', params: {
          'p_name': name.isEmpty ? null : name,
          'p_description': null,
          'p_member_ids': _selectedIds.toList(),
        });

        if (mounted) {
          final title = name.isEmpty ? 'Grupo sem nome' : name;
          context.pushReplacement(
            '/chat/$chatId',
            extra: {'name': title, 'isGroup': true},
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao iniciar conversa: $e'),
            backgroundColor: AppConstants.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedIds.contains(userId)) {
        _selectedIds.remove(userId);
      } else {
        // Se estiver tentando adicionar um segundo usuário e não tiver permissão
        if (_selectedIds.isNotEmpty) {
          final currentUser = ref.read(currentUserProvider).valueOrNull;
          if (!AppPermissions.canCreateGroupChat(currentUser?.roleLevel)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Você não tem permissão para criar grupos de chat.'),
                backgroundColor: AppConstants.danger,
              ),
            );
            return;
          }
        }
        _selectedIds.add(userId);
      }
    });
  }

  int _getRoleWeight(String role) {
    switch (role) {
      case 'super_admin':
        return 100;
      case 'admin':
        return 90;
      case 'manager':
        return 80;
      case 'member':
      default:
        return 10;
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);
    final theme = Theme.of(context);
    final isGroupMode = _selectedIds.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Novo Bate-Papo',
                style: TextStyle(fontWeight: FontWeight.w600)),
            Text(
              isGroupMode
                  ? '${_selectedIds.length} selecionados'
                  : 'Selecione um contato',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: ResponsiveWidthContainer(
        child: usersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Erro: $error')),
          data: (allUsers) {
            if (allUsers.isEmpty) {
              return const Center(child: Text('Nenhum contato encontrado.'));
            }

            // Filtro de pesquisa
            final query = _searchCtrl.text.trim().toLowerCase();
            final filteredUsers = allUsers.where((u) {
              return u.fullName.toLowerCase().contains(query);
            }).toList();

            return Column(
              children: [
                // ─── Área de Selecionados (Chips) ────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _selectedIds.isNotEmpty
                      ? Container(
                          height: 100,
                          color: theme.colorScheme.surface,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            children: _selectedIds.map((id) {
                              final user = allUsers.firstWhere(
                                (u) => u.id == id,
                                orElse: () =>
                                    UserModel(id: id, fullName: '...'),
                              );
                              return GestureDetector(
                                onTap: () => _toggleSelection(id),
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Stack(
                                        children: [
                                          CircleAvatar(
                                            radius: 26,
                                            backgroundColor: theme
                                                .colorScheme.primaryContainer,
                                            backgroundImage: user.avatarUrl !=
                                                    null
                                                ? CachedNetworkImageProvider(
                                                    user.avatarUrl!, maxWidth: 320)
                                                : null,
                                            child: user.avatarUrl == null
                                                ? Text(user.fullName[0]
                                                    .toUpperCase())
                                                : null,
                                          ),
                                          Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: CircleAvatar(
                                              radius: 10,
                                              backgroundColor:
                                                  theme.colorScheme.surface,
                                              child: const Icon(
                                                  Icons.remove_circle,
                                                  size: 20,
                                                  color: AppConstants.danger),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          user.fullName.split(' ').first,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600),
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (_selectedIds.isNotEmpty) const Divider(height: 1),

                // ─── Busca e Nome do Grupo ──────────────────
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Buscar colaborador...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),

                      // Expande o campo de Nome do Grupo se tiver > 1 pessoa selecionada
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: isGroupMode
                            ? Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: TextField(
                                  controller: _groupNameCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Nome do Grupo (Opcional)',
                                    hintText: 'Ex: Equipe de Vendas',
                                    prefixIcon:
                                        const Icon(Icons.group_add_rounded),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: theme.colorScheme.primary
                                        .withValues(alpha: 0.05),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),

                // ─── Lista de Contatos Agrupada ────────────
                Expanded(
                  child: Builder(
                    builder: (context) {
                      // Reagrupamento por Filial -> Departamento
                      final Map<String, Map<String, List<UserModel>>>
                          groupedData = {};
                      for (final u in filteredUsers) {
                        final branchName = u.branchName ?? 'Matriz / Sede';
                        final deptName = u.departmentName ?? 'Geral / Outros';

                        groupedData
                            .putIfAbsent(branchName, () => {})
                            .putIfAbsent(deptName, () => [])
                            .add(u);
                      }

                      final sortedBranches = groupedData.keys.toList()..sort();

                      if (sortedBranches.isEmpty) {
                        return const Center(
                            child: Text('Nenhum colaborador encontrado.'));
                      }

                      return ListView.builder(
                        itemCount: sortedBranches.length,
                        itemBuilder: (context, branchIndex) {
                          final branchName = sortedBranches[branchIndex];
                          final deptsMap = groupedData[branchName]!;
                          final sortedDepts = deptsMap.keys.toList()..sort();

                          // Conta o total de usuários na filial
                          final totalBranchUsers = deptsMap.values
                              .fold<int>(0, (sum, list) => sum + list.length);

                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.15),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ExpansionTile(
                                shape: const RoundedRectangleBorder(
                                    side: BorderSide.none),
                                collapsedShape: const RoundedRectangleBorder(
                                    side: BorderSide.none),
                                title: Row(
                                  children: [
                                    Icon(
                                      Icons.business_rounded,
                                      color: theme.colorScheme.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        branchName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$totalBranchUsers',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                collapsedTextColor: theme.colorScheme.onSurface,
                                backgroundColor: Colors.transparent,
                                collapsedBackgroundColor: Colors.transparent,
                                childrenPadding:
                                    const EdgeInsets.only(bottom: 8),
                                iconColor: theme.colorScheme.primary,
                                collapsedIconColor:
                                    theme.colorScheme.onSurfaceVariant,
                                initiallyExpanded:
                                    branchIndex == 0 || query.isNotEmpty,
                                children: [
                                  const Divider(height: 1),
                                  ...sortedDepts.map((deptName) {
                                    final deptUsers = deptsMap[deptName]!;

                                    // Ordena os usuários do departamento por peso de papel
                                    deptUsers.sort((a, b) =>
                                        _getRoleWeight(b.roleLevel).compareTo(
                                            _getRoleWeight(a.roleLevel)));

                                    return Container(
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: theme
                                              .colorScheme.outlineVariant
                                              .withValues(alpha: 0.1),
                                          width: 1,
                                        ),
                                      ),
                                      child: ExpansionTile(
                                        shape: const RoundedRectangleBorder(
                                            side: BorderSide.none),
                                        collapsedShape:
                                            const RoundedRectangleBorder(
                                                side: BorderSide.none),
                                        dense: true,
                                        leading: Icon(
                                          Icons.folder_shared_rounded,
                                          color: theme.colorScheme.secondary,
                                          size: 18,
                                        ),
                                        title: Text(
                                          deptName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        trailing: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.secondary
                                                .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '${deptUsers.length}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  theme.colorScheme.secondary,
                                            ),
                                          ),
                                        ),
                                        initiallyExpanded: query.isNotEmpty,
                                        children: [
                                          const Divider(height: 1),
                                          ListView.separated(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            padding: EdgeInsets.zero,
                                            itemCount: deptUsers.length,
                                            separatorBuilder: (_, __) =>
                                                const Divider(
                                                    height: 1, indent: 70),
                                            itemBuilder: (context, userIndex) {
                                              final user = deptUsers[userIndex];
                                              final isSelected = _selectedIds
                                                  .contains(user.id);
                                              return _UserCheckboxTile(
                                                user: user,
                                                isSelected: isSelected,
                                                onChanged: (val) {
                                                  if (!user.isActive) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                          content: Text(
                                                              'Usuário arquivado no sistema.')),
                                                    );
                                                    return;
                                                  }
                                                  _toggleSelection(user.id);
                                                },
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _selectedIds.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _isLoading
                  ? null
                  : () {
                      final users = usersAsync.valueOrNull ?? [];
                      _createChatOrGroup(users);
                    },
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(
                      isGroupMode
                          ? Icons.group_add_rounded
                          : Icons.send_rounded,
                      color: Colors.white),
              label: Text(
                _isLoading
                    ? 'Aguarde...'
                    : isGroupMode
                        ? 'Criar Grupo'
                        : 'Iniciar Chat',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: theme.colorScheme.primary,
            )
          : null,
    );
  }
}

class _UserCheckboxTile extends ConsumerWidget {
  final UserModel user;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const _UserCheckboxTile({
    required this.user,
    required this.isSelected,
    required this.onChanged,
  });

  Widget _buildRoleBadge(String role, ThemeData theme) {
    Color color;
    Color textColor;
    String label = AppPermissions.getLabel(role);

    switch (role) {
      case 'super_admin':
        color = Colors.amber.shade900.withValues(alpha: 0.12);
        textColor = Colors.amber.shade900;
        label = 'TI - Super Admin';
        break;
      case 'admin':
        color = Colors.blue.shade800.withValues(alpha: 0.12);
        textColor = Colors.blue.shade900;
        label = 'Diretoria';
        break;
      case 'manager':
        color = Colors.purple.shade700.withValues(alpha: 0.12);
        textColor = Colors.purple.shade900;
        label = 'Gestor';
        break;
      case 'member':
      default:
        color = Colors.grey.shade600.withValues(alpha: 0.08);
        textColor = Colors.grey.shade700;
        label = 'Colaborador';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border:
            Border.all(color: textColor.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isOnline = user.isActuallyOnline ||
        ref.watch(onlineUsersProvider.select((set) => set.contains(user.id)));

    return InkWell(
      onTap: () => onChanged(!isSelected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.04)
            : Colors.transparent,
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isOnline
                          ? AppConstants.success.withValues(alpha: 0.5)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: user.avatarUrl != null
                        ? CachedNetworkImageProvider(user.avatarUrl!, maxWidth: 320)
                        : null,
                    child: user.avatarUrl == null
                        ? Text(
                            user.initials,
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                ),
                if (isOnline)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: AppConstants.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),

            // Informações
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
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            decoration: user.isActive
                                ? null
                                : TextDecoration.lineThrough,
                            color: user.isActive
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildRoleBadge(user.roleLevel, theme),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (user.jobPositionName != null &&
                          user.jobPositionName!.isNotEmpty) ...[
                        Text(
                          user.jobPositionName!,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (user.departmentName != null &&
                            user.departmentName!.isNotEmpty) ...[
                          Text(
                            ' • ',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ],
                      ],
                      if (user.departmentName != null &&
                          user.departmentName!.isNotEmpty)
                        Text(
                          user.departmentName!,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                  if (!isOnline && user.lastSeenAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Visto por último: ${timeago.format(user.lastSeenAt!, locale: 'pt_BR_short')}',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Ícone indicador online/offline no canto direito
            Tooltip(
              message: isOnline ? 'Online' : 'Offline',
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline
                      ? AppConstants.success
                      : theme.colorScheme.outline.withValues(alpha: 0.3),
                  boxShadow: isOnline
                      ? [
                          BoxShadow(
                            color: AppConstants.success.withValues(alpha: 0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
              ),
            ),

            // Checkbox Customizado
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    isSelected ? theme.colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
