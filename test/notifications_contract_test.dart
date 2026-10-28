import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato entre as Edge Functions de push, o app Android e o PWA.
///
/// Cada ponta roda num lugar diferente (Deno, isolate Android, service
/// worker) e nenhuma quebra aparece no `flutter analyze`. Estes testes prendem
/// os pontos em que uma mudança isolada já derrubou notificações.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('send-chat-notification', () {
    final ts = read('supabase/functions/send-chat-notification/index.ts');

    test('manda ao app os campos do layout estilo WhatsApp', () {
      for (final field in [
        'preview:',
        'sender_avatar:',
        'conversation_table:',
        'is_mention:',
        'sender_name:',
        'chat_type:',
      ]) {
        expect(ts, contains(field), reason: field);
      }
    });

    test('web recebe data-only (sem notificação duplicada pelo SDK)', () {
      final web = ts.substring(ts.indexOf("} else if (platform === 'web') {"),
          ts.indexOf('} else {', ts.indexOf("platform === 'web'")));
      expect(web, isNot(contains('notification:')));
      expect(web, isNot(contains('messagePayload.notification')));
      expect(web, contains("Urgency: 'high'"));
    });

    test('só apaga token com UNREGISTERED/404, nunca por INVALID_ARGUMENT',
        () {
      expect(ts, contains('isStaleTokenError(resp.status, respBody)'));
      expect(ts, isNot(contains("errorCode === 'INVALID_ARGUMENT'")));
      final fcm = read('supabase/functions/_shared/fcm.ts');
      expect(fcm, contains("'UNREGISTERED'"));
      expect(
        fcm
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n'),
        isNot(contains('INVALID_ARGUMENT')),
      );
    });
  });

  group('send-call-notification', () {
    final ts = read('supabase/functions/send-call-notification/index.ts');

    test('chamada em canal usa o id do canal, nunca a string "null"', () {
      expect(ts, contains('chat_id: contextId'));
      expect(ts, isNot(contains('chat_id: String(chatId)')));
    });

    test('toque expira em 60 s e a web recebe título e texto', () {
      expect(ts, contains("ttl: '60s'"));
      expect(ts, contains("TTL: '60'"));
      expect(ts, contains('title: isVideo'));
    });
  });

  test('workflow usa o canal com som e informa o canal do card', () {
    final ts = read('supabase/functions/send-workflow-notification/index.ts');
    expect(ts, contains("channel_id: 'alinhaja_workflow_alerts'"));
    expect(ts, contains("chat_type: 'workflow'"));
    final dart = read('lib/core/services/push_notification_service.dart');
    expect(dart, contains("'alinhaja_workflow_alerts'"),
        reason: 'O app precisa criar o canal que o servidor referencia.');
  });

  test('functions chamadas por trigger não exigem JWT no deploy', () {
    final toml = read('supabase/config.toml');
    for (final fn in [
      'send-chat-notification',
      'send-workflow-notification',
      'send-module-notification',
    ]) {
      final start = toml.indexOf('[functions.$fn]');
      expect(start, isNonNegative, reason: fn);
      final end = toml.indexOf('[', start + 1);
      expect(toml.substring(start, end == -1 ? toml.length : end),
          contains('verify_jwt = false'),
          reason: fn);
    }
  });

  test('migration do trigger de push não duplica o existente', () {
    final sql =
        read('supabase/migrations/20260916130000_version_chat_push_triggers.sql');
    expect(sql, contains("p.proname = 'notify_chat_function'"));
    expect(sql, contains("p.prosrc ILIKE '%send-chat-notification%'"));
    expect(sql, contains("encode(t.tgargs, 'escape')"));
    expect(sql, contains('IF v_exists THEN'));
  });

  test('manifest declara o receiver das ações da notificação', () {
    final xml = read('android/app/src/main/AndroidManifest.xml');
    expect(
        xml,
        contains(
            'com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver'));
  });

  group('Service worker (web/PWA)', () {
    final sw = read('web/firebase-messaging-sw.js');

    test('não reexibe mensagem que o SDK já mostrou', () {
      final handler = sw.indexOf('messaging.onBackgroundMessage');
      final guard = sw.indexOf('if (payload.notification) return;');
      final show = sw.indexOf('showNotification', handler);
      expect(guard, greaterThan(handler));
      expect(guard, lessThan(show));
    });

    test('formatador é carregado pelo SW e pela página', () {
      expect(sw, contains('importScripts("notification-format.js")'));
      expect(read('web/index.html'), contains('src="notification-format.js"'));
      final hosting = jsonDecode(read('firebase.json'))['hosting'] as List;
      final app = hosting.cast<Map>().firstWhere((h) => h['target'] == 'app');
      expect(
        (app['headers'] as List).cast<Map>().map((h) => h['source']),
        contains('/notification-format.js'),
        reason: 'Sem no-cache o SW atualizado usaria o formatador antigo.',
      );
    });

    test('formatador: agrupa por conversa, foto, chamadas e rotas', () async {
      final node = await _which('node');
      if (node == null) {
        markTestSkipped('node indisponível');
        return;
      }
      const script = '''
const f = require('./web/notification-format.js');
const a = f.build({title:'Ana', body:'oi', chat_id:'c1', chat_type:'direct',
  sender_avatar:'https://cdn/a.png', chat_name:'Ana'}, 0);
const b = f.build({title:'Ana', body:'tudo?', chat_id:'c1'}, a.options.data.count);
const insecure = f.build({title:'x', chat_id:'c2', sender_avatar:'http://x/a.png'}, 0);
const call = f.build({type:'call', call_id:'k1', chat_id:'null', channel_id:'ch9',
  caller_name:'João', is_video:'false'}, 0);
console.log(JSON.stringify({
  aTitle: a.title, aIcon: a.options.icon, aTag: a.options.tag,
  bTitle: b.title, bCount: b.options.data.count,
  insecureIcon: insecure.options.icon,
  callTitle: call.title, callTag: call.options.tag, callChat: call.options.data.chatId,
  callSticky: call.options.requireInteraction,
  channelPath: f.pathFor('ch9', 'channel'), chatPath: f.pathFor('c1', 'direct'),
  rootPath: f.pathFor('', 'direct'),
  workflowPath: f.pathFor('ch1', 'workflow'),
}));
''';
      final result = await Process.run(node, ['-e', script],
          stdoutEncoding: utf8, stderrEncoding: utf8);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final out = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(out, {
        'aTitle': 'Ana',
        'aIcon': 'https://cdn/a.png',
        'aTag': 'c1',
        'bTitle': 'Ana (2 mensagens)',
        'bCount': 2,
        'insecureIcon': '/icons/Icon-192.png',
        'callTitle': '📞 Chamada de voz',
        'callTag': 'call_k1',
        'callChat': 'ch9',
        'callSticky': true,
        'channelPath': '/#/channel/ch9',
        'chatPath': '/#/chat/c1',
        'rootPath': '/',
        'workflowPath': '/#/channel/ch1',
      });
    });
  });
}

Future<String?> _which(String bin) async {
  try {
    final r = await Process.run(Platform.isWindows ? 'where' : 'which', [bin]);
    if (r.exitCode != 0) return null;
    return (r.stdout as String).split(RegExp(r'\r?\n')).first.trim();
  } catch (_) {
    return null;
  }
}
