import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/auth/ui/login_screen.dart';
import 'package:alinha_ja/features/auth/ui/signup_screen.dart';
import 'package:alinha_ja/core/ui/responsive_layout.dart';
import 'package:alinha_ja/features/chats/ui/new_chat_screen.dart';
import 'package:alinha_ja/features/chat/ui/chat_screen.dart';
import 'package:alinha_ja/features/chat/ui/thread_screen.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/admin/ui/edit_profile_screen.dart';
import 'package:alinha_ja/features/admin/ui/moderation_screen.dart';
import 'package:alinha_ja/features/admin/ui/usage_reports_screen.dart';
import 'package:alinha_ja/features/profile/ui/profile_screen.dart';
import 'package:alinha_ja/features/profile/ui/user_activity_history_screen.dart';
import 'package:alinha_ja/features/chats/ui/search_screen.dart';
import 'package:alinha_ja/features/chats/ui/channel_create_screen.dart';
import 'package:alinha_ja/features/chats/ui/channel_discovery_screen.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/features/hr/ui/meus_documentos_screen.dart';
import 'package:alinha_ja/features/hr/ui/absences/my_absences_screen.dart';
import 'package:alinha_ja/features/hr/ui/my_time_clock_screen.dart';
import 'package:alinha_ja/features/hr/ui/my_onboarding_screen.dart';
import 'package:alinha_ja/features/hr/ui/my_performance_screen.dart';
import 'package:alinha_ja/features/hr/ui/my_payslips_screen.dart';
import 'package:alinha_ja/features/calls/ui/active_call_screen.dart';
import 'package:alinha_ja/features/calls/ui/mirotalk/mirotalk_screen.dart';
import 'package:alinha_ja/features/workflow/ui/workflow_main_view.dart';
import 'package:alinha_ja/features/workflow/ui/my_operation_screen.dart';
import 'package:alinha_ja/features/chat/ui/chat_info_screen.dart';
import 'package:alinha_ja/features/channels/ui/channel_info_screen.dart';
import 'package:alinha_ja/features/channels/ui/workspace_edit_screen.dart';
import 'package:alinha_ja/features/channels/ui/workspace_preset_manager_screen.dart';
import 'package:alinha_ja/features/channels/ui/channel_thread_screen.dart';
import 'package:alinha_ja/features/channels/models/channel_message_model.dart';
import 'package:alinha_ja/features/chat/ui/starred_messages_screen.dart';
import 'package:alinha_ja/features/chats/ui/new_dm_redirect_screen.dart';
import 'package:alinha_ja/features/settings/ui/settings_screen.dart';
import 'package:alinha_ja/features/settings/ui/notification_settings_screen.dart';
import 'package:alinha_ja/features/settings/ui/changelog_screen.dart';
import 'package:alinha_ja/features/admin/ui/employee_management_screen.dart';
import 'package:alinha_ja/features/hr/ui/candidate_detail_screen.dart';
import 'package:alinha_ja/features/hr/ui/careers_screen.dart';
import 'package:alinha_ja/features/hr/ui/candidate_area_screen.dart';
import 'package:alinha_ja/features/hr/ui/candidate_portal/candidate_login_screen.dart';
import 'package:alinha_ja/features/hr/ui/candidate_portal/candidate_signup_screen.dart';
import 'package:alinha_ja/features/hr/ui/candidate_portal/candidate_verify_screen.dart';
import 'package:alinha_ja/features/hr/ui/candidate_portal/candidate_dashboard_screen.dart';
import 'package:alinha_ja/features/hr/ui/employee_detail_screen.dart';
import 'package:alinha_ja/features/auth/ui/splash_screen.dart';
import 'package:alinha_ja/features/support/ui/support_dashboard_screen.dart';
import 'package:alinha_ja/features/support/ui/create_ticket_screen.dart';
import 'package:alinha_ja/features/support/ui/ticket_chat_screen.dart';
import 'package:alinha_ja/features/location/ui/location_tracking_screen.dart';
import 'package:alinha_ja/core/ui/call_overlay_wrapper.dart';
import 'package:alinha_ja/features/auth/ui/verify_2fa_screen.dart';
import 'package:alinha_ja/features/auth/ui/verify_email_2fa_screen.dart';
import 'package:alinha_ja/features/auth/ui/trusted_devices_screen.dart';
import 'package:alinha_ja/features/auth/ui/mfa_enrollment_screen.dart';
import 'package:alinha_ja/features/auth/ui/security_2fa_screen.dart';
import 'package:alinha_ja/features/auth/ui/update_password_screen.dart';
import 'package:alinha_ja/features/auth/ui/force_change_password_screen.dart';
import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/core/modules/module_routes.dart';
import 'package:alinha_ja/features/legal/ui/legal_document_screen.dart';
import 'package:alinha_ja/features/legal/ui/policy_gate.dart';
import 'package:alinha_ja/features/backup/ui/backup_screen.dart';
import 'package:alinha_ja/features/legal/ui/privacy_center_screen.dart';

