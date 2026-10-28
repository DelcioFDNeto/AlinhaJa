import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';

import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/platform/ui/platform_org_switcher.dart';
import 'package:alinha_ja/core/providers/desktop_selection_provider.dart';
import 'package:alinha_ja/core/modules/module_descriptor.dart';
import 'package:alinha_ja/core/modules/module_access_provider.dart';
import 'package:alinha_ja/features/onboarding/onboarding_keys.dart';
import 'package:alinha_ja/core/brand/logo_empresa.dart';

/// Uma Sidebar CRM moderna e expansível.
class CrmSidebar extends ConsumerStatefulWidget {
  final int unreadChannels;
  final int unreadConversations;
  final int currentTabIndex;
  final Function(int) onTabSelected;

  const CrmSidebar({
    super.key,
    required this.unreadChannels,
    required this.unreadConversations,
    required this.currentTabIndex,
    required this.onTabSelected,
  });

  @override
  ConsumerState<CrmSidebar> createState() => CrmSidebarState();
}

class CrmSidebarState extends ConsumerState<CrmSidebar> {
  bool _isExpanded = false;
  final ScrollController _scrollController = ScrollController();

  /// Durante o tour guiado todas as seções ficam abertas: ExpansionTile
  /// recolhida não monta os filhos, e o tour mede cada módulo pela chave.
  bool _tourMode = false;

  /// Estado atual (usado pelo tour para restaurar ao final).
  bool get isExpanded => _isExpanded;

  /// Expande a sidebar e abre todas as seções para o tour guiado.
  void beginTour() {
    if (!mounted) return;
    setState(() {
      _isExpanded = true;
      _tourMode = true;
    });
  }

  /// Sai do modo tour; recolhe a sidebar se ela estava recolhida antes.
  void endTour({required bool collapse}) {
    if (!mounted) return;
    setState(() {
      _tourMode = false;
      if (collapse) _isExpanded = false;
    });
  }

  /// Rola a lista de módulos para o topo. Usado pelo tour guiado para começar
  /// sempre do primeiro item e ir descendo.
  Future<void> scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  /// Garante que o alvo de [key] (um item de módulo da lista rolável) esteja
  /// visível, rolando a sidebar o mínimo necessário. O tour chama isto antes de
  /// destacar cada passo para que balão e recorte fiquem sempre dentro da tela,
  /// mesmo em notebooks de tela baixa.
  Future<void> ensureKeyVisible(GlobalKey key,
      {double alignment = 0.15}) async {
    final ctx = key.currentContext;
    if (ctx == null || !_scrollController.hasClients) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: alignment,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final accessibleModules = ref.watch(accessibleModulesProvider);
    final selection = ref.watch(desktopSelectionProvider);
    final isPlatformOwner = ref.watch(isPlatformOwnerProvider);

    final comunicacao = accessibleModules
        .where((m) => m.section == ModuleSection.comunicacao)
        .toList(growable: false);
    final rh = accessibleModules
        .where((m) => m.section == ModuleSection.rh)
        .toList(growable: false);
    final financeiro = accessibleModules
        .where((m) => m.section == ModuleSection.financeiro)
        .toList(growable: false);
    final bottom = accessibleModules
        .where((m) =>
            m.section == ModuleSection.helpdesk ||
            m.section == ModuleSection.admin ||
            m.section == ModuleSection.operacoes ||
            m.section == ModuleSection.sistema)
        .toList(growable: false);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: _isExpanded ? 260.0 : 80.0,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        boxShadow: [
          if (_isExpanded)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(2, 0),
            )
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Hamburger Menu e Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: _isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  tooltip: _isExpanded ? 'Recolher Menu' : 'Expandir Menu',
                ),
                if (_isExpanded) ...[
                  const SizedBox(width: 8),
                  // Logo da empresa ao lado do nome do produto, quando houver.
                  const LogoEmpresa(altura: 28, comLogoDoProduto: false),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppConstants.appName,
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: theme.colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                ]
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    controller: _scrollController,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            // ── Seletor de empresa (só dono da plataforma) ──
                            // Alterna a empresa em atuação com o mesmo login.
                            PlatformOrgSwitcher(isExpanded: _isExpanded),

                            // ── COMUNICAÇÃO (abas do painel esquerdo) ──
                            if (comunicacao.isNotEmpty)
                              _buildSectionGroup('COMUNICAÇÃO', Icons.forum_outlined, comunicacao, theme, selection),

                            // ── RECURSOS HUMANOS (painel direito, gated RBAC) ──
                            if (rh.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildSectionGroup('RECURSOS HUMANOS', Icons.groups_outlined, rh, theme, selection),
                            ],

                            // ── FINANCEIRO (painel direito, gated RBAC) ──
                            if (financeiro.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildSectionGroup('FINANCEIRO', Icons.account_balance_outlined, financeiro, theme, selection),
                            ],

                            const Spacer(),

                            // ── Helpdesk / Admin / Operações (rodapé) ──
                            if (bottom.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              for (final m in bottom)
                                _buildModuleItem(m, theme, selection),
                            ],

                            // ── Console de Plataforma ──
                            // Vive numa build/host separado (`PLATFORM_ADMIN`).
                            // Nas builds de tenant (Fluxy e AlinhaJá) fica brand-guard:allow
                            // sempre ausente da sidebar.
                            if (AppEnv.isPlatformAdminBuild && isPlatformOwner)
                              _SidebarItem(
                                icon: Icons.hub_outlined,
                                activeIcon: Icons.hub_rounded,
                                label: 'Console de Plataforma',
                                isSelected: selection?.type == DesktopViewType.platformConsole,
                                badge: 0,
                                badgeColor: Colors.transparent,
                                isExpanded: _isExpanded,
                                onTap: () => ref.read(desktopSelectionProvider.notifier).state = const DesktopSelection(type: DesktopViewType.platformConsole),
                              ),

