import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';

class CallHistoryEntry {
  final String id;
  final String contextId; // chat_id ou channel_id
  final String callerId;
  final String status;
  final String type;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? audioUrl;

  // Joins
  final String? chatName;
  final String? chatType;
  final String? callerName;
  final String? callerAvatarUrl;
  final String? partnerName;
  final String? partnerAvatarUrl;
  final bool isChannelMeeting;

  const CallHistoryEntry({
    required this.id,
    required this.contextId,
    required this.callerId,
    required this.status,
    required this.type,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    this.audioUrl,
    this.chatName,
    this.chatType,
    this.callerName,
    this.callerAvatarUrl,
    this.partnerName,
    this.partnerAvatarUrl,
    this.isChannelMeeting = false,
  });

  // Mantém compatibilidade com código que usa chatId
  String get chatId => contextId;

  bool get isGroup => chatType == 'group';
  bool get isChannel => isChannelMeeting;
  bool get isGroupOrChannel => isGroup || isChannel;

  Duration? get duration {
    if (startedAt != null && endedAt != null) {
      return endedAt!.difference(startedAt!);
    }
    return null;
  }

  bool get hasRecording => audioUrl != null && audioUrl!.isNotEmpty;
}

final callHistoryProvider =
    FutureProvider.autoDispose<List<CallHistoryEntry>>((ref) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return [];

  // Buscar IDs de chats do usuário
  final membersResp =
      await supabase.from('chat_members').select('chat_id').eq('user_id', myId);
  final myChats =
      (membersResp as List).map((row) => row['chat_id'] as String).toList();

  // Buscar IDs de canais do usuário
  final channelMembersResp = await supabase
      .from('channel_members')
      .select('channel_id')
      .eq('user_id', myId);
  final myChannels = (channelMembersResp as List)
      .map((row) => row['channel_id'] as String)
      .toList();

  if (myChats.isEmpty && myChannels.isEmpty) return [];

  final List<CallHistoryEntry> entries = [];
  final Map<String, Map<String, dynamic>> dmPartners = {};

  if (myChats.isNotEmpty) {
    try {
      final partnersRes = await supabase
          .from('chat_members')
          .select('chat_id, users(full_name, avatar_url)')
          .inFilter('chat_id', myChats)
          .neq('user_id', myId);
      for (final p in (partnersRes as List)) {
        final chatId = p['chat_id'] as String;
        final user = p['users'] as Map<String, dynamic>?;
        if (user != null) {
          dmPartners[chatId] = user;
        }
      }
    } catch (e) {
      // ignore: empty_catches
    }
  }

  // ─── Chamadas de ÁUDIO (tabela calls) ──────────────────────
  if (myChats.isNotEmpty) {
    try {
      final callsResponse = await supabase
          .from('calls')
          .select('''
            id, chat_id, channel_id, caller_id, status, type, created_at, started_at, ended_at, audio_url,
            chats (name, type),
            caller:users!calls_caller_id_fkey (full_name, avatar_url)
          ''')
          .inFilter('chat_id', myChats)
          .order('created_at', ascending: false)
          .limit(50);

      for (final row in (callsResponse as List)) {
        try {
          final callerMap = row['caller'] as Map<String, dynamic>?;
          final chatMap = row['chats'] as Map<String, dynamic>?;
          final chatId = row['chat_id'] as String? ?? '';
          final partner = dmPartners[chatId];
          entries.add(CallHistoryEntry(
            id: row['id'] as String,
            contextId: chatId,
            callerId: row['caller_id'] as String? ?? '',
            status: row['status'] as String? ?? 'ended',
            type: 'audio',
            createdAt: DateTime.parse(row['created_at'] as String? ??
                row['started_at'] as String? ??
                DateTime.now().toIso8601String()),
            startedAt: row['started_at'] != null
                ? DateTime.parse(row['started_at'] as String)
                : null,
            endedAt: row['ended_at'] != null
                ? DateTime.parse(row['ended_at'] as String)
                : null,
            audioUrl: row['audio_url'] as String?,
            chatName: chatMap?['name'] as String?,
            chatType: chatMap?['type'] as String?,
            callerName: callerMap?['full_name'] as String?,
            callerAvatarUrl: callerMap?['avatar_url'] as String?,
            partnerName: partner?['full_name'] as String?,
            partnerAvatarUrl: partner?['avatar_url'] as String?,
            isChannelMeeting: false,
          ));
        } catch (e) {
          // ignore parse errors for a single row
        }
      }
    } catch (e) {
      // ignore query errors
    }
  }

  // ─── Chamadas de ÁUDIO em canais (tabela calls com channel_id) ─
  if (myChannels.isNotEmpty) {
    try {
      final channelCallsResponse = await supabase
          .from('calls')
          .select('''
            id, chat_id, channel_id, caller_id, status, type, created_at, started_at, ended_at, audio_url,
            channels (name, type),
            caller:users!calls_caller_id_fkey (full_name, avatar_url)
          ''')
          .inFilter('channel_id', myChannels)
          .order('created_at', ascending: false)
          .limit(50);

      for (final row in (channelCallsResponse as List)) {
        try {
          final callerMap = row['caller'] as Map<String, dynamic>?;
          final channelMap = row['channels'] as Map<String, dynamic>?;
          entries.add(CallHistoryEntry(
            id: row['id'] as String,
            contextId: row['channel_id'] as String? ?? '',
            callerId: row['caller_id'] as String? ?? '',
            status: row['status'] as String? ?? 'ended',
            type: 'audio',
            createdAt: DateTime.parse(row['created_at'] as String? ??
                row['started_at'] as String? ??
                DateTime.now().toIso8601String()),
            startedAt: row['started_at'] != null
                ? DateTime.parse(row['started_at'] as String)
                : null,
            endedAt: row['ended_at'] != null
                ? DateTime.parse(row['ended_at'] as String)
                : null,
            audioUrl: row['audio_url'] as String?,
            chatName: channelMap?['name'] as String?,
            chatType: channelMap?['type'] as String?,
            callerName: callerMap?['full_name'] as String?,
            callerAvatarUrl: callerMap?['avatar_url'] as String?,
            isChannelMeeting: true,
          ));
        } catch (e) {
          // ignore parse errors for a single row
        }
      }
    } catch (e) {
      // ignore query errors
    }
  }

  // ─── Reuniões de VÍDEO em chats (tabela meetings) ──────────
  if (myChats.isNotEmpty) {
    try {
      final meetingsResponse = await supabase
          .from('meetings')
          .select('''
            id, chat_id, channel_id, host_id, status, created_at, started_at, ended_at, audio_url,
            chats (name, type),
            host:users!meetings_host_id_fkey (full_name, avatar_url)
          ''')
          .inFilter('chat_id', myChats)
          .order('created_at', ascending: false)
          .limit(50);

      for (final row in (meetingsResponse as List)) {
        try {
          final hostMap = row['host'] as Map<String, dynamic>?;
          final chatMap = row['chats'] as Map<String, dynamic>?;
          entries.add(CallHistoryEntry(
            id: row['id'] as String,
            contextId: row['chat_id'] as String? ?? '',
            callerId: row['host_id'] as String? ?? '',
            status: row['status'] as String? ?? 'ended',
            type: 'video',
            createdAt: DateTime.parse(row['created_at'] as String? ??
                row['started_at'] as String? ??
                DateTime.now().toIso8601String()),
            startedAt: row['started_at'] != null
                ? DateTime.parse(row['started_at'] as String)
                : null,
            endedAt: row['ended_at'] != null
                ? DateTime.parse(row['ended_at'] as String)
                : null,
            audioUrl: row['audio_url'] as String?,
            chatName: chatMap?['name'] as String?,
            chatType: chatMap?['type'] as String?,
            callerName: hostMap?['full_name'] as String?,
            callerAvatarUrl: hostMap?['avatar_url'] as String?,
            isChannelMeeting: false,
          ));
        } catch (e) {
          // ignore parse errors for a single row
        }
      }
    } catch (e) {
      // ignore query errors
    }
  }

  // ─── Reuniões de VÍDEO em canais (tabela meetings com channel_id) ──
  if (myChannels.isNotEmpty) {
    try {
      final channelMeetingsResponse = await supabase
          .from('meetings')
          .select('''
            id, chat_id, channel_id, host_id, status, created_at, started_at, ended_at, audio_url,
            channels (name, type),
            host:users!meetings_host_id_fkey (full_name, avatar_url)
          ''')
          .inFilter('channel_id', myChannels)
          .order('created_at', ascending: false)
          .limit(50);

      for (final row in (channelMeetingsResponse as List)) {
        try {
          final hostMap = row['host'] as Map<String, dynamic>?;
          final channelMap = row['channels'] as Map<String, dynamic>?;
          entries.add(CallHistoryEntry(
            id: row['id'] as String,
            contextId: row['channel_id'] as String? ?? '',
            callerId: row['host_id'] as String? ?? '',
            status: row['status'] as String? ?? 'ended',
            type: 'video',
            createdAt: DateTime.parse(row['created_at'] as String? ??
                row['started_at'] as String? ??
                DateTime.now().toIso8601String()),
            startedAt: row['started_at'] != null
                ? DateTime.parse(row['started_at'] as String)
                : null,
            endedAt: row['ended_at'] != null
                ? DateTime.parse(row['ended_at'] as String)
                : null,
            audioUrl: row['audio_url'] as String?,
            chatName: channelMap?['name'] as String?,
            chatType: channelMap?['type'] as String?,
            callerName: hostMap?['full_name'] as String?,
            callerAvatarUrl: hostMap?['avatar_url'] as String?,
            isChannelMeeting: true,
          ));
        } catch (e) {
          // ignore parse errors for a single row
        }
      }
    } catch (e) {
      // ignore query errors
    }
  }

  // Ordena todas as entradas por data (mais recente primeiro)
  entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return entries;
});
