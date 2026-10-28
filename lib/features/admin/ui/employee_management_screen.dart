import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/admin/ui/org_structure_management_sheet.dart';

/// Provider que carrega TODOS os usuários (ativos + inativos).
final _allUsersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await supabase
      .from('users')
      .select(
          'id, full_name, avatar_url, department_id, job_position_id, branch_id, role_level, is_active, departments(name), job_positions(name)')
      .order('full_name');
  return List<Map<String, dynamic>>.from(res);
});

/// Painel administrativo para gestão de funcionários.
/// Apenas visível para TI Admin.
class EmployeeManagementScreen extends ConsumerWidget {
  const EmployeeManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;
    final theme = Theme.of(context);

    if (currentUser == null ||
        !AppPermissions.canAccessAdmin(currentUser.roleLevel)) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Gestão de Equipe',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
          ),
          centerTitle: false,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Acesso Negado',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Área restrita à administração de TI.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final usersAsync = ref.watch(_allUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Gestão de Equipe',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar lista',
            onPressed: () => ref.invalidate(_allUsersProvider),
          ),
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Gerenciar Departamentos e Cargos',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (context) => const OrgStructureManagementSheet(),
              );
            },
          ),
        ],
      ),
      body: ResponsiveWidthContainer(
        child: usersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  'Erro ao carregar equipe:\n$e',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: theme.colorScheme.error, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => ref.invalidate(_allUsersProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
          data: (users) {
            if (users.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline,
                        size: 64, color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum colaborador encontrado.',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              );
            }

            final activeUsers =
                users.where((u) => u['is_active'] == true).toList();
            final archivedUsers =
                users.where((u) => u['is_active'] != true).toList();

            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // Contador
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      _CountChip(
                        label: 'Ativos',
                        count: activeUsers.length,
                        color: AppConstants.success,
                        theme: theme,
                      ),
                      const SizedBox(width: 12),
                      _CountChip(
                        label: 'Arquivados',
                        count: archivedUsers.length,
                        color: theme.colorScheme.outline,
                        theme: theme,
                      ),
                    ],
                  ),
                ),

                // Ativos
                if (activeUsers.isNotEmpty) ...[
                  _SectionTitle(title: 'Colaboradores Ativos', theme: theme),
                  ...activeUsers.map((u) => _EmployeeCard(
                        user: u,
                        theme: theme,
                        onAction: () => ref.invalidate(_allUsersProvider),
                      )),
                ],

                // Arquivados
                if (archivedUsers.isNotEmpty) ...[
                  _SectionTitle(title: 'Arquivados / Desligados', theme: theme),
                  ...archivedUsers.map((u) => _EmployeeCard(
                        user: u,
                        theme: theme,
                        onAction: () => ref.invalidate(_allUsersProvider),
                      )),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Card do Funcionário ─────────────────────────────────────────

class _EmployeeCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final ThemeData theme;
  final VoidCallback onAction;

  const _EmployeeCard({
    required this.user,
    required this.theme,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final name = user['full_name'] as String? ?? 'Sem nome';
    final avatarUrl = user['avatar_url'] as String?;
    final job = (user['job_positions'] as Map?)?['name'] as String? ?? '';
    final department = (user['departments'] as Map?)?['name'] as String? ?? '';
    final branch = user['branch_id'] as String? ?? '';
    final role = user['role_level'] as String? ?? 'member';
    final isActive = user['is_active'] as bool? ?? false;
    final userId = user['id'] as String;

    final subtitle =
        [job, department, branch].where((s) => s.isNotEmpty).join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh
          .withValues(alpha: isActive ? 1.0 : 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage:
              avatarUrl != null ? CachedNetworkImageProvider(avatarUrl, maxWidth: 320) : null,
          child: avatarUrl == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                )
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outline,
                  decoration: isActive ? null : TextDecoration.lineThrough,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Status chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isActive
                    ? AppConstants.success.withValues(alpha: 0.15)
                    : theme.colorScheme.outline.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive ? 'Ativo' : 'Arquivado',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isActive
                      ? AppConstants.success
                      : theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
        subtitle: subtitle.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            : null,
        trailing: _ActionMenu(
          userId: userId,
          userName: name,
          isActive: isActive,
          roleLevel: role,
          theme: theme,
          onAction: onAction,
        ),
      ),
    );
  }
}

// ─── Menu de Ações (PopupMenuButton) ─────────────────────────────

class _ActionMenu extends StatelessWidget {
  final String userId;
  final String userName;
  final bool isActive;
  final String roleLevel;
  final ThemeData theme;
  final VoidCallback onAction;

