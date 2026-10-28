import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardas da vistoria de 2026-09-19: visualização única, encerramento de
/// chamada na web, presença, canais Realtime e relatório de uso.
///
/// Boa parte mora em SQL ou depende do SDK do Agora/Supabase, que não rodam
/// no `flutter test`: os testes prendem no repositório o invariante de cada
/// correção.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Só o código: descarta linhas inteiras de comentário.
  String code(String path) => read(path)
      .split('\n')
      .where((l) => !RegExp(r'^\s*(//|--)').hasMatch(l))
      .join('\n');

  group('Visualização única', () {
    test('a RPC não desfaz o consumo se o Storage recusar o DELETE por SQL', () {
      final sql =
          code('supabase/migrations/20260919100000_view_once_consumo_tolerante.sql');
      final storage = sql.indexOf('DELETE FROM storage.objects');
      final excecao = sql.indexOf('EXCEPTION WHEN OTHERS', storage);
      expect(storage, greaterThan(0));
      expect(excecao, greaterThan(storage),
          reason: 'a remoção do objeto fica numa subtransação própria');
      expect(sql.indexOf('DELETE FROM public.messages'), lessThan(storage));
    });

    test('a foto é consumida ao abrir, com os bytes em memória', () {
      final bubble = code('lib/features/chat/ui/widgets/view_once_bubble.dart');
      expect(bubble, contains('Image.memory(bytes'));
      final consome = bubble.indexOf('unawaited(notifier.openViewOnceMessage');
      final abre = bubble.indexOf('navigator.push(_visualizador(foto))');
      expect(consome, greaterThan(0));
      expect(consome, lessThan(abre));
      // Nada de cache em disco para mídia temporária.
      expect(bubble, isNot(contains('CachedNetworkImage')));
      expect(bubble, isNot(contains('SignedNetworkImage')));
    });

    test('some da tela mesmo se a RPC falhar', () {
      final provider = code('lib/features/chat/providers/chat_provider.dart');
      final inicio = provider.indexOf('Future<void> openViewOnceMessage');
      final remove = provider.indexOf('m.id != messageId', inicio);
      final rpc = provider.indexOf("rpc('mark_view_once_opened'", inicio);
      expect(remove, lessThan(rpc));
    });

    test('remetente recebe a exclusão pelo realtime', () {
      final provider = code('lib/features/chat/providers/chat_provider.dart');
      expect(provider, contains('event: PostgresChangeEvent.delete'));
      expect(provider, contains('_onMessageDelete'));
    });

    test('não vaza pela galeria, encaminhar, fixar nem favoritar', () {
      expect(code('lib/features/chat/providers/chat_info_provider.dart'),
          contains('.where((m) => !m.isViewOnce)'));
      final menu = code('lib/features/chat/ui/widgets/chat_message_list.dart');
      expect('if (!message.isViewOnce)'.allMatches(menu).length, 3);
      final tela = code('lib/features/chat/ui/chat_screen.dart');
      expect('!m.isViewOnce'.allMatches(tela).length, 2);
    });
  });

  group('Encerramento de chamada', () {
    final call = code('lib/core/services/call_service.dart');

    test('para preview e compartilhamento de tela antes de sair', () {
      final leave = call.indexOf('Future<void> leaveChannel()');
      final fim = call.indexOf('Future<void> toggleMute()', leave);
      final corpo = call.substring(leave, fim);
      expect(corpo, contains("_teardownStep('stopPreview'"));
      expect(corpo, contains("_teardownStep('stopScreenCapture'"));
      expect(corpo, contains('wasSharingScreen'));
      // Cada passo com teto: um SDK pendurado não trava os seguintes.
      expect(call, contains('step().timeout(const Duration(seconds: 3))'));
    });

    test('canal de presença é removido, não só desinscrito', () {
      expect(call, isNot(contains('_presenceChannel?.unsubscribe()')));
      expect(call, contains('supabase.removeChannel(channel)'));
      expect(call, contains('identical(_presenceChannel, channel)'));
    });

    test('toque da web só começa com diálogo e sempre para', () {
      final show = call.indexOf('void showWebIncomingCallDialog');
      final ctx = call.indexOf('if (context == null) return;', show);
      final toca = call.indexOf('_webRingtonePlayer = AudioPlayer()', show);
      expect(ctx, greaterThan(show));
      expect(ctx, lessThan(toca));
      expect(call, contains('if (kIsWeb) _stopWebIncomingAlert();'));
    });

    test('"quem fala" não reconstrói a chamada a cada 250 ms', () {
      expect(call, contains('_notifySpeakersChanged()'));
      expect(call, contains('Duration(milliseconds: 300)'));
    });
  });

  group('Presença', () {
    final presence = code('lib/core/providers/presence_service.dart');

    test('perder o foco da janela não é ficar offline', () {
      final ciclo = presence.indexOf('void didChangeAppLifecycleState');
      final fim = presence.indexOf('}', presence.indexOf('_goOffline()', ciclo));
      expect(presence.substring(ciclo, fim),
          isNot(contains('AppLifecycleState.inactive')));
    });

    test('init idempotente: um observer só', () {
      expect(presence, contains('if (!_observing)'));
      expect(presence, contains('!_webListenersRegistered'));
    });
  });

  test('canais Realtime saem do cliente ao descartar', () {
    for (final f in [
      'lib/features/chat/providers/chat_provider.dart',
      'lib/core/services/push_notification_service.dart',
    ]) {
      final s = code(f);
      expect(s, isNot(contains('_typingChannel?.unsubscribe()')), reason: f);
      expect(s, isNot(contains('_joinRequestsChannel?.unsubscribe()')),
          reason: f);
    }
  });

  test('relatório de uso conta no banco, com canais', () {
    final r = code('lib/features/admin/ui/usage_reports_screen.dart');
    expect(r, contains(".from('channels').count()"));
    expect(r, contains(".from('channel_messages').count()"));
    expect(r, isNot(contains('as List).length')));
  });

  test('fn_is_admin volta a STABLE', () {
    expect(code('supabase/migrations/20260919110000_fn_is_admin_stable.sql'),
        contains('ALTER FUNCTION public.fn_is_admin() STABLE'));
  });

  test('toda rota que o app abre existe no router', () {
    final router = read('lib/core/router.dart');
    final modules = read('lib/core/modules/module_registry.dart');
    final declaradas = {
      ...RegExp(r"path:\s*'([^']+)'").allMatches(router).map((m) => m[1]!),
      ...RegExp(r"route:\s*'([^']+)'")
          .allMatches(modules)
          .map((m) => m[1]!.split('?').first),
    }.where((p) => p.startsWith('/'));
    final padroes = [
      for (final p in declaradas)
        RegExp('^${p.replaceAll(RegExp(r':\w+'), '[^/]+')}/?\$'),
    ];

    final nav = RegExp(r"(?:context\.(?:push|go|pushReplacement|replace)|"
        r"goRouter\.(?:go|push)|router\.(?:go|push))\(\s*'([^']+)'");
    final faltando = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final m in nav.allMatches(f.readAsStringSync())) {
        final rota = m[1]!
            .split('?')
            .first
            .replaceAll(RegExp(r'\$\{[^}]+\}|\$\w+'), 'X');
        if (!padroes.any((p) => p.hasMatch(rota))) faltando.add(rota);
      }
    }
    expect(faltando, isEmpty);
  });
}
