import 'package:flutter_test/flutter_test.dart';
import 'package:alinha_ja/features/chats/providers/call_history_provider.dart';

void main() {
  group('CallHistoryEntry Logic Tests â€”', () {
    test('isGroupOrChannel should be true for group chats', () {
      final entryGroup = CallHistoryEntry(
        id: 'call_1',
        contextId: 'chat_1',
        callerId: 'user_1',
        status: 'ended',
        type: 'audio',
        createdAt: DateTime.now(),
        chatType: 'group',
      );

      final entryDirect = CallHistoryEntry(
        id: 'call_3',
        contextId: 'chat_3',
        callerId: 'user_1',
        status: 'ended',
        type: 'audio',
        createdAt: DateTime.now(),
        chatType: 'direct',
      );

      expect(entryGroup.isGroupOrChannel, true);
      expect(entryDirect.isGroupOrChannel, false);
    });

    test('isGroupOrChannel should be true for channel meetings', () {
      final entryChannel = CallHistoryEntry(
        id: 'call_2',
        contextId: 'channel_1',
        callerId: 'user_1',
        status: 'ended',
        type: 'video',
        createdAt: DateTime.now(),
        chatType: 'operacional',
        isChannelMeeting: true,
      );

      expect(entryChannel.isGroupOrChannel, true);
      expect(entryChannel.isChannel, true);
    });

    test('duration computes correctly when startedAt and endedAt are present',
        () {
      final now = DateTime.now();
      final startedAt = now.subtract(const Duration(minutes: 5, seconds: 30));

      final entry = CallHistoryEntry(
        id: 'call_4',
        contextId: 'chat_1',
        callerId: 'user_1',
        status: 'ended',
        type: 'audio',
        createdAt: now,
        startedAt: startedAt,
        endedAt: now,
      );

      expect(entry.duration, isNotNull);
      expect(entry.duration!.inMinutes, 5);
      expect(entry.duration!.inSeconds, 330);
    });

    test('duration is null when startedAt or endedAt are missing', () {
      final entryNoEnded = CallHistoryEntry(
        id: 'call_5',
        contextId: 'chat_1',
        callerId: 'user_1',
        status: 'ended',
        type: 'audio',
        createdAt: DateTime.now(),
        startedAt: DateTime.now(),
      );

      final entryNoDates = CallHistoryEntry(
        id: 'call_6',
        contextId: 'chat_1',
        callerId: 'user_1',
        status: 'ended',
        type: 'audio',
        createdAt: DateTime.now(),
      );

      expect(entryNoEnded.duration, isNull);
      expect(entryNoDates.duration, isNull);
    });

    test('hasRecording is true only if audioUrl is present and not empty', () {
      final entryWithAudio = CallHistoryEntry(
        id: 'call_7',
        contextId: 'chat_1',
        callerId: 'user_1',
        status: 'ended',
        type: 'audio',
        createdAt: DateTime.now(),
        audioUrl: 'https://example.com/audio.mp3',
      );

      final entryEmptyAudio = CallHistoryEntry(
        id: 'call_8',
        contextId: 'chat_1',
        callerId: 'user_1',
        status: 'ended',
        type: 'audio',
        createdAt: DateTime.now(),
        audioUrl: '',
      );

      final entryNoAudio = CallHistoryEntry(
        id: 'call_9',
        contextId: 'chat_1',
        callerId: 'user_1',
        status: 'ended',
        type: 'audio',
        createdAt: DateTime.now(),
      );

      expect(entryWithAudio.hasRecording, true);
      expect(entryEmptyAudio.hasRecording, false);
      expect(entryNoAudio.hasRecording, false);
    });

    test('chatId getter returns contextId for backwards compatibility', () {
      final entry = CallHistoryEntry(
        id: 'call_0',
        contextId: 'chat_x',
        callerId: '',
        status: 'ended',
        type: 'audio',
        createdAt: DateTime.now(),
      );

      expect(entry.chatId, 'chat_x');
      expect(entry.callerId, '');
      expect(entry.status, 'ended');
      expect(entry.chatName, isNull);
      expect(entry.callerName, isNull);
      expect(entry.startedAt, isNull);
    });
  });
}
