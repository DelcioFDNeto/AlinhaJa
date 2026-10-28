import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/admin/admin_tab_registry.dart';
import 'package:alinha_ja/core/rbac/models/rbac_permission.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final ScrollController _tabScrollCtrl = ScrollController();
  bool _redirecting = false;

  @override
  void dispose() {
    _tabScrollCtrl.dispose();
    super.dispose();
  }

  /// Regra de ENTRADA no painel: `super_admin`/`admin` (por role_level) têm
  /// bypass; os demais precisam da permissão RBAC `admin_panel:view`. A partir
  /// daí, cada aba é filtrada individualmente por [_canSeeTab].
  bool _canEnter(String? roleLevel, List<RbacPermission> perms) {
    if (roleLevel == AppPermissions.superAdmin ||
        roleLevel == AppPermissions.admin) {
      return true;
    }
    return perms.hasPermission('admin_panel', 'view');
  }

  void _denyAndRedirect() {
    if (_redirecting) return;
    _redirecting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acesso Negado: Área restrita.'),
          backgroundColor: AppConstants.danger,
        ),
      );
      context.go('/chats');
    });
  }

  /// Decide se a aba [tab] deve aparecer para o usuário logado.
  ///
  /// `super_admin` e `admin` (por role_level) enxergam todas as abas — o mesmo
  /// bypass aplicado na ENTRADA (`_canEnter`) vale por aba, para não travar
  /// admins legados que ainda não possuem grants RBAC atribuídos. Os demais
  /// perfis são estritamente gated pela permissão `view` do módulo da aba.
  bool _canSeeTab(
    AdminTabDescriptor tab,
    String? roleLevel,
    List<RbacPermission> perms,
  ) {
    if (roleLevel == AppPermissions.superAdmin ||
        roleLevel == AppPermissions.admin) {
      return true;
    }
    return perms.hasPermission(tab.module, tab.action);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final permsAsync = ref.watch(myPermissionsProvider);

    return permsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Dashboard Administrativo')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Não foi possível carregar as permissões.\n$e',
                textAlign: TextAlign.center),
          ),
        ),
      ),
      data: (perms) {
        // Gate de entrada (defesa em profundidade; a rota /admin já é guardada
        // por moduleGuard('admin_panel')).
        if (!_canEnter(user?.roleLevel, perms)) {
          _denyAndRedirect();
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final visibleTabs = kAdminTabRegistry
            .where((t) => _canSeeTab(t, user?.roleLevel, perms))
            .toList(growable: false);

        if (visibleTabs.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Dashboard Administrativo')),
            body: const _NoAccessBody(),
          );
        }

        return _buildDashboard(context, visibleTabs);
      },
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    List<AdminTabDescriptor> tabs,
  ) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double tabHeight = screenWidth < 900 ? 52.0 : 72.0;

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard Administrativo'),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(tabHeight),
            child: Theme(
              data: Theme.of(context).copyWith(
                scrollbarTheme: ScrollbarThemeData(
                  thumbColor: WidgetStateProperty.all(
                      Colors.grey.withValues(alpha: 0.5)),
                  thickness: WidgetStateProperty.all(4),
                  radius: const Radius.circular(8),
                ),
              ),
              child: Listener(
                onPointerSignal: (pointerSignal) {
                  if (pointerSignal is PointerScrollEvent) {
                    final double scrollDelta = pointerSignal.scrollDelta.dy != 0
                        ? pointerSignal.scrollDelta.dy
                        : pointerSignal.scrollDelta.dx;
                    if (scrollDelta != 0) {
                      final newOffset = _tabScrollCtrl.offset + scrollDelta;
                      _tabScrollCtrl.jumpTo(
                        newOffset.clamp(
                            0.0, _tabScrollCtrl.position.maxScrollExtent),
                      );
                    }
                  }
                },
                child: Scrollbar(
                  controller: _tabScrollCtrl,
                  thumbVisibility: true,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: SingleChildScrollView(
                      controller: _tabScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: TabBar(
                        isScrollable: true,
                        physics: const NeverScrollableScrollPhysics(),
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          for (final t in tabs)
                            _buildTab(context, t.icon, t.title, screenWidth),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: ResponsiveWidthContainer(
          child: TabBarView(
            children: [
              for (final t in tabs) t.builder(),
            ],
          ),
        ),
      ),
    );
  }

  Tab _buildTab(
      BuildContext context, IconData icon, String text, double screenWidth) {
    if (screenWidth < 600) {
      // Mobile: Apenas ícone com tooltip
      return Tab(
        icon: Tooltip(
          message: text,
          child: Icon(icon, size: 22),
        ),
      );
    } else if (screenWidth < 950) {
      // Tablet: Ícone e texto lado a lado (mais compacto)
      return Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      );
    } else {
      // Desktop: Ícone acima do texto (padrão)
      return Tab(
        icon: Icon(icon, size: 24),
        text: text,
      );
    }
  }
}

/// Corpo exibido quando o usuário acessa o painel mas não tem permissão para
/// nenhuma aba (ex.: `admin` sem permissões RBAC atribuídas).
class _NoAccessBody extends StatelessWidget {
  const _NoAccessBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Nenhuma área disponível',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Você ainda não tem permissão para nenhuma seção do painel '
              'administrativo. Solicite acesso ao administrador da organização.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
