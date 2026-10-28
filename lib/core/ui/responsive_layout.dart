import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/features/chats/ui/main_scaffold.dart';
import 'package:alinha_ja/core/providers/desktop_selection_provider.dart';
import 'package:alinha_ja/features/chat/ui/chat_screen.dart';
import 'package:alinha_ja/features/workflow/ui/workflow_main_view.dart';
import 'package:alinha_ja/features/profile/ui/profile_screen.dart';
import 'package:alinha_ja/features/settings/ui/settings_screen.dart';
import 'package:alinha_ja/core/providers/chat_tab_provider.dart';
import 'package:alinha_ja/features/support/ui/support_dashboard_screen.dart';
import 'package:alinha_ja/features/chat/ui/starred_messages_screen.dart';
import 'package:alinha_ja/features/chats/ui/new_chat_screen.dart';
import 'package:alinha_ja/core/modules/module_registry.dart';
import 'package:alinha_ja/core/modules/module_access_provider.dart';
import 'package:alinha_ja/core/ui/components/crm_sidebar.dart';
import 'package:alinha_ja/features/platform/ui/platform_console_screen.dart';
import 'package:alinha_ja/features/chats/ui/chats_list_screen.dart';
import 'package:alinha_ja/features/chats/models/chat_model.dart';
import 'package:alinha_ja/features/onboarding/onboarding_keys.dart';
import 'package:alinha_ja/core/constants.dart';

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _NewChatIntent extends Intent {
  const _NewChatIntent();
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

/// Breakpoint para alternar entre layout mobile e desktop.
const double kDesktopBreakpoint = 800;

/// Widget raiz que decide entre o layout mobile (telas inteiras com GoRouter)
/// e o layout desktop (master-detail com painel dividido).
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kDesktopBreakpoint) {
          // Mobile: fluxo nativo com Navigator/GoRouter
          return const MainScaffold();
        }
        // Desktop: master-detail
        return const DesktopMainScreen();
      },
    );
  }
}

/// Layout master-detail estilo WhatsApp Web.
/// Painel esquerdo: lista (MainScaffold) | Painel direito: chat/canal selecionado.
class DesktopMainScreen extends ConsumerStatefulWidget {
  const DesktopMainScreen({super.key});

  @override
  ConsumerState<DesktopMainScreen> createState() => _DesktopMainScreenState();
}

class _DesktopMainScreenState extends ConsumerState<DesktopMainScreen> {
  double _sidebarWidth = 450.0;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(desktopSelectionProvider);
    final focusMode = ref.watch(desktopFocusModeProvider);
    final currentTab = ref.watch(chatTabProvider);
    final accessibleModuleIds = ref.watch(accessibleModuleIdsProvider);
    final theme = Theme.of(context);

    // Obter as contagens não lidas globais (se quisermos manter o badge na sidebar)
    final chatsAsyncValue = ref.watch(chatsListProvider);
    int unreadChannels = 0;
    int unreadConversations = 0;
    chatsAsyncValue.whenData((List<ChatModel> chats) {
      for (final chat in chats) {
        if (chat.type == ChatType.channel) {
          unreadChannels += chat.unreadCount;
        } else {
          unreadConversations += chat.unreadCount;
        }
      }
    });