  const _ActionMenu({
    required this.userId,
    required this.userName,
    required this.isActive,
    required this.roleLevel,
    required this.theme,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurfaceVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (action) => _handleAction(context, action),
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'view_profile',
          child: ListTile(
            leading: Icon(Icons.person_search_rounded, color: Colors.blue),
            title: Text('Ver Perfil Completo',
                style: TextStyle(fontWeight: FontWeight.w600)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        if (isActive)
          const PopupMenuItem(
            value: 'archive',
            child: ListTile(
              leading: Icon(Icons.archive_outlined, color: Colors.orange),
              title: Text('📦 Arquivar (Desligamento)'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          )
        else
          const PopupMenuItem(
            value: 'reactivate',
            child: ListTile(
              leading: Icon(Icons.replay_rounded, color: Colors.green),
              title: Text('🔄 Reativar'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_forever_rounded,
                color: theme.colorScheme.error),
            title: Text(
              '🗑️ Excluir Definitivamente',
              style: TextStyle(
                  color: theme.colorScheme.error, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Apenas contas de teste',
                style: TextStyle(fontSize: 11)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    switch (action) {
      case 'view_profile':
        _showProfileDetails(context);
        break;
      case 'archive':
        await _executeRpc(
          context,
          rpcName: 'archive_user',
          successMsg: '$userName foi arquivado(a) com sucesso.',
        );
        break;
      case 'reactivate':
        await _executeRpc(
          context,
          rpcName: 'reactivate_user',
          successMsg: '$userName foi reativado(a) com sucesso!',
        );
        break;
      case 'delete':
        await _confirmAndDelete(context);
        break;
    }
  }

  void _showProfileDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProfileDetailsSheet(
        userId: userId,
        theme: theme,
      ),
    );
  }

  Future<void> _executeRpc(
    BuildContext context, {
    required String rpcName,
    required String successMsg,
  }) async {
    try {
      await supabase.rpc(rpcName, params: {'p_user_id': userId});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMsg),
            backgroundColor: AppConstants.success,
          ),
        );
      }
      onAction();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: AppConstants.danger,
          ),
        );
      }
    }
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            size: 48, color: Theme.of(ctx).colorScheme.error),
        title: const Text('⚠️ Exclusão Definitiva'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Você está prestes a EXCLUIR PERMANENTEMENTE a conta de:',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx)
                    .colorScheme
                    .errorContainer
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color:
                        Theme.of(ctx).colorScheme.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                userName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Theme.of(ctx).colorScheme.error,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esta ação é IRREVERSÍVEL. Todos os dados do usuário serão removidos fisicamente do banco. Use apenas para contas de teste com erros.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Excluir Permanentemente'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await _executeRpc(
        context,
        rpcName: 'delete_user_account',
        successMsg: 'Conta de $userName excluída permanentemente.',
      );
    }
  }
}

// ─── Bottom Sheet de Detalhes do Perfil ─────────────────────────

class _ProfileDetailsSheet extends ConsumerWidget {
  final String userId;
  final ThemeData theme;

  const _ProfileDetailsSheet({required this.userId, required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Busca o usuário da cache ou busca diretamente se necessário
    final usersAsync = ref.watch(_allUsersProvider);
    final users = usersAsync.valueOrNull;
    final user = users?.firstWhere((u) => u['id'] == userId, orElse: () => {});

    if (user == null || user.isEmpty) {
      return Container(
        color: theme.colorScheme.surface,
        height: 200,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final name = user['full_name'] as String? ?? 'Sem nome';
    final avatarUrl = user['avatar_url'] as String?;
    final job =
        (user['job_positions'] as Map?)?['name'] as String? ?? 'Não definido';
    final department =
        (user['departments'] as Map?)?['name'] as String? ?? 'Não definido';
    final branch = user['branch_id'] as String? ?? 'Não definido';
    final role = user['role_level'] as String? ?? 'member';
    final isActive = user['is_active'] as bool? ?? false;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 12),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            CircleAvatar(
              radius: 50,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage: avatarUrl != null
                  ? CachedNetworkImageProvider(avatarUrl, maxWidth: 320)
                  : null,
              child: avatarUrl == null
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? AppConstants.success.withValues(alpha: 0.15)
                    : theme.colorScheme.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isActive ? 'Status: ATIVO' : 'Status: ARQUIVADO',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color:
                      isActive ? AppConstants.success : theme.colorScheme.error,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _InfoRow(
                      icon: Icons.work_outline,
                      label: 'Cargo',
                      value: job,
                      theme: theme),
                  const Divider(),
                  _InfoRow(
                      icon: Icons.corporate_fare,
                      label: 'Departamento',
                      value: department,
                      theme: theme),
                  const Divider(),
                  _InfoRow(
                      icon: Icons.store_mall_directory_outlined,
                      label: 'Filial (ID)',
                      value: branch,
                      theme: theme),
                  const Divider(),
                  _InfoRow(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'Nível de Permissão',
                      value: role,
                      theme: theme),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 24, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style:
                    TextStyle(fontSize: 12, color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ],
          )
        ],
      ),
    );
  }
}

// ─── Widgets auxiliares ────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final ThemeData theme;
  const _SectionTitle({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final ThemeData theme;
  const _CountChip(
      {required this.label,
      required this.count,
      required this.color,
      required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
