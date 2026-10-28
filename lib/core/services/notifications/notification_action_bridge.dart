import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/services/notifications/notification_actions_gateway.dart';

/// Ponte entre o isolate das ações e o isolate principal do app.
class NotificationActionBridge {
  NotificationActionBridge._();

  static const _portName = 'alinhaja_notification_actions';
  static ReceivePort? _port;
  static SupabaseClient? _client;

  /// Chamado pelo app no isolate principal (Android).
  static void registerMain(SupabaseClient client) {
    _client = client;
    _port?.close();
    ui.IsolateNameServer.removePortNameMapping(_portName);
    final port = ReceivePort();
    _port = port;
    ui.IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    port.listen((message) async {
      if (message is! Map) return;
      final reply = message['reply'];
      if (reply is! SendPort) return;
      if (message['op'] == 'ping') {
        reply.send('pong');
        return;
      }
      reply.send(await _run(
        SupabaseClientGateway(client),
        message['op'] as String? ?? '',
        message['chatId'] as String? ?? '',
        ConversationSource.values[message['source'] as int? ?? 0],
        message['text'] as String?,
      ));
    });
  }

  static Future<bool> perform(
      String op, String chatId, ConversationSource source, String? text) async {
    final local = _client;
    if (local != null) {
      return _run(SupabaseClientGateway(local), op, chatId, source, text);
    }

    final main = ui.IsolateNameServer.lookupPortByName(_portName);
    if (main != null) {
      final pong = await _ask(main, {'op': 'ping'}, const Duration(seconds: 2));
      if (pong == 'pong') {
        // App vivo: ele executa com a própria sessão. Timeout aqui conta como
        // falha — renovar a sessão em paralelo derrubaria o login.
        final result = await _ask(
          main,
          {
            'op': op,
            'chatId': chatId,
            'source': source.index,
            if (text != null) 'text': text,
          },
          const Duration(seconds: 20),
        );
        return result == true;
      }
    }

    final gateway = await _restGateway();
    if (gateway == null) return false;
    return _run(gateway, op, chatId, source, text);
  }

  static Future<bool> _run(ConversationGateway gateway, String op,
      String chatId, ConversationSource source, String? text) async {
    try {
      if (op == kReplyActionId) {
        if (text == null || text.isEmpty) return false;
        await gateway.sendText(chatId, source, text);
      } else if (op == kMarkReadActionId) {
        await gateway.markRead(chatId, source);
      } else {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[Notif] Ação "$op" falhou: $e');
      return false;
    }
  }

  static Future<Object?> _ask(
      SendPort target, Map<String, Object?> message, Duration timeout) async {
    final port = ReceivePort();
    try {
      target.send({...message, 'reply': port.sendPort});
      return await port.first.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      port.close();
    }
  }

  static Future<RestSessionGateway?> _restGateway() async {
    var url = AppEnv.supabaseUrl;
    var key = AppEnv.supabaseAnonKey;
    if (url.isEmpty || key.isEmpty) {
      try {
        await dotenv.load(fileName: '.env');
        url = AppEnv.supabaseUrl;
        key = AppEnv.supabaseAnonKey;
      } catch (_) {}
    }
    if (url.isEmpty || key.isEmpty) return null;
    return RestSessionGateway(supabaseUrl: url, anonKey: key);
  }
}
