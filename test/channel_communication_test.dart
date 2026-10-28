import 'package:flutter_test/flutter_test.dart';
import 'package:alinha_ja/features/channels/models/channel_message_model.dart';
import 'package:alinha_ja/features/channels/providers/active_channel_provider.dart';
import 'package:alinha_ja/features/channels/ui/widgets/channel_notification_selector.dart';

ChannelMessageModel _msg(
  String id, {
  required String senderId,
  required DateTime createdAt,
}) {
  return ChannelMessageModel(
    id: id,
    channelId: 'ch1',
    senderId: senderId,
    content: 'msg $id',
    createdAt: createdAt,
  );
}

void main() {
  group('ChannelMessageModel — marca de edição', () {
    test('coluna edited_at alimenta o indicador "editado"', () {
      final msg = ChannelMessageModel.fromJson({
        'id': 'm1',
        'channel_id': 'ch1',
        'sender_id': 'u1',
        'content': 'texto',
        'created_at': '2026-08-13T10:00:00Z',
        'edited_at': '2026-08-13T10:05:00Z',
      });

      expect(msg.editedAt, isNotNull);
      expect(msg.isEdited, isTrue);
    });

    test('mensagem antiga com edited_at só no metadata continua marcada', () {
      final legacy = ChannelMessageModel.fromJson({
        'id': 'm2',
        'channel_id': 'ch1',
        'sender_id': 'u1',
        'content': 'texto',
        'created_at': '2026-08-13T10:00:00Z',
        'metadata': {'edited_at': '2026-08-13T10:05:00Z'},
      });

      expect(legacy.editedAt, isNull);
      expect(legacy.isEdited, isTrue,
          reason: 'o indicador não pode sumir para mensagens gravadas antes '
              'de a coluna existir');
    });

    test('mensagem nunca editada não é marcada', () {
      final msg = ChannelMessageModel.fromJson({
        'id': 'm3',
        'channel_id': 'ch1',
        'sender_id': 'u1',
        'content': 'texto',
        'created_at': '2026-08-13T10:00:00Z',
      });

      expect(msg.isEdited, isFalse);
    });
  });

  group('ChannelState — régua de não lidas', () {
    final readAt = DateTime.utc(2026, 8, 13, 10, 0);

    test('aponta a mensagem mais antiga posterior ao last_read_at', () {
      final state = ChannelState(
        currentUserId: 'me',
        lastReadAt: readAt,
        // Ordem decrescente, como o provider carrega.
        messages: [
          _msg('novo2', senderId: 'u1', createdAt: DateTime.utc(2026, 8, 13, 10, 20)),
          _msg('novo1', senderId: 'u1', createdAt: DateTime.utc(2026, 8, 13, 10, 10)),
          _msg('lido', senderId: 'u1', createdAt: DateTime.utc(2026, 8, 13, 9, 50)),
        ],
      );

      expect(state.firstUnreadMessageId, equals('novo1'));
    });

    test('as próprias mensagens não abrem a régua', () {
      final state = ChannelState(
        currentUserId: 'me',
        lastReadAt: readAt,
        messages: [
          _msg('minha', senderId: 'me', createdAt: DateTime.utc(2026, 8, 13, 10, 30)),
          _msg('lido', senderId: 'u1', createdAt: DateTime.utc(2026, 8, 13, 9, 50)),
        ],
      );

      expect(state.firstUnreadMessageId, isNull);
    });

    test('tudo lido não exibe régua', () {
      final state = ChannelState(
        currentUserId: 'me',
        lastReadAt: readAt,
        messages: [
          _msg('a', senderId: 'u1', createdAt: DateTime.utc(2026, 8, 13, 9, 30)),
        ],
      );

      expect(state.firstUnreadMessageId, isNull);
    });

    test('sem last_read_at não inventa régua', () {
      final state = ChannelState(
        currentUserId: 'me',
        messages: [
          _msg('a', senderId: 'u1', createdAt: DateTime.utc(2026, 8, 13, 11, 0)),
        ],
      );

      expect(state.firstUnreadMessageId, isNull);
    });
  });

  group('ChannelState — nível de notificação', () {
    test('padrão é receber tudo', () {
      expect(ChannelState().notificationLevel, equals('all'));
      expect(ChannelState().isMuted, isFalse);
    });

    test('isMuted só vale para o nível none', () {
      expect(ChannelState(notificationLevel: 'none').isMuted, isTrue);
      expect(ChannelState(notificationLevel: 'mentions').isMuted, isFalse);
    });

    test('copyWith preserva o nível quando não informado', () {
      final state = ChannelState(notificationLevel: 'mentions');
      expect(state.copyWith(isLoading: false).notificationLevel,
          equals('mentions'));
    });
  });

  group('ChannelNotificationLevel', () {
    test('resolve conhece os três níveis', () {
      expect(ChannelNotificationLevel.resolve('none').label,
          equals('Silenciado'));
      expect(ChannelNotificationLevel.resolve('mentions').label,
          equals('Somente menções'));
      expect(ChannelNotificationLevel.resolve('all').label,
          equals('Todas as mensagens'));
    });

    test('valor desconhecido ou nulo cai em "todas"', () {
      expect(ChannelNotificationLevel.resolve(null).value, equals('all'));
      expect(ChannelNotificationLevel.resolve('xpto').value, equals('all'));
    });
  });

  group('Menções coletivas', () {
    test('os apelidos aceitos cobrem PT e EN', () {
      const aliases = ActiveChannelNotifier.everyoneMentionAliases;

      expect(aliases, containsAll(<String>['canal', 'aqui', 'todos']));
      expect(aliases, containsAll(<String>['channel', 'here', 'everyone']));
    });

    test('apelidos são comparados em minúsculas', () {
      for (final alias in ActiveChannelNotifier.everyoneMentionAliases) {
        expect(alias, equals(alias.toLowerCase()),
            reason: 'a comparação em _parseMentions normaliza para minúsculas');
      }
    });
  });
}