                            // ── Configurações (item intrínseco, sempre visível) ──
                            _SidebarItem(
                              icon: Icons.settings_outlined,
                              activeIcon: Icons.settings_rounded,
                              label: 'Configurações',
                              isSelected:
                                  selection?.type == DesktopViewType.settings,
                              badge: 0,
                              badgeColor: Colors.transparent,
                              isExpanded: _isExpanded,
                              onTap: () => ref
                                  .read(desktopSelectionProvider.notifier)
                                  .state = const DesktopSelection(
                                  type: DesktopViewType.settings),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              ),
              ),
            ),
          ),
            
          const SizedBox(height: 8),
          KeyedSubtree(
            key: HomeTourKeys.avatarMenu,
            child: _buildUserProfile(user, theme),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Constrói um item de navegação a partir de um [ModuleDescriptor].
  ///
  /// - Módulos [ModuleActivation.leftTab] alternam a aba do painel esquerdo
  ///   (Canais/Conversas/Chamadas) e mostram os badges de não lidos.
  /// - Módulos [ModuleActivation.rightPanel] selecionam a tela no painel
  ///   direito via [DesktopSelection.module].
  Widget _buildModuleItem(
    ModuleDescriptor m,
    ThemeData theme,
    DesktopSelection? selection,
  ) {
    final bool isLeftTab = m.activation == ModuleActivation.leftTab;

    // Badges: apenas as abas de comunicação exibem contadores de não lidos.
    int badge = 0;
    Color badgeColor = Colors.transparent;
    if (m.leftTabIndex == 0) {
      badge = widget.unreadChannels;
      badgeColor = theme.colorScheme.primary;
    } else if (m.leftTabIndex == 1) {
      badge = widget.unreadConversations;
      badgeColor = const Color(0xFFE65100);
    }

    final bool isSelected = isLeftTab
        ? widget.currentTabIndex == m.leftTabIndex
        : (selection?.type == DesktopViewType.module &&
            selection?.moduleId == m.id);

    final Widget item = _SidebarItem(
      icon: m.icon,
      activeIcon: m.activeIcon,
      label: m.title,
      isSelected: isSelected,
      badge: badge,
      badgeColor: badgeColor,
      isExpanded: _isExpanded,
      onTap: () {
        if (isLeftTab) {
          widget.onTabSelected(m.leftTabIndex ?? 0);
        } else {
          ref.read(desktopSelectionProvider.notifier).state =
              DesktopSelection.module(m.id);
        }
      },
    );

    // Cada item recebe a chave de tour do seu módulo — o walkthrough do
    // desktop percorre um passo por módulo realmente presente na sidebar.
    return KeyedSubtree(key: HomeTourKeys.moduleKey(m.id), child: item);
  }

  Widget _buildSectionGroup(
    String title,
    IconData icon,
    List<ModuleDescriptor> modules,
    ThemeData theme,
    DesktopSelection? selection,
  ) {
    if (modules.isEmpty) return const SizedBox.shrink();

    if (!_isExpanded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          for (final m in modules) _buildModuleItem(m, theme, selection),
        ],
      );
    }

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        // Chave própria no tour: força uma ExpansionTile nova, aberta, sem
        // herdar (nem sobrescrever) o estado que o usuário deixou no
        // PageStorage — ao sair do tour a seção volta como estava.
        key: PageStorageKey('section_$title${_tourMode ? '_tour' : ''}'),
        initiallyExpanded: _tourMode || title == 'COMUNICAÇÃO',
        tilePadding: const EdgeInsets.only(left: 20, right: 16),
        childrenPadding: const EdgeInsets.only(left: 8),
        leading: Icon(
          icon,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          size: 20,
        ),
        title: Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          for (final m in modules) _buildModuleItem(m, theme, selection),
        ],
      ),
    );
  }

  Widget _buildUserProfile(dynamic user, ThemeData theme) {
    return InkWell(
      onTap: () {
         ref.read(desktopSelectionProvider.notifier).state = const DesktopSelection(type: DesktopViewType.profile);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _isExpanded ? 16 : 0, vertical: 8),
        child: Row(
          mainAxisAlignment: _isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage: user?.avatarUrl != null ? CachedNetworkImageProvider(user!.avatarUrl!, maxWidth: 320) : null,
              child: user?.avatarUrl == null
                  ? Text(
                      user?.fullName.isNotEmpty == true ? user!.fullName[0].toUpperCase() : '?',
                      style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            if (_isExpanded) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user?.fullName ?? 'Usuário',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      user?.roleLevel ?? 'Colaborador',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final int badge;
  final Color badgeColor;
  final bool isExpanded;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.badge,
    required this.badgeColor,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    final bgColor = isSelected ? theme.colorScheme.primary.withValues(alpha: 0.1) : Colors.transparent;

    Widget child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
        padding: EdgeInsets.symmetric(horizontal: isExpanded ? 16 : 0),
        child: Row(
          mainAxisAlignment: isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text(badge > 99 ? '99+' : badge.toString(), style: const TextStyle(fontSize: 10, color: Colors.white)),
              backgroundColor: badgeColor,
              child: Icon(isSelected ? activeIcon : icon, color: color, size: 24),
            ),
            if (isExpanded) ...[
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
            ]
          ],
        ),
      ),
    );

    if (!isExpanded) {
      child = Tooltip(message: label, preferBelow: false, child: child);
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isExpanded ? 12 : 8, vertical: 2),
      child: child,
    );
  }
}
