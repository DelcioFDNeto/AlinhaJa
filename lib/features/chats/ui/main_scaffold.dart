import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/modules/module_descriptor.dart';
import 'package:alinha_ja/core/modules/module_access_provider.dart';
import 'package:alinha_ja/core/modules/module_registry.dart';
import 'package:alinha_ja/features/chats/ui/chats_list_screen.dart';
import 'package:alinha_ja/features/chats/ui/channels_tab.dart';
import 'package:alinha_ja/features/chats/ui/calls_tab.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/core/providers/presence_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alinha_ja/core/providers/chat_tab_provider.dart';
import 'package:alinha_ja/core/ui/responsive_layout.dart';
import 'package:alinha_ja/features/chats/models/chat_model.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/providers/desktop_selection_provider.dart';
import 'package:alinha_ja/features/legal/providers/legal_provider.dart';
import 'package:alinha_ja/features/onboarding/onboarding_keys.dart';
import 'package:alinha_ja/features/onboarding/onboarding_launcher.dart';
import 'package:alinha_ja/features/onboarding/tour_replay_provider.dart';
import 'package:alinha_ja/core/constants.dart';

/// Scaffold principal com BottomNavigationBar estilo WhatsApp.
/// Usa IndexedStack para preservar o estado de cada aba.
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}
class _MainScaffoldState extends ConsumerState<MainScaffold> {
  /// Guarda para o disparo automático da introdução.
  ///
  /// A tentativa acontece em dois momentos (pós-frame inicial e quando o
  /// aceite de política resolve); sem isto o carrossel abriria duas vezes.
  bool _onboardingDisparado = false;

