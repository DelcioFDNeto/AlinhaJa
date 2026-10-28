import 'package:flutter_test/flutter_test.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/chat/providers/chat_provider.dart';

void main() {
  group('ChatState', () {
    test('should have default values', () {
      const state = ChatState();

      expect(state.messages, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.latestReadByOthers, isNull);
      expect(state.error, isNull);
      expect(state.typingUsers, isEmpty);
      expect(state.reactions, isEmpty);
      expect(state.pinnedMessage, isNull);
    });

    test('copyWith should create new state with updated values', () {
      const state = ChatState();
      final newState = state.copyWith(isLoading: true, hasMore: false);

      expect(newState.isLoading, isTrue);
      expect(newState.hasMore, isFalse);
      expect(state.isLoading, isFalse);
    });

    test('copyWith with clearPin should remove pinned message', () {
      final msg = MessageModel(
        id: 'msg-1',
        chatId: 'chat-1',
        senderId: 'user-1',
        createdAt: DateTime.now(),
      );
      final state = ChatState(pinnedMessage: msg);
      final newState = state.copyWith(clearPin: true);

      expect(newState.pinnedMessage, isNull);
    });
  });

  group('ChatArgs', () {
    test('should correctly compare equal args', () {
      const args1 = ChatArgs(chatId: 'chat-123');
      const args2 = ChatArgs(chatId: 'chat-123');

      expect(args1, equals(args2));
      expect(args1.hashCode, equals(args2.hashCode));
    });

    test('should differentiate args with different threadId', () {
      const args1 = ChatArgs(chatId: 'chat-123', threadId: 'thread-1');
      const args2 = ChatArgs(chatId: 'chat-123', threadId: 'thread-2');

      expect(args1, isNot(equals(args2)));
    });

    test('should differentiate args with and without threadId', () {
      const args1 = ChatArgs(chatId: 'chat-123');
      const args2 = ChatArgs(chatId: 'chat-123', threadId: 'thread-1');

      expect(args1, isNot(equals(args2)));
    });
  });

  group('MessageModel', () {
    test('isEdited should return true when editedAt is set', () {
      final msg = MessageModel(
        id: 'msg-1',
        chatId: 'chat-1',
        senderId: 'user-1',
        createdAt: DateTime.now(),
        editedAt: DateTime.now(),
      );

      expect(msg.isEdited, isTrue);
    });

    test('isEdited should return false when editedAt is null', () {
      final msg = MessageModel(
        id: 'msg-1',
        chatId: 'chat-1',
        senderId: 'user-1',
        createdAt: DateTime.now(),
      );

      expect(msg.isEdited, isFalse);
    });

    test('isOptimistic should return true when status is sending', () {
      final msg = MessageModel(
        id: 'msg-1',
        chatId: 'chat-1',
        senderId: 'user-1',
        createdAt: DateTime.now(),
        status: MessageStatus.sending,
      );

      expect(msg.isOptimistic, isTrue);
    });

    test('contentTypeString should return correct string', () {
      final msg = MessageModel(
        id: 'msg-1',
        chatId: 'chat-1',
        senderId: 'user-1',
        createdAt: DateTime.now(),
        contentType: ContentType.image,
      );

      expect(msg.contentTypeString, equals('image'));
    });
  });

  // O realtime da conversa passou de `stream()` (lista inteira a cada evento)
  // para eventos de linha. Estes testes fixam a mescla que substituiu a
  // antiga "detecção de exclusão" do stream.
  group('mergeMessageLists', () {
    MessageModel msg(String id, int minute,
            {String sender = 'other', String? content}) =>
        MessageModel(
          id: id,
          chatId: 'chat-1',
          senderId: sender,
          content: content,
          createdAt: DateTime.utc(2026, 9, 18, 10, minute),
        );

    test('mensagem nova entra no topo e preserva as páginas antigas', () {
      final current = [msg('b', 2), msg('a', 1)];

      final merge =
          mergeMessageLists(current, [msg('c', 3)], currentUserId: 'me');

      expect(merge.messages.map((m) => m.id), ['c', 'b', 'a']);
      expect(merge.newFromOthers, isTrue);
    });

    test('alteração substitui no lugar, sem duplicar', () {
      final current = [msg('b', 2), msg('a', 1, content: 'antes')];

      final merge = mergeMessageLists(
          current, [msg('a', 1, content: 'editada')],
          currentUserId: 'me');

      expect(merge.messages.map((m) => m.id), ['b', 'a']);
      expect(merge.messages.last.content, 'editada');
      expect(merge.newFromOthers, isFalse);
    });

    test('mensagem minha não marca a conversa como lida', () {
      final merge = mergeMessageLists([], [msg('x', 1, sender: 'me')],
          currentUserId: 'me');

      expect(merge.newFromOthers, isFalse);
    });

    test('ids repetidos no mesmo lote entram uma vez só', () {
      final merge = mergeMessageLists([], [msg('x', 1), msg('x', 1)],
          currentUserId: 'me');

      expect(merge.messages, hasLength(1));
    });

    test('respeita o teto mantendo as mais recentes', () {
      final current = [for (var i = 3; i >= 1; i--) msg('m$i', i)];

      final merge = mergeMessageLists(current, [msg('m4', 4)],
          currentUserId: 'me', cap: 3);

      expect(merge.messages.map((m) => m.id), ['m4', 'm3', 'm2']);
    });
  });

  group('replaceOptimisticMessage', () {
    final optimistic = MessageModel(
      id: 'temp',
      chatId: 'chat-1',
      senderId: 'me',
      status: MessageStatus.sending,
      createdAt: DateTime.utc(2026, 9, 18, 10, 5),
    );
    final real = MessageModel(
      id: 'real',
      chatId: 'chat-1',
      senderId: 'me',
      createdAt: DateTime.utc(2026, 9, 18, 10, 5),
    );

    test('troca a otimista pela real', () {
      final result = replaceOptimisticMessage([optimistic], 'temp', real);

      expect(result.map((m) => m.id), ['real']);
    });

    test('realtime chegou antes do insert: não duplica', () {
      final result =
          replaceOptimisticMessage([real, optimistic], 'temp', real);

      expect(result.map((m) => m.id), ['real']);
    });
  });
}
