import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'core/router.dart';
import 'core/theme_provider.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/brand/brand_theme.dart';
import 'package:alinha_ja/core/brand/org_identity.dart';
import 'package:alinha_ja/core/config/app_env.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/globals.dart';
import 'package:alinha_ja/core/services/backup_service.dart';
import 'package:alinha_ja/core/services/push_notification_service.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/core/services/session_timeout_service.dart';
import 'package:alinha_ja/core/providers/presence_service.dart';
import 'package:alinha_ja/core/modules/module_access_provider.dart';

/// Widget raiz compartilhado pelas duas marcas (Fluxy e AlinhaJá) e pela build brand-guard:allow
/// do Console de Plataforma. O que muda entre elas vem de [AppEnv], não do
/// entrypoint — por isso o nome é neutro.
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeSettings = ref.watch(themeSettingsProvider);
    // Identidade da empresa (logo e cores): troca o tema sem nova build.
    final identidade =
        ref.watch(orgIdentityProvider).value ?? OrgIdentity.vazia;

    return _PushNotificationInitializer(
      child: MaterialApp.router(
        scaffoldMessengerKey: Globals.scaffoldMessengerKey,
        // Define o título da aba no navegador: sobrescreve, em tempo de
        // execução, o <title> do web/index.html.
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        builder: (context, widget) {
          ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
            debugPrint('========================================');
            debugPrint('FLUTTER ERROR: ${errorDetails.exception}');
            debugPrint('StackTrace: ${errorDetails.stack}');
            debugPrint('========================================');
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'Ops! Algo deu errado.',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        errorDetails.exceptionAsString(),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tente contatar o administrador caso o erro persista.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          };
          // Envolve toda a árvore para alimentar o timeout por inatividade.
          // Fica aqui, no builder do MaterialApp, para cobrir também
          // diálogos e overlays — que ficam acima do Navigator.
          final app = SessionActivityDetector(child: widget!);

          if (AppEnv.isDev) {
            return Banner(
              message: 'DEV',
              location: BannerLocation.topEnd,
              color: const Color(0xFFF57C00),
              child: app,
            );
          }
          return app;
        },
        routerConfig: router,
        themeMode: themeSettings.mode,
        theme: BrandTheme.claro(themeSettings.scheme, identidade),
        darkTheme: BrandTheme.escuro(themeSettings.scheme, identidade),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('pt', 'BR'),
        ],
      ),
    );
  }
}

/// Widget invisível que inicializa o PushNotificationService dentro do
/// contexto Riverpod, garantindo que o Ref seja injetado corretamente.
class _PushNotificationInitializer extends ConsumerStatefulWidget {
  final Widget child;
  const _PushNotificationInitializer({required this.child});

  @override
  ConsumerState<_PushNotificationInitializer> createState() =>
      _PushNotificationInitializerState();
}

class _PushNotificationInitializerState
    extends ConsumerState<_PushNotificationInitializer> {
  StreamSubscription<AuthState>? _authSub;
  Timer? _updateTimer;
  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _checkForUpdates();
      _updateTimer = Timer.periodic(
          const Duration(minutes: 10), (_) => _checkForUpdates());
    }
    // Escuta mudanças de auth e inicializa/limpa o token FCM.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;

      if (event == AuthChangeEvent.passwordRecovery) {
        debugPrint('App: Evento de recuperação de senha detectado');
        Future.microtask(() => goRouter.go('/update-password'));
        return;
      }

      // Build de admin (Console de Plataforma): sem serviços de tenant
      // (FCM/presença/chamadas). Só o fluxo de auth importa.
      if (AppEnv.isPlatformAdminBuild) return;

      final pushService = ref.read(pushNotificationServiceProvider);

      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession) {
        if (data.session != null) {
          debugPrint('App: Evento de login detectado, inicializando serviços');
          pushService.initialize();
          // Marcar como online ao fazer login
          try {
            ref.read(presenceServiceProvider).init();
            debugPrint('App: PresenceService inicializado');
          } catch (e) {
            debugPrint('App: Erro ao inicializar PresenceService: $e');
          }
          // Passa a contar inatividade só a partir do login.
          SessionTimeoutService.instance.start();

          // Troca de conta no mesmo aparelho: descarta o espelho local de
          // quem usou antes. A leitura já filtra por dono, mas manter o
          // dado de terceiro em disco não tem finalidade — e é justamente
          // o que a exportação antiga acabava levando junto.
          BackupService.purgarEspelhoLocal(
            manterTitular: data.session!.user.id,
          );
        }
      } else if (event == AuthChangeEvent.signedOut) {
        debugPrint('App: Evento de logout detectado');
        pushService.deleteToken();

        // Rede de segurança da limpeza local: `AuthRepository.signOut` já
        // purga antes de encerrar a sessão, mas há saídas que não passam
        // por ele — expiração por inatividade, conta desativada na splash,
        // 2FA abandonado. Todas desembocam aqui.
        BackupService.limparDadosDoDispositivo();

        // -- Prevenão de Memory Leaks & Limpeza de Sockets Supabase Globais --
        try {
          ref.read(presenceServiceProvider).dispose();
          CallService.instance.dispose();
          SessionTimeoutService.instance.stop();
        } catch (_) {}
      }
    });
  }

  Future<void> _checkForUpdates() async {
    if (kIsWeb && !_updateAvailable) {
      try {
        final response = await http.get(Uri.parse(
            'version.json?t=${DateTime.now().millisecondsSinceEpoch}'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final serverVersion = data['version'] as String?;
          const currentVersion = AppConstants.appVersion;
          if (serverVersion != null && serverVersion != currentVersion) {
            setState(() => _updateAvailable = true);
            debugPrint('App: Nova versão disponível: $serverVersion');
            _showUpdateBanner();
            _updateTimer?.cancel();
          }
        }
      } catch (_) {}
    }
  }

  void _showUpdateBanner() {
    Globals.scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text(
            'Nova versão do aplicativo disponível! Recarregue a página.'),
        duration: const Duration(days: 365), // Mantém fixo na tela
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.corMarca,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            // Apenas esconde, usuário precisa dar F5.
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-sincroniza as inscrições em tópicos FCM por módulo sempre que o
    // conjunto de módulos acessíveis do usuário muda (login, troca de perfil
    // RBAC, etc.). O provider também mantém Globals.accessibleModuleIds.
    // Ignorado na build de admin (sem FCM/módulos de tenant).
    if (!AppEnv.isPlatformAdminBuild) {
      ref.listen(accessibleModulesProvider, (previous, next) {
        final ids = next.map((m) => m.id).toSet();
        try {
          ref.read(pushNotificationServiceProvider).syncModuleTopicSubscriptions(ids);
        } catch (e) {
          debugPrint('App: erro ao sincronizar tópicos de módulo: $e');
        }
      });
    }
    return widget.child;
  }
}

