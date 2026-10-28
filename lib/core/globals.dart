import 'package:flutter/material.dart';

/// Chaves globais acessíveis em qualquer parte do app sem BuildContext.
class Globals {
  Globals._();

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Chave global do Navigator para roteamento via push notifications.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// ID do chat atualmente aberto pelo usuário (null = nenhum chat aberto).
  /// Usado para suprimir notificações quando o usuário já está na conversa.
  static String? currentOpenChatId;

  /// Role do usuário logado para verificações síncronas no router redirect.
  /// Atualizado por [currentUserProvider] via app.dart.
  static String? currentUserRoleLevel;

  /// Espelho síncrono de `users.is_platform_owner` para a guarda de rota do
  /// Console de Plataforma (o redirect do GoRouter é síncrono). Atualizado por
  /// [currentUserProvider]. Tri-estado: `null` = ainda não resolvido (cold
  /// start; a guarda é permissiva e a tela revalida), `false` = não é dono,
  /// `true` = dono da aplicação.
  static bool? currentUserIsPlatformOwner;

  /// IDs dos módulos que o usuário logado pode ver (chaves RBAC, ex.:
  /// `rh_alertas`). Espelho síncrono de `accessibleModulesProvider`, usado
  /// pelas guardas de rota do GoRouter (o redirect é síncrono e não consegue
  /// aguardar um FutureProvider).
  ///
  /// `null` = ainda não resolvido (cold start). As guardas tratam esse estado
  /// de forma permissiva-para-logado para evitar flicker de bloqueio, e a UI
  /// revalida quando o provider resolve.
  static Set<String>? accessibleModuleIds;

  /// Indica se a sessão atual já cumpriu o 2FA (dispositivo confiável,
  /// super_admin isento ou código validado). Usado pelo router redirect
  /// para bloquear rotas protegidas de forma síncrona.
  ///
  /// É intencionalmente em memória: reinicia como `false` a cada carga do
  /// app, forçando a reavaliação de confiança do dispositivo no splash/verify.
  static bool is2faVerified = false;

  /// Exibe um SnackBar de erro globalmente sem precisar do BuildContext explícito.
  static void showErrorSnackBar(String message) {
    if (scaffoldMessengerKey.currentState != null) {
      scaffoldMessengerKey.currentState!.showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Exibe um SnackBar de sucesso/aviso globalmente sem precisar do BuildContext explícito.
  static void showSuccessSnackBar(String message) {
    if (scaffoldMessengerKey.currentState != null) {
      scaffoldMessengerKey.currentState!.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
