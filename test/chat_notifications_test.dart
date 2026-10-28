import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alinha_ja/core/services/notifications/chat_notification_renderer.dart';
import 'package:alinha_ja/core/services/notifications/notification_actions_gateway.dart';
import 'package:alinha_ja/core/services/notifications/notification_store.dart';
import 'package:alinha_ja/core/services/push_notification_service.dart';

NotificationLine line(String sender, String text,
        {int time = 1, bool me = false}) =>
    NotificationLine(sender: sender, text: text, time: time, fromMe: me);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('NotificationStore', () {
    test('acumula por conversa e limita a 20 linhas', () async {
      for (var i = 0; i < 25; i++) {
        await NotificationStore.append('c1', line('Ana', 'm$i', time: i),
            title: 'Ana', chatType: 'direct', source: 'messages');
      }
      final lines = await NotificationStore.lines('c1');
      expect(lines, hasLength(NotificationStore.maxLinesPerChat));
      expect(lines.first.text, 'm5');
      expect(lines.last.text, 'm24');
      expect(await NotificationStore.title('c1'), 'Ana');
      expect(await NotificationStore.source('c1'), 'messages');
    });

    test('resumo lista da conversa mais recente para a mais antiga', () async {
      await NotificationStore.append('a', line('Ana', 'oi'), title: 'Ana');
      await NotificationStore.append('b', line('Bia', 'olá'), title: 'Vendas');
      await NotificationStore.append('a', line('Ana', 'tudo?'), title: 'Ana');

      final digests = await NotificationStore.digests();
      expect(digests.map((d) => d.chatId), ['a', 'b']);
      expect(summaryText(digests), '3 mensagens de 2 conversas');
      expect(digestLine(digests.first), 'Ana: tudo?');
    });

    test('resposta enviada não conta como não lida', () async {
      await NotificationStore.append('a', line('Ana', 'oi'), title: 'Ana');
      await NotificationStore.append('a', line('Você', 'já vou', me: true));
      final digests = await NotificationStore.digests();
      expect(summaryText(digests), '1 mensagem');
      expect(digestLine(digests.single), 'Ana: Você: já vou');
    });

    test('clear remove a conversa e todas as chaves dela', () async {
      await NotificationStore.append('a', line('Ana', 'oi'),
          title: 'Ana', chatType: 'direct', source: 'messages');
      await NotificationStore.clear('a');
      expect(await NotificationStore.lines('a'), isEmpty);
      expect(await NotificationStore.title('a'), isNull);
      expect(await NotificationStore.source('a'), isNull);
      expect(await NotificationStore.digests(), isEmpty);
    });

    test('cache corrompido não derruba a leitura', () async {
      SharedPreferences.setMockInitialValues({'notif_cache_x': '{quebrado'});
      expect(await NotificationStore.lines('x'), isEmpty);
    });

    test('lê o formato antigo do cache (sender/text/time)', () async {
      SharedPreferences.setMockInitialValues({
        'notif_cache_x': jsonEncode([
          {'sender': 'Ana', 'text': 'oi', 'time': 5}
        ]),
      });
      final l = (await NotificationStore.lines('x')).single;
      expect([l.sender, l.text, l.time, l.fromMe], ['Ana', 'oi', 5, false]);
    });
  });

  group('IncomingChatMessage.fromData', () {
    test('payload novo usa preview, remetente, avatar e tabela', () {
      final m = IncomingChatMessage.fromData({
        'chat_id': 'g1',
        'chat_type': 'group',
        'title': 'Vendas',
        'body': '@ Ana: oi pessoal',
        'preview': 'oi pessoal',
        'sender_name': 'Ana',
        'sender_id': 'u1',
        'sender_avatar': 'https://cdn/a.png',
        'conversation_table': 'messages',
        'is_mention': 'true',
      })!;
      expect(m.senderName, 'Ana');
      expect(m.text, 'oi pessoal');
      expect(m.senderAvatar, 'https://cdn/a.png');
      expect(m.source, 'messages');
      expect(m.mentioned, isTrue);
    });

    test('payload antigo de grupo separa "Nome: texto" e tira o @', () {
      final m = IncomingChatMessage.fromData({
        'chat_id': 'g1',
        'chat_type': 'group',
        'title': 'Vendas',
        'body': '@ Ana: horário: 10h',
      })!;
      expect(m.senderName, 'Ana');
      expect(m.text, 'horário: 10h');
      expect(m.mentioned, isFalse);
    });

    test('DM antiga usa o título como remetente', () {
      final m = IncomingChatMessage.fromData(
          {'chat_id': 'd1', 'title': 'Ana', 'body': 'nota: pago'})!;
      expect(m.chatType, 'direct');
      expect(m.senderName, 'Ana');
      expect(m.text, 'nota: pago');
    });

    test('sem chat_id não há conversa', () {
      expect(IncomingChatMessage.fromData({'title': 'x'}), isNull);
      expect(IncomingChatMessage.fromData({'chat_id': ''}), isNull);
    });
  });

  group('ConversationPayload', () {
    test('ida e volta preserva a tabela de origem', () {
      final p = ConversationPayload.decode(
          const ConversationPayload('c1', 'channel', 'Avisos', 'channel_messages')
              .encode())!;
      expect([p.chatId, p.chatType, p.name, p.source],
          ['c1', 'channel', 'Avisos', 'channel_messages']);
    });

    test('resumo e lixo não viram conversa', () {
      expect(ConversationPayload.decode('summary'), isNull);
      expect(ConversationPayload.decode('não-json'), isNull);
      expect(ConversationPayload.decode(null), isNull);
    });
  });

  test('stableNotificationId é determinístico, positivo e distingue ids', () {
    const id = '2b1c6f0e-8a1d-4a7e-9d41-3f0a7c2e5b11';
    expect(stableNotificationId(id), stableNotificationId(id));
    expect(stableNotificationId(id), isNonNegative);
    expect(stableNotificationId(id), lessThanOrEqualTo(0x7fffffff));
    expect(stableNotificationId('a'), isNot(stableNotificationId('b')));
    // FNV-1a de "a" (0xe40c292c) reduzido a 31 bits: prende o algoritmo, já
    // que o id tem de bater entre versões do app para cancelar notificações.
    expect(stableNotificationId('a'), 0x640c292c);
  });

  test('canal Android por tipo de conversa', () {
    expect(androidChannelFor('direct').id, 'alinhaja_dms');
    expect(androidChannelFor('group').id, 'alinhaja_groups');
    expect(androidChannelFor('channel').id, 'alinhaja_channels');
    expect(androidChannelFor('workflow').id, 'alinhaja_workflow_alerts');
    expect(androidChannelFor('qualquer').id, 'alinhaja_dms');
  });

  test('sourceFor: tabela explícita vence o tipo da conversa', () {
    expect(sourceFor(table: 'messages', chatType: 'channel'),
        ConversationSource.messages);
    expect(sourceFor(table: 'channel_messages'),
        ConversationSource.channelMessages);
    expect(sourceFor(chatType: 'channel'), ConversationSource.channelMessages);
    expect(sourceFor(chatType: 'group'), ConversationSource.messages);
  });

  group('isQuietHoursActive', () {
    TimeOfDay t(int h, int m) => TimeOfDay(hour: h, minute: m);
    test('janela que atravessa a meia-noite', () {
      expect(isQuietHoursActive('22:0', '8:0', t(23, 30)), isTrue);
      expect(isQuietHoursActive('22:0', '8:0', t(7, 59)), isTrue);
      expect(isQuietHoursActive('22:0', '8:0', t(8, 0)), isFalse);
      expect(isQuietHoursActive('22:0', '8:0', t(12, 0)), isFalse);
    });
    test('janela no mesmo dia', () {
      expect(isQuietHoursActive('12:0', '14:0', t(13, 0)), isTrue);
      expect(isQuietHoursActive('12:0', '14:0', t(14, 0)), isFalse);
    });
    test('valor malformado não lança e conta como inativo', () {
      expect(isQuietHoursActive('xx', '8:0', t(3, 0)), isFalse);
      expect(isQuietHoursActive('22', '8:0', t(23, 0)), isFalse);
    });
  });

  group('StoredSession', () {
    Map<String, dynamic> session({int? expiresAt}) => {
          'access_token': 'at',
          'refresh_token': 'rt',
          'expires_at': expiresAt,
          'user': {'id': 'u1'},
        };

    test('mesma chave do supabase_flutter', () {
      expect(StoredSession.storageKey('https://abcxyz.supabase.co'),
          'sb-abcxyz-auth-token');
    });

    test('expira com folga de 60 s', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1000000 * 1000);
      expect(StoredSession(session(expiresAt: 1000000 + 61)).isExpired(now),
          isFalse);
      expect(StoredSession(session(expiresAt: 1000000 + 59)).isExpired(now),
          isTrue);
      expect(StoredSession(session()).isExpired(now), isTrue);
    });

    test('rejeita sessão sem token ou usuário', () {
      expect(StoredSession.parse(jsonEncode({'access_token': 'x'})), isNull);
      expect(StoredSession.parse('lixo'), isNull);
      expect(StoredSession.parse(jsonEncode(session(expiresAt: 1))), isNotNull);
    });
  });

  group('RestSessionGateway', () {
    const url = 'https://abcxyz.supabase.co';
    const key = 'sb-abcxyz-auth-token';
    int nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

    test('responde em DM com a sessão salva, sem renovar', () async {
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({
          'access_token': 'valid',
          'refresh_token': 'rt',
          'expires_at': nowSec() + 3600,
          'user': {'id': 'u1'},
        }),
      });
      final calls = <http.Request>[];
      final gw = RestSessionGateway(
        supabaseUrl: url,
        anonKey: 'anon',
        httpClient: MockClient((req) async {
          calls.add(req);
          return http.Response('', 201);
        }),
      );
      await gw.sendText('chat-1', ConversationSource.messages, 'olá');

      expect(calls, hasLength(1));
      expect(calls.single.url.toString(), '$url/rest/v1/messages');
      expect(calls.single.headers['Authorization'], 'Bearer valid');
      expect(jsonDecode(calls.single.body), {
        'chat_id': 'chat-1',
        'sender_id': 'u1',
        'content': 'olá',
        'content_type': 'text',
      });
    });

    test('sessão expirada: renova, grava a nova e usa o token novo', () async {
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({
          'access_token': 'old',
          'refresh_token': 'rt-old',
          'expires_at': nowSec() - 10,
          'user': {'id': 'u1'},
        }),
      });
      final calls = <http.Request>[];
      final gw = RestSessionGateway(
        supabaseUrl: url,
        anonKey: 'anon',
        httpClient: MockClient((req) async {
          calls.add(req);
          if (req.url.path == '/auth/v1/token') {
            return http.Response(
                jsonEncode({
                  'access_token': 'new',
                  'refresh_token': 'rt-new',
                  'expires_in': 3600,
                  'user': {'id': 'u1'},
                }),
                200);
          }
          return http.Response('', 204);
        }),
      );
      await gw.markRead('canal-1', ConversationSource.channelMessages);

      expect(jsonDecode(calls.first.body), {'refresh_token': 'rt-old'});
      expect(calls.last.url.path, '/rest/v1/channel_members');
      expect(calls.last.url.query, 'channel_id=eq.canal-1&user_id=eq.u1');
      expect(calls.last.headers['Authorization'], 'Bearer new');

      final prefs = await SharedPreferences.getInstance();
      final saved = StoredSession.parse(prefs.getString(key))!;
      expect(saved.accessToken, 'new');
      expect(saved.refreshToken, 'rt-new');
      expect(saved.isExpired(DateTime.now()), isFalse);
    });

    test('marcar DM como lida atualiza membro e chama a RPC', () async {
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({
          'access_token': 'valid',
          'expires_at': nowSec() + 3600,
          'user': {'id': 'u1'},
        }),
      });
      final paths = <String>[];
      final gw = RestSessionGateway(
        supabaseUrl: url,
        anonKey: 'anon',
        httpClient: MockClient((req) async {
          paths.add('${req.method} ${req.url.path}');
          return http.Response('', 204);
        }),
      );
      await gw.markRead('chat-1', ConversationSource.messages);
      expect(paths, [
        'PATCH /rest/v1/chat_members',
        'POST /rest/v1/rpc/mark_messages_as_read',
      ]);
    });

    test('erro HTTP vira exceção (a notificação mostra "Não enviada")',
        () async {
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({
          'access_token': 'valid',
          'expires_at': nowSec() + 3600,
          'user': {'id': 'u1'},
        }),
      });
      final gw = RestSessionGateway(
        supabaseUrl: url,
        anonKey: 'anon',
        httpClient: MockClient((_) async => http.Response('RLS', 403)),
      );
      expect(
          () => gw.sendText('c', ConversationSource.channelMessages, 'x'),
          throwsStateError);
    });

    test('sem sessão salva não tenta a rede', () async {
      var called = false;
      final gw = RestSessionGateway(
        supabaseUrl: url,
        anonKey: 'anon',
        httpClient: MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
      );
      await expectLater(
          gw.sendText('c', ConversationSource.messages, 'x'), throwsStateError);
      expect(called, isFalse);
    });
  });

  testWidgets('avatar: recorte central quadrado em 128 px', (tester) async {
    await tester.runAsync(() async {
      // Imagem 300x150: vermelha na metade esquerda, azul na direita.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 150, 150),
          ui.Paint()..color = const ui.Color(0xFFFF0000));
      canvas.drawRect(const ui.Rect.fromLTWH(150, 0, 150, 150),
          ui.Paint()..color = const ui.Color(0xFF0000FF));
      final img = await recorder.endRecording().toImage(300, 150);
      final png = (await img.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();

      final out = await squareThumbnail(png, 128);
      expect(out, isNotNull);
      final codec = await ui.instantiateImageCodec(out!);
      final frame = await codec.getNextFrame();
      expect([frame.image.width, frame.image.height], [128, 128]);

      final px = (await frame.image.toByteData())!;
      int red(int x) => px.getUint8((64 * 128 + x) * 4);
      int blue(int x) => px.getUint8((64 * 128 + x) * 4 + 2);
      // Recorte central: esquerda vermelha, direita azul.
      expect(red(5), greaterThan(200));
      expect(blue(122), greaterThan(200));
    });
  });
}