  @override
  void initState() {
    super.initState();
    // Inicializa o serviço silencioso de presença em tempo real
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(presenceServiceProvider).init();
      _talvezAbrirOnboarding();
    });
  }

  /// Abre a introdução + tour do 1º login, mas só quando o portão de aceite
  /// já decidiu que esta tela pode ficar.
  ///
  /// **Por que esperar.** `PolicyGate` devolve `child` enquanto a consulta de
  /// aceites está carregando (fail-open deliberado), então este scaffold monta
  /// antes de se saber se há documento pendente. Disparando aqui sem
  /// checar, no primeiro acesso o carrossel subia no `rootNavigator` — acima
  /// de tudo — e logo em seguida o portão trocava o app pela tela de
  /// consentimento. O resultado era o pior dos dois mundos: carrossel por cima
  /// do aceite, `markSeen` gravado, e o tour de coach marks pulado porque os
  /// alvos já tinham sido desmontados. Ou seja, quem entrava pela primeira vez
  /// perdia o tour para sempre.
  ///
  /// Com o aceite pendente não fazemos nada: o scaffold será desmontado e,
  /// depois do aceite, remontado — e aí o `initState` roda de novo com o
  /// caminho livre. Erro na consulta segue em frente de propósito, para
  /// acompanhar o mesmo fail-open do portão.
  void _talvezAbrirOnboarding() {
    if (_onboardingDisparado || !mounted) return;

    final aceites = ref.read(pendingPoliciesProvider);
    if (aceites.isLoading) return;
    if (aceites.valueOrNull?.isNotEmpty ?? false) return;

    _onboardingDisparado = true;
    launchOnboarding(context);
  }

  // As 3 abas — IndexedStack mantém todas vivas para preservar scroll/estado
  static const _tabs = <Widget>[
    ChannelsTab(), // 📢 Canais
    ChatsListScreen(), // 💬 Conversas (DMs + Grupos)
    CallsTab(), // 📞 Chamadas
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // "Rever tutorial" pedido de uma tela empilhada (ex.: Central de Ajuda no
    // mobile): a tela setou o flag e navegou para a home. Aqui, já na home com
    // os alvos do tour montados, disparamos o fluxo e limpamos o flag.
    // Quando o portão de aceite resolve (com ou sem documento pendente), esta
    // tela pode ter continuado montada — é o caso de quem já aceitou tudo.
    // Aí é aqui que a introdução do 1º login finalmente sai.
    ref.listen(pendingPoliciesProvider, (prev, next) {
      if (next.isLoading) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _talvezAbrirOnboarding();
      });
    });

    ref.listen<bool>(tourReplayProvider, (prev, next) {
      if (next) {
        ref.read(tourReplayProvider.notifier).state = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) launchOnboarding(context, reset: true);
        });
      }
    });

    // Obter as listas de chats globalmente para computar os badges de notificações
    final chatsAsyncValue = ref.watch(chatsListProvider);
    int unreadChannels = 0;
    int unreadConversations = 0;

    chatsAsyncValue.whenData((chats) {
      for (final chat in chats) {
        if (chat.type == ChatType.channel) {
          unreadChannels += chat.unreadCount;
        } else {
          unreadConversations += chat.unreadCount;
        }
      }
    });

    final isDesktop = MediaQuery.of(context).size.width >= kDesktopBreakpoint;

    final currentIndex = ref.watch(chatTabProvider);

    if (isDesktop) {
      return Scaffold(
        appBar: _buildGlobalHeader(context, theme, isDesktop: true, currentIndex: currentIndex),
        body: IndexedStack(
          index: currentIndex,
          children: _tabs,
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      appBar: _buildGlobalHeader(context, theme, isDesktop: false, currentIndex: currentIndex),
      body: IndexedStack(
        index: currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.92),
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                KeyedSubtree(
                  key: HomeTourKeys.tabCanais,
                  child: _NavItem(
                    icon: Icons.campaign_outlined,
                    activeIcon: Icons.campaign_rounded,
                    label: 'Canais',
                    isSelected: currentIndex == 0,
                    badge: unreadChannels,
                    badgeColor: theme.colorScheme.primary,
                    theme: theme,
                    onTap: () => ref.read(chatTabProvider.notifier).state = 0,
                  ),
                ),
                KeyedSubtree(
                  key: HomeTourKeys.tabConversas,
                  child: _NavItem(
                    icon: Icons.chat_bubble_outline_rounded,
                    activeIcon: Icons.chat_bubble_rounded,
                    label: 'Conversas',
                    isSelected: currentIndex == 1,
                    badge: unreadConversations,
                    badgeColor: const Color(0xFFE65100),
                    theme: theme,
                    onTap: () => ref.read(chatTabProvider.notifier).state = 1,
                  ),
                ),
                KeyedSubtree(
                  key: HomeTourKeys.tabChamadas,
                  child: _NavItem(
                    icon: Icons.videocam_outlined,
                    activeIcon: Icons.videocam_rounded,
                    label: 'Chamadas',
                    isSelected: currentIndex == 2,
                    badge: 0,
                    badgeColor: Colors.transparent,
                    theme: theme,
                    onTap: () => ref.read(chatTabProvider.notifier).state = 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildGlobalHeader(BuildContext context, ThemeData theme,
      {bool isDesktop = false, required int currentIndex}) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.valueOrNull;
    final accessibleModules = ref.watch(accessibleModulesProvider);

    // Ações contextuais por aba
    List<Widget> actions = [];
    if (currentIndex == 0) {
      actions.addAll([
        IconButton(
          icon: const Icon(Icons.explore_outlined),
          tooltip: 'Explorar Canais',
          onPressed: () => context.push('/channels/discover'),
        ),
        IconButton(
          key: HomeTourKeys.search,
          icon: const Icon(Icons.search),
          onPressed: () => context.push('/search'),
        ),
      ]);
    } else if (currentIndex == 1) {
      actions.add(
        IconButton(
          key: HomeTourKeys.search,
          icon: const Icon(Icons.search),
          onPressed: () => context.push('/search'),
        ),
      );
    } else if (currentIndex == 2) {
      // actions for calls tab (empty for now)
    }

    // Atalhos globais de módulos (Helpdesk, ...) — visíveis em qualquer
    // aba. Derivados do registro de módulos e gateados pelo mesmo RBAC.
    for (final m in accessibleModules.where((m) =>
        m.section == ModuleSection.helpdesk)) {
      actions.add(
        IconButton(
          key: isDesktop ? null : HomeTourKeys.headerModuleKey(m.id),
          icon: Icon(m.icon),
          tooltip: m.title,
          onPressed: () => isDesktop
              ? ref.read(desktopSelectionProvider.notifier).state =
                  DesktopSelection.module(m.id)
              : context.push(Uri.parse(m.route).path),
        ),
      );
    }

    if (!isDesktop) {
      // Menu de módulos mobile — equivalente à sidebar do desktop: todo
      // módulo de painel liberado pelo RBAC (RH, Financeiro, Admin...), menos
      // os que já têm atalho próprio no header (Helpdesk).
      final menuModules = mobileMenuModules(accessibleModules);

      if (menuModules.isNotEmpty) {
        actions.add(
          PopupMenuButton<String>(
            key: HomeTourKeys.modulesMenu,
            offset: const Offset(0, 48),
            icon: const Icon(Icons.apps_rounded, color: Colors.deepOrange),
            tooltip: 'Módulos',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (route) => context.push(route),
            itemBuilder: (ctx) => [
              for (final (i, m) in menuModules.indexed) ...[
                if (i == 0 || menuModules[i - 1].section != m.section)
                  PopupMenuItem<String>(
                    enabled: false,
                    height: 32,
                    child: Text(
                      moduleSectionLabel(m.section),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                PopupMenuItem(
                  value: Uri.parse(m.route).path,
                  child: Row(children: [
                    Icon(m.icon, size: 20, color: Colors.deepOrange),
                    const SizedBox(width: 8),
                    Text(m.title),
                  ]),
                ),
              ],
            ],
          ),
        );
      }

      // Menu Global (Avatar + Dropdown) — visível apenas no topo no modo Mobile
      actions.add(
        PopupMenuButton<String>(
          key: HomeTourKeys.avatarMenu,
          offset: const Offset(0, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          icon: CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage: user?.avatarUrl != null
                ? CachedNetworkImageProvider(user!.avatarUrl!, maxWidth: 320)
                : null,
            child: user?.avatarUrl == null
                ? Text(
                    user?.fullName.isNotEmpty == true
                        ? user!.fullName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
          onSelected: (value) async {
            switch (value) {
              case 'profile':
                context.push('/profile');
                break;
              case 'starred':
                context.push('/starred');
                break;
              case 'my_operation':
                context.push('/minha-operacao');
                break;
              case 'new_chat':
                context.push('/contacts');
                break;
              case 'support':
                context.push('/support');
                break;
              case 'help':
                context.push('/support/help');
                break;
              case 'mark_read':
                final userId = supabase.auth.currentUser?.id;
                if (userId != null) {
                  try {
                    await supabase.rpc('mark_all_chats_as_read', params: {
                      'p_user_id': userId,
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Todas as conversas foram marcadas como lidas.')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro ao marcar como lido: $e')),
                      );
                    }
                  }
                }
                break;
              case 'settings':
                context.push('/settings');
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'profile',
              child: ListTile(
                leading: Icon(Icons.person_outline_rounded),
                title: Text('Meu Perfil'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'starred',
              child: ListTile(
                leading: Icon(Icons.star_outline_rounded, color: Colors.amber),
                title: Text('Mensagens Favoritas'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            // A tela existia desde a v1.3.7, mas nenhum menu levava até ela:
            // só era alcançável digitando a URL na versão web.
            const PopupMenuItem(
              value: 'my_operation',
              child: ListTile(
                leading: Icon(Icons.assignment_ind_outlined),
                title: Text('Minha Operação'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'new_chat',
              child: ListTile(
                leading: Icon(Icons.group_add_outlined),
                title: Text('Novo Grupo / Chat'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'support',
              child: ListTile(
                leading: Icon(Icons.headset_mic_rounded, color: Colors.teal),
                title: Text('Suporte T.I.'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'help',
              child: ListTile(
                leading: Icon(Icons.help_outline_rounded, color: Colors.blue),
                title: Text('Central de Ajuda'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'mark_read',
              child: ListTile(
                leading: Icon(Icons.done_all_rounded),
                title: Text('Marcar tudo como lido'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'settings',
              child: ListTile(
                leading: Icon(Icons.settings_outlined),
                title: Text('Configurações'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      );
    }

    return AppBar(
      title: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo_header.png',
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            Text(
              AppConstants.appName,
              style: GoogleFonts.outfit(
                textStyle: theme.textTheme.titleLarge,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
      centerTitle: false,
      actions: actions,
      elevation: 0,
      scrolledUnderElevation: 2,
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

// ─── Custom NavItem Widget (Premium, Device-Integrated Feel) ────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final int badge;
  final Color badgeColor;
  final ThemeData theme;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.badge,
    required this.badgeColor,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 20 : 16,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text(
                badge > 99 ? '99+' : badge.toString(),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
              backgroundColor: badgeColor,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isSelected ? activeIcon : icon,
                  key: ValueKey(isSelected),
                  size: 24,
                  color: color,
                ),
              ),
            ),
            // Label só aparece quando selecionado (estilo iOS nativo)
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: isSelected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                          letterSpacing: -0.2,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Desktop Web Sidebar (WhatsApp Web Style) ──────────────

// _WebSidebar removed as it was extracted to CrmSidebar.
