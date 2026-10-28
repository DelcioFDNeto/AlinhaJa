import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/core/supabase_client.dart';

/// Encerra a sessão após um período sem interação do usuário.
///
/// ## Por quê
/// A sessão do Supabase se renova sozinha indefinidamente. Num app que roda
/// no navegador de um desktop compartilhado de filial, isso significa que
/// quem senta na máquina depois continua logado como a pessoa anterior —
/// com acesso a conversas, workflow e, para admins, ao painel inteiro.
///
/// ## Desenho
/// Só conta inatividade de fato: qualquer toque, clique, rolagem ou tecla
/// reinicia o relógio.
///
/// **Só vale na web.** No app nativo (APK) fica desligado: o aparelho é
/// pessoal, o logout exigia login + 2FA a cada volta ao app, e o signOut
/// apaga o token FCM (listener de auth em app.dart) — com o timer correndo em
/// segundo plano, o celular parava de receber push.
///
/// Não substitui o 2FA nem a RLS — é defesa contra sessão abandonada, que
/// nenhuma das duas cobre.
class SessionTimeoutService with WidgetsBindingObserver {
  SessionTimeoutService._();
  static final SessionTimeoutService instance = SessionTimeoutService._();

  /// Inatividade tolerada antes do logout automático.
  ///
  /// 30 min é o intervalo usual para ferramenta corporativa: longo o
  /// bastante para uma reunião curta, curto o bastante para uma estação
  /// deixada aberta no fim do expediente.
  static const Duration timeout = Duration(minutes: 30);

  Timer? _timer;
  DateTime? _lastInteraction;
  bool _started = false;

  void start() {
    if (_started || !kIsWeb) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _touch();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _lastInteraction = null;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _started = false;
    }
  }

  /// Registra interação e reinicia a contagem.
  void _touch() {
    _lastInteraction = DateTime.now();
    _timer?.cancel();
    _timer = Timer(timeout, _expire);
  }

  /// Chamado pelo detector de gestos que envolve o app.
  void registerInteraction() {
    if (!_started) return;
    if (supabase.auth.currentSession == null) return;
    _touch();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;

    if (state == AppLifecycleState.resumed) {
      // Ao voltar, decide pelo tempo decorrido: um timer pode ter sido
      // suspenso junto com o app e não teria disparado.
      final last = _lastInteraction;
      if (last != null && DateTime.now().difference(last) >= timeout) {
        _expire();
      } else {
        _touch();
      }
    }
  }

  Future<void> _expire() async {
    _timer?.cancel();
    _timer = null;

    if (supabase.auth.currentSession == null) return;

    try {
      Globals.is2faVerified = false;
      await supabase.auth.signOut();
      Globals.showErrorSnackBar(
        'Sessão encerrada por inatividade. Entre novamente.',
      );
    } catch (e) {
      debugPrint('Falha ao encerrar sessão por inatividade: $e');
    }
  }
}

/// Envolve a árvore de widgets e alimenta o [SessionTimeoutService].
///
/// Usa [Listener] em vez de `GestureDetector` para observar os eventos na
/// fase de captura: assim contamos a interação sem competir com nenhum
/// gesto da UI nem engolir toques.
class SessionActivityDetector extends StatelessWidget {
  final Widget child;

  const SessionActivityDetector({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => SessionTimeoutService.instance.registerInteraction(),
      onPointerSignal: (_) =>
          SessionTimeoutService.instance.registerInteraction(),
      child: child,
    );
  }
}