    // Garante que não ultrapasse 50% em telas menores logo no início
    final screenWidth = MediaQuery.of(context).size.width;
    if (_sidebarWidth > screenWidth * 0.5) {
      _sidebarWidth = screenWidth * 0.5;
    }

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _SearchIntent(), // Ctrl+K
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _SearchIntent(), // Cmd+K (Mac)
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _NewChatIntent(), // Ctrl+N
        SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            _NewChatIntent(), // Cmd+N (Mac)
        SingleActivator(LogicalKeyboardKey.escape): _EscapeIntent(), // Esc
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (intent) => context.push('/search'),
          ),
          _NewChatIntent: CallbackAction<_NewChatIntent>(
            onInvoke: (intent) => context.push('/contacts'),
          ),
          _EscapeIntent: CallbackAction<_EscapeIntent>(
            onInvoke: (intent) {
              // Esc devolve os menus antes de largar a conversa aberta.
              if (focusMode) {
                ref.read(desktopFocusModeProvider.notifier).state = false;
              } else if (selection != null) {
                ref.read(desktopSelectionProvider.notifier).state = null;
              }
              return null;
            },
          ),
        },
        child: FocusScope(
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: [
                // Se o focus mode estiver ativado, omitimos a barra lateral e o divisor
                if (!focusMode) ...[
                  // ── Sidebar CRM (NOVA) ──
                  CrmSidebar(
                    key: HomeTourKeys.crmSidebar,
                    unreadChannels: unreadChannels,
                    unreadConversations: unreadConversations,
                    currentTabIndex: currentTab,
                    onTabSelected: (index) => ref.read(chatTabProvider.notifier).state = index,
                  ),

                  // ── Painel Esquerdo: Lista de Conversas ──
                  SizedBox(
                    width: _sidebarWidth,
                    child: const MainScaffold(),
                  ),

                  // ── Divisor Vertical (Redimensionável) ──
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (details) {
                        setState(() {
                          _sidebarWidth += details.delta.dx;
                          if (_sidebarWidth < 320.0) {
                            _sidebarWidth = 320.0;
                          } else if (_sidebarWidth > screenWidth * 0.5) {
                            _sidebarWidth = screenWidth * 0.5;
                          }
                        });
                      },
                      child: Container(
                        width: 4,
                        color: Colors.transparent,
                        child: Center(
                          child: Container(
                            width: 1,
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                // ── Painel Direito: Chat/Canal Selecionado ──
                Expanded(
                  child: Stack(
                    children: [
                      // O conteúdo em si
                      Positioned.fill(
                        child: selection == null
                            ? _DesktopPlaceholder(theme: theme)
                            : _buildRightPanel(
                                selection, accessibleModuleIds, theme),
                      ),
                      // Alternador do Modo Foco: puxador estreito colado na
                      // borda esquerda do painel, centralizado na vertical.
                      // Ficava como FAB no canto inferior esquerdo, onde
                      // cobria o botão de anexos da barra de mensagem.
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _FocusModeHandle(
                            focusMode: focusMode,
                            onToggle: () => ref
                                .read(desktopFocusModeProvider.notifier)
                                .state = !focusMode,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanel(
    DesktopSelection selection,
    Set<String> accessibleModuleIds,
    ThemeData theme,
  ) {
    switch (selection.type) {
      case DesktopViewType.chat:
        return ChatScreen(
          key: ValueKey('chat-${selection.id}'),
          chatId: selection.id ?? '',
          chatName: selection.name ?? '',
          isGroup: selection.isGroup,
        );
      case DesktopViewType.workflow:
        return WorkflowMainView(
          key: ValueKey('channel-${selection.id}'),
          channelId: selection.id ?? '',
          channelName: selection.name ?? '',
        );
      case DesktopViewType.profile:
        return const ProfileScreen(key: ValueKey('profile'));
      case DesktopViewType.settings:
        return const SettingsScreen(key: ValueKey('settings'));
      case DesktopViewType.support:
        return const SupportDashboardScreen(key: ValueKey('support'));
      case DesktopViewType.starred:
        return const StarredMessagesScreen(key: ValueKey('starred'));
      case DesktopViewType.contacts:
        return const NewChatScreen(key: ValueKey('contacts'));
      case DesktopViewType.module:
        // Tela de um módulo do registro — guarda RBAC única.
        final moduleId = selection.moduleId;
        final module = moduleId == null ? null : moduleById(moduleId);
        if (module == null || !accessibleModuleIds.contains(moduleId)) {
          return _AccessDeniedPlaceholder(theme: theme);
        }
        return KeyedSubtree(
          key: ValueKey('module-$moduleId'),
          child: Builder(builder: module.effectiveDesktopBuilder),
        );
      case DesktopViewType.platformConsole:
        return const PlatformConsoleScreen(key: ValueKey('platform_console'));
    }
  }
}

/// Puxador do Modo Foco — faixa estreita na borda esquerda do painel direito.
///
/// Fica discreto (quase transparente) e ganha destaque no hover, sem disputar
/// espaço com a barra de mensagem nem com as ações da AppBar.
class _FocusModeHandle extends StatefulWidget {
  final bool focusMode;
  final VoidCallback onToggle;

  const _FocusModeHandle({required this.focusMode, required this.onToggle});

  @override
  State<_FocusModeHandle> createState() => _FocusModeHandleState();
}

class _FocusModeHandleState extends State<_FocusModeHandle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: widget.focusMode
          ? 'Sair do Modo Foco'
          : 'Modo Foco (ocultar menus)',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onToggle,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _hovering ? 1.0 : 0.35,
            child: Container(
              width: 16,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(8),
                ),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Icon(
                widget.focusMode
                    ? Icons.chevron_right_rounded
                    : Icons.chevron_left_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessDeniedPlaceholder extends StatelessWidget {
  final ThemeData theme;
  const _AccessDeniedPlaceholder({required this.theme});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 24),
            Text(
              'Acesso Negado',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Você não tem permissão para acessar este módulo.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder elegante exibido quando nenhum chat está selecionado.
class _DesktopPlaceholder extends StatelessWidget {
  final ThemeData theme;
  const _DesktopPlaceholder({required this.theme});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Image.asset(
                  'assets/images/logo_header.png',
                  width: 56,
                  height: 56,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.chat_rounded,
                    size: 48,
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '${AppConstants.appName} para Desktop',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
                fontFamily: 'Outfit',
                fontFamilyFallback: const ['Segoe UI', 'Roboto', 'sans-serif'],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Selecione uma conversa para começar.',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    'Suas conversas são criptografadas de ponta a ponta',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
