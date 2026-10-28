import 'package:flutter_test/flutter_test.dart';
import 'package:alinha_ja/features/chats/models/chat_model.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/support/models/support_ticket_model.dart';

void main() {
  group('Model Serialization Tests â€”', () {
    group('ChatModel', () {
      test('should parse correctly from valid JSON', () {
        final json = {
          'id': 'chat_123',
          'type': 'group',
          'name': 'Dev Team',
          'created_at': '2026-04-10T12:00:00Z',
          'is_pinned': true,
        };

        final model = ChatModel.fromJson(json);

        expect(model.id, 'chat_123');
        expect(model.type, ChatType.group);
        expect(model.name, 'Dev Team');
        expect(model.isPinned, true);
        expect(model.createdAt.year, 2026);
      });

      test('should throw FormatException if id is missing or empty', () {
        final jsonMissingId = {
          'type': 'direct',
        };
        final jsonEmptyId = {
          'id': '',
        };

        expect(() => ChatModel.fromJson(jsonMissingId), throwsFormatException);
        expect(() => ChatModel.fromJson(jsonEmptyId), throwsFormatException);
      });
    });

    group('MessageModel', () {
      test('should parse correctly from basic JSON', () {
        final json = {
          'id': 'msg_001',
          'chat_id': 'chat_123',
          'sender_id': 'user_abc',
          'content': 'Hello world',
          'status': 'read',
          'content_type': 'text',
          'created_at': '2026-04-10T12:05:00Z',
        };

        final model = MessageModel.fromJson(json);

        expect(model.id, 'msg_001');
        expect(model.chatId, 'chat_123');
        expect(model.senderId, 'user_abc');
        expect(model.content, 'Hello world');
        expect(model.status, MessageStatus.read);
        expect(model.contentType, ContentType.text);
      });

      test('should throw FormatException if required fields are missing', () {
        final json = {
          'chat_id': 'chat_123',
          'sender_id': 'user_abc',
          // missing 'id'
        };

        expect(() => MessageModel.fromJson(json), throwsFormatException);
      });

      test('should handle multimedia content correctly', () {
        final json = {
          'id': 'msg_002',
          'chat_id': 'chat_123',
          'sender_id': 'user_abc',
          'content_type': 'image',
          'media_url': 'https://example.com/image.png',
          'created_at': '2026-04-10T12:10:00Z',
        };

        final model = MessageModel.fromJson(json);

        expect(model.contentType, ContentType.image);
        expect(model.mediaUrl, 'https://example.com/image.png');
      });
    });

    group('SupportTicketModel', () {
      test('should parse correctly from valid JSON', () {
        final json = {
          'id': 'ticket_999',
          'creator_id': 'user_abc',
          'title': 'App Crashes on login',
          'description': 'Description here',
          'category': 'bug',
          'priority': 'high',
          'status': 'open',
          'created_at': '2026-04-10T14:00:00Z',
          'updated_at': '2026-04-10T14:00:00Z',
        };

        final model = SupportTicketModel.fromJson(json);

        expect(model.id, 'ticket_999');
        expect(model.title, 'App Crashes on login');
        expect(model.status, 'open');
        expect(model.priority, 'high');
      });
    });
  });
}
