import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/core/services/session_timeout_service.dart';

/// O logout por inatividade só vale na web (desktops compartilhados). No APK
/// ele deslogava o aparelho — inclusive em segundo plano, onde o timer seguia
/// correndo — e o signOut apagava o token FCM: o celular parava de receber
/// notificações.
///
/// Os testes rodam na VM (não web). O Supabase não é inicializado de
/// propósito: se o serviço tentar encerrar a sessão, acessa o cliente e o
/// teste falha.
void main() {
  testWidgets('app nativo não encerra a sessão em segundo plano',
      (tester) async {
    final service = SessionTimeoutService.instance;
    addTearDown(service.stop);

    service.start();
    service.didChangeAppLifecycleState(AppLifecycleState.hidden);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);

    await tester.pump(SessionTimeoutService.timeout * 2);
  });

  testWidgets('app nativo não encerra a sessão ao voltar depois do prazo',
      (tester) async {
    final service = SessionTimeoutService.instance;
    addTearDown(service.stop);

    service.start();
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(SessionTimeoutService.timeout * 2);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    service.registerInteraction();
    await tester.pump();
  });
}