/// Instância global do GoRouter para permitir navegação sem BuildContext
/// (útil para eventos de background como CallKit ou Push Notifications)
final goRouter = GoRouter(
  navigatorKey: Globals.navigatorKey,
  initialLocation: '/',
  redirect: (context, state) {
    final isLoggedIn = supabase.auth.currentUser != null;
    final loc = state.matchedLocation;
    final isOnSplash = loc == '/';
    final isOnLogin = loc.startsWith('/login');
    final isOnSignup = loc.startsWith('/signup');
    final isOnVerify = loc.startsWith('/verify-2fa') ||
        loc.startsWith('/verify-email-2fa');
    final isOnMfaSetup = loc.startsWith('/mfa-setup');
    final isOnUpdatePassword = loc.startsWith('/update-password') ||
        loc.startsWith('/force-change-password');
    final isOnAuth = isOnSplash || isOnLogin || isOnSignup;

    // Rotas públicas do Portal do Candidato (RH-2): acessíveis sem login
    // e sem exigência de 2FA — não tocam em dados internos (Edge Function).
    final isOnPublicPortal =
        loc.startsWith('/carreiras') || loc.startsWith('/candidato');
    if (isOnPublicPortal) return null;

    // Não autenticado tentando acessar área protegida → login.
    if (!isLoggedIn &&
        !isOnAuth &&
        !isOnVerify &&
        !isOnMfaSetup &&
        !isOnUpdatePassword) {
      return '/login';
    }

    if (isLoggedIn) {
      final verified = Globals.is2faVerified;

      // Logado mas ainda sem 2FA cumprido: só pode permanecer no splash (que
      // resolve o nível de garantia da sessão), na verificação, na configuração
      // do 2FA ou na redefinição de senha (sessão de recovery). Qualquer outra
      // rota — inclusive voltar para /login pelo histórico do navegador — é
      // redirecionada para a verificação, fechando o bypass do "voltar aba".
      if (!verified &&
          !isOnSplash &&
          !isOnVerify &&
          !isOnMfaSetup &&
          !isOnUpdatePassword) {
        return '/verify-2fa';
      }

      // Build de admin (Console de Plataforma, host separado):
      // Cai em /chats normalmente, e de lá abre o Console no painel direito.
      if (AppEnv.isPlatformAdminBuild && verified) {
        if (isOnLogin || isOnSignup) return '/chats';
        return null;
      }

      // Já verificado e ainda numa tela de auth → entra no app.
      if (verified && (isOnLogin || isOnSignup)) {
        return '/chats';
      }
    }

    return null;
  },
  routes: [
    // -- Rotas de Auth (sem CallOverlayWrapper) --
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const SignUpScreen()),
    GoRoute(
      path: '/verify-2fa',
      builder: (context, state) => const Verify2FAScreen(),
    ),
    GoRoute(
      path: '/verify-email-2fa',
      builder: (context, state) => const VerifyEmail2FAScreen(),
    ),
    GoRoute(
      path: '/update-password',
      builder: (context, state) => const UpdatePasswordScreen(),
    ),
    GoRoute(
      path: '/force-change-password',
      builder: (context, state) => const ForceChangePasswordScreen(),
    ),
    GoRoute(
      path: '/mfa-setup',
      builder: (context, state) {
        final onboarding = (state.extra as Map<String, dynamic>?)?['onboarding']
                as bool? ??
            false;
        return MfaEnrollmentScreen(isOnboarding: onboarding);
      },
    ),

    // -- Portal do Candidato (público, sem auth) --
    GoRoute(
      path: '/carreiras/:slug',
      builder: (context, state) =>
          CareersScreen(orgSlug: state.pathParameters['slug'] ?? ''),
    ),
    GoRoute(
      path: '/carreiras/:slug/vaga/:vagaId',
      builder: (context, state) => CareersScreen(
        orgSlug: state.pathParameters['slug'] ?? '',
        vagaId: state.pathParameters['vagaId'],
      ),
    ),
    GoRoute(
      path: '/candidato/login',
      builder: (context, state) => const CandidateLoginScreen(),
    ),
    GoRoute(
      path: '/candidato/signup',
      builder: (context, state) => const CandidateSignupScreen(),
    ),
    GoRoute(
      path: '/candidato/verify',
      builder: (context, state) => CandidateVerifyScreen(
        token: state.uri.queryParameters['token'],
      ),
    ),
    GoRoute(
      path: '/candidato/verify-sent',
      builder: (context, state) => const CandidateVerifyScreen(),
    ),
    GoRoute(
      path: '/candidato/dashboard',
      builder: (context, state) => const CandidateDashboardScreen(),
    ),
    GoRoute(
      path: '/candidato/:token',
      builder: (context, state) =>
          CandidateAreaScreen(token: state.pathParameters['token'] ?? ''),
    ),

    // -- Rotas autenticadas (com CallOverlayWrapper) --
    ShellRoute(
      builder: (context, state, child) {
        // PolicyGate por dentro: se houver documento pendente de aceite, ele
        // substitui o app inteiro — mas a chamada em curso continua visível.
        return CallOverlayWrapper(child: PolicyGate(child: child));
      },
      routes: [
        GoRoute(
          path: '/contacts',
          builder: (context, state) => const NewChatScreen(),
        ),
        // -- LGPD: central de privacidade e leitor de documentos --
        GoRoute(
          path: '/privacidade',
          builder: (context, state) => const PrivacyCenterScreen(),
        ),
        // Backup do titular: fica junto da privacidade, não do painel admin.
        GoRoute(
          path: '/backup',
          builder: (context, state) => const BackupScreen(),
        ),
        GoRoute(
          path: '/legal/:id',
          builder: (context, state) => LegalDocumentScreen(
            documentId: state.pathParameters['id'] ?? '',
          ),
        ),
        GoRoute(
          path: '/chats',
          builder: (context, state) => const ResponsiveLayout(),
        ),
        GoRoute(
          path: '/workspace',
          redirect: (context, state) => '/chats',
        ),
        GoRoute(
          path: '/meus-documentos',
          builder: (context, state) => const MeusDocumentosScreen(),
        ),
        GoRoute(
          path: '/meus-afastamentos',
          builder: (context, state) => const MyAbsencesScreen(),
        ),
        GoRoute(
          path: '/meu-ponto',
          builder: (context, state) => const MyTimeClockScreen(),
        ),
        GoRoute(
          path: '/meus-holerites',
          builder: (context, state) => const MyPayslipsScreen(),
        ),
        GoRoute(
          path: '/meu-onboarding',
          builder: (context, state) => const MyOnboardingScreen(),
        ),
        GoRoute(
          path: '/meu-desempenho',
          builder: (context, state) => const MyPerformanceScreen(),
        ),
        GoRoute(
          path: '/chat/new_dm_:id',
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            final extra = state.extra as Map<String, dynamic>? ?? {};
            final targetUser = extra['targetUser'] as UserModel?;
            return NewDmRedirectScreen(
              targetUserId: id,
              targetUser: targetUser,
            );
          },
        ),
        GoRoute(
          path: '/chat/:id',
          builder: (context, state) {
            final chatId = state.pathParameters['id']!;
            final extra = state.extra as Map<String, dynamic>?;
            final chatName = extra?['name'] as String? ?? 'Chat';
            final isGroup = extra?['isGroup'] as bool? ?? false;
            return ChatScreen(
              chatId: chatId,
              chatName: chatName,
              isGroup: isGroup,
            );
          },
        ),
        GoRoute(
          path: '/chat/:id/info',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return ChatInfoScreen(
                chatId: id,
                chatName: extra['name'] as String? ?? 'Info',
                isGroup: extra['isGroup'] as bool? ?? false,
                targetUser: extra['targetUser'] as UserModel?);
          },
        ),
        GoRoute(
          path: '/chat/:id/thread/:messageId',
          builder: (context, state) {
            final chatId = state.pathParameters['id']!;
            final extra = state.extra as Map<String, dynamic>?;
            final chatName = extra?['chatName'] as String? ?? 'Desconhecido';
            final parentMessage = extra?['parentMessage'] as MessageModel?;

            if (parentMessage == null) {
              return const Scaffold(
                  body:
                      Center(child: Text('Mensagem original não encontrada')));
            }

            return ThreadScreen(
              chatId: chatId,
              chatName: chatName,
              parentMessage: parentMessage,
            );
          },
        ),
        // -- Rotas primárias dos módulos (RH, Helpdesk, Admin) --
        // Geradas a partir do registro de módulos, cada uma com guarda RBAC.
        // Ver lib/core/modules/module_routes.dart.
        ...buildModuleRoutes(),

        // -- Sub-rotas parametrizadas dos módulos (guardadas pelo mesmo id) --
        GoRoute(
          path: '/rh/candidato/:id',
          redirect: moduleGuard('rh_banco_talentos'),
          builder: (context, state) => CandidateDetailScreen(
            candidatoId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/rh/funcionario/:id',
          redirect: moduleGuard('rh_funcionarios'),
          builder: (context, state) => EmployeeDetailScreen(
            funcionarioId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/admin/moderation',
          redirect: moduleGuard('admin_panel'),
          builder: (context, state) => const ModerationScreen(),
        ),
        GoRoute(
          path: '/admin/reports',
          redirect: moduleGuard('admin_panel'),
          builder: (context, state) => const UsageReportsScreen(),
        ),
        GoRoute(
          path: '/admin/edit',
          redirect: (context, state) {
            // Antes só validava o tipo de `extra`: bastava navegar com um
            // UserModel qualquer para abrir a edição de perfil de terceiro
            // sem ser admin. A guarda de módulo é a mesma das demais telas
            // administrativas.
            if (state.extra == null || state.extra is! UserModel) {
              return '/chats';
            }
            return moduleGuard('admin_panel')(context, state);
          },
          builder: (context, state) {
            final targetUser = state.extra as UserModel;
            return EditProfileScreen(targetUser: targetUser);
          },
        ),
        // -- Console de Plataforma (inserido no painel direito do Desktop) --
        // Não existe rota avulsa /plataforma: o componente
        // PlatformConsoleScreen é renderizado pelo ResponsiveLayout.
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/profile/activity',
          builder: (context, state) => const UserActivityHistoryScreen(),
        ),
        GoRoute(
          path: '/starred',
          builder: (context, state) => const StarredMessagesScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/security-2fa',
          builder: (context, state) => const Security2FAScreen(),
        ),
        GoRoute(
          path: '/trusted-devices',
          builder: (context, state) => const TrustedDevicesScreen(),
        ),
        GoRoute(
          path: '/settings/location',
          builder: (context, state) => const LocationTrackingScreen(),
        ),
        GoRoute(
          path: '/settings/notifications',
          builder: (context, state) => const NotificationSettingsScreen(),
        ),
        GoRoute(
          path: '/settings/changelog',
          builder: (context, state) => const ChangelogScreen(),
        ),
        GoRoute(
          path: '/employees',
          builder: (context, state) => const EmployeeManagementScreen(),
        ),
        GoRoute(
          path: '/support',
          builder: (context, state) => const SupportDashboardScreen(),
        ),
        // '/support/help' (Central de Ajuda) é gerada por buildModuleRoutes()
        // com guarda RBAC do módulo `helpdesk_central`.
        GoRoute(
          path: '/support/new',
          builder: (context, state) => const CreateTicketScreen(),
        ),
        GoRoute(
          path: '/support/ticket/:id',
          builder: (context, state) {
            final ticketId = state.pathParameters['id']!;
            return TicketChatScreen(ticketId: ticketId);
          },
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchScreen(),
        ),
        GoRoute(
          path: '/group/create',
          builder: (context, state) => const NewChatScreen(),
        ),
        GoRoute(
          path: '/channel/create',
          builder: (context, state) => const ChannelCreateScreen(),
        ),
        GoRoute(
          path: '/minha-operacao',
          builder: (context, state) => const MyOperationScreen(),
        ),
        GoRoute(
          path: '/workspace-presets',
          builder: (context, state) => const WorkspacePresetManagerScreen(),
        ),
        GoRoute(
          path: '/channels/discover',
          builder: (context, state) => const ChannelDiscoveryScreen(),
        ),
        GoRoute(
          path: '/channel/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            final extra = state.extra as Map<String, dynamic>? ?? {};
            final name = extra['channelName'] as String? ?? 'Canal Corporativo';

            return WorkflowMainView(channelId: id, channelName: name);
          },
        ),
        GoRoute(
          path: '/channel/:id/thread/:messageId',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            final parentMessage =
                extra?['parentMessage'] as ChannelMessageModel?;

            if (parentMessage == null) {
              return const Scaffold(
                  body:
                      Center(child: Text('Mensagem original não encontrada')));
            }

            return ChannelThreadScreen(
              parentMessage: parentMessage,
              senderName: extra?['senderName'] as String? ?? 'Membro',
            );
          },
        ),
        GoRoute(
          path: '/channel/:id/info',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return ChannelInfoScreen(
                channelId: id,
                channelName: extra['channelName'] as String? ?? 'Canal',
                metadata: extra['metadata'] as Map<String, dynamic>?);
          },
        ),
        GoRoute(
          path: '/channel/:id/edit',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return WorkspaceEditScreen(
              channelId: id,
              channelName: extra['channelName'] as String? ?? 'Workspace',
            );
          },
        ),
        GoRoute(
          path: '/call/:chatId',
          builder: (context, state) {
            final chatId = state.pathParameters['chatId']!;
            final extra = state.extra as Map<String, dynamic>? ?? {};
            final callerName = extra['callerName'] as String? ?? 'Chamada';
            final isVideo = extra['isVideo'] as bool? ?? false;
            return ActiveCallScreen(
              callerName: callerName,
              chatId: chatId,
              isVideo: isVideo,
              isRouted: true,
            );
          },
        ),
        GoRoute(
          path: '/mirotalk/:roomId',
          name: 'mirotalk',
          builder: (context, state) {
            final roomId = state.pathParameters['roomId'] ?? '';
            final extra = state.extra as Map<String, dynamic>?;
            final queryUserName = state.uri.queryParameters['userName'];
            final userName =
                queryUserName ?? (extra?['userName'] as String?) ?? 'Usuário';
            final cleanUserName = userName.trim();
            return MiroTalkScreen(
              roomId: roomId,
              userName: cleanUserName.isNotEmpty ? cleanUserName : 'Usuário',
            );
          },
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text('Página não encontrada: ${state.error}')),
  ),
);

/// Provider do GoRouter — observa o estado de auth para redirecionar.
final routerProvider = Provider<GoRouter>((ref) => goRouter);

