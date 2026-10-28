import 'package:flutter/foundation.dart';

import 'web_notification_service_stub.dart'
    if (dart.library.js_interop) 'web_notification_service_web.dart' as impl;

class WebNotificationService {
  static void showWebNotification(String title, String body, {String? tag}) {
    if (kIsWeb) {
      impl.showWebNotification(title, body, tag: tag);
    }
  }

  /// Com o app aberto mas sem foco (outra janela na frente), o FCM entrega
  /// a mensagem à página e não ao service worker. Aqui a página pede ao SW
  /// que exiba a notificação do sistema. Retorna false se a janela está em
  /// foco ou o navegador não suporta — aí vale o toast in-app.
  static bool showPushIfUnfocused(Map<String, dynamic> data) {
    if (!kIsWeb) return false;
    return impl.showPushIfUnfocused(data);
  }

  static void closeWebNotification(String tag) {
    if (kIsWeb) {
      impl.closeWebNotification(tag);
    }
  }
}
