import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/chats/ui/channel_discovery_screen.dart'; // Reutilizando model basico
import 'package:alinha_ja/features/profile/models/user_model.dart';

class ChatInfoState {
  final Map<String, int> messageCounts; // userId -> count
  final List<MessageModel> sharedMedia;
  final List<DiscoverableChannel> commonChats;
  final Map<String, dynamic>? chatDetails;
  final UserModel? targetUser;
  final bool isLoading;

  const ChatInfoState({
    this.messageCounts = const {},
    this.sharedMedia = const [],
    this.commonChats = const [],
    this.chatDetails,
    this.targetUser,
    this.isLoading = true,
  });

  ChatInfoState copyWith({
    Map<String, int>? messageCounts,
    List<MessageModel>? sharedMedia,
    List<DiscoverableChannel>? commonChats,
    Map<String, dynamic>? chatDetails,
    UserModel? targetUser,
    bool? isLoading,
  }) {
    return ChatInfoState(
      messageCounts: messageCounts ?? this.messageCounts,
      sharedMedia: sharedMedia ?? this.sharedMedia,
      commonChats: commonChats ?? this.commonChats,
      chatDetails: chatDetails ?? this.chatDetails,
      targetUser: targetUser ?? this.targetUser,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ChatInfoArgs {
  final String chatId;
  final bool isGroup;
  final String? targetUserId; // Para DMs

  const ChatInfoArgs({
    required this.chatId,
    required this.isGroup,
    this.targetUserId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatInfoArgs &&
          runtimeType == other.runtimeType &&
          chatId == other.chatId &&
          isGroup == other.isGroup &&
          targetUserId == other.targetUserId;

  @override
  int get hashCode =>
      chatId.hashCode ^ isGroup.hashCode ^ targetUserId.hashCode;
}

class ChatInfoNotifier extends FamilyNotifier<ChatInfoState, ChatInfoArgs> {
  @override
  ChatInfoState build(ChatInfoArgs arg) {
    Future.microtask(() => _loadData());
    return const ChatInfoState(isLoading: true);
  }

  Future<void> _loadData() async {
    final futures = <Future>[];

    // Carregar detalhes do chat
    futures.add(_fetchChatDetails());

    // 1. Carregar contagem de mensagens (se for grupo)
    if (arg.isGroup) {
      futures.add(_fetchMessageCounts());
    }

    // 2. Carregar mídias compartilhadas
    futures.add(_fetchSharedMedia());

    // 3. Carregar targetUser e chats em comum (se for DM)
    if (!arg.isGroup) {
      futures.add(_fetchTargetUserAndCommonChats());
    }

    await Future.wait(futures);

    state = state.copyWith(isLoading: false);
  }

  Future<void> _fetchChatDetails() async {
    try {
      final res = await supabase
          .from('chats')
          .select(
              'id, name, description, avatar_url, created_by, type, metadata')
          .eq('id', arg.chatId)
          .maybeSingle();
      if (res != null) {
        state = state.copyWith(chatDetails: res);
      }
    } catch (_) {}
  }

  Future<void> _fetchMessageCounts() async {
    try {
      final resCount = await supabase
          .from('messages')
          .select('sender_id')
          .eq('chat_id', arg.chatId);

      Map<String, int> counts = {};
      for (final row in (resCount as List)) {
        final sid = row['sender_id'] as String;
        counts[sid] = (counts[sid] ?? 0) + 1;
      }

      state = state.copyWith(messageCounts: counts);
    } catch (_) {}
  }

  Future<void> _fetchSharedMedia() async {
    try {
      final res = await supabase
          .from('messages')
          .select('*')
          .eq('chat_id', arg.chatId)
          .inFilter('content_type', ['image', 'video', 'file'])
          .order('created_at', ascending: false)
          .limit(100); // Traz as 100 media mais recentes

      // Mídia de visualização única não entra na galeria: por aqui ela abria
      // direto, quantas vezes quisessem, sem passar pelo consumo.
      final media = (res as List)
          .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
          .where((m) => !m.isViewOnce)
          .toList();
      state = state.copyWith(sharedMedia: media);
    } catch (_) {}
  }

  Future<void> _fetchTargetUserAndCommonChats() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    String? tId = arg.targetUserId;
    if (tId == null) {
      try {
        final membersRes = await supabase
            .from('chat_members')
            .select('user_id')
            .eq('chat_id', arg.chatId);
        final memberIds =
            (membersRes as List).map((e) => e['user_id'] as String).toList();
        tId = memberIds.firstWhere((id) => id != myId, orElse: () => '');
      } catch (_) {}
    }

    if (tId == null || tId.isEmpty) return;

    try {
      // Sem cpf/data_nascimento/sexo/phone: é a info de um COLEGA, não há
      // finalidade legítima para dado sensível aqui (LGPD Art. 6º, III —
      // necessidade). O privilégio de coluna foi revogado no banco, então
      // pedi-los aqui devolveria 403 e derrubaria a tela inteira.
      final userRes = await supabase
          .from('users')
          .select(
              'id, full_name, avatar_url, email, is_online, last_seen_at, branch_id, role_level, department_id, job_position_id, is_active, branches(id, name), departments(name), job_positions(name)')
          .eq('id', tId)
          .maybeSingle();

      if (userRes != null) {
        final userModel =
            UserModel.fromJson(Map<String, dynamic>.from(userRes));
        state = state.copyWith(targetUser: userModel);
      }
    } catch (_) {}

    try {
      final myChatsRes = await supabase
          .from('chat_members')
          .select('chat_id')
          .eq('user_id', myId);
      final myChatIds =
          (myChatsRes as List).map((e) => e['chat_id'] as String).toList();

      if (myChatIds.isNotEmpty) {
        final intersectionRes = await supabase
            .from('chat_members')
            .select('chat_id')
            .eq('user_id', tId)
            .inFilter('chat_id', myChatIds);

        final commonIds = (intersectionRes as List)
            .map((e) => e['chat_id'] as String)
            .toList();

        if (commonIds.isNotEmpty) {
          final chatsDetails = await supabase
              .from('chats')
              .select('id, name, description, type')
              .inFilter('id', commonIds)
              .not('type', 'eq', 'dm');

          final List<DiscoverableChannel> common =
              (chatsDetails as List).map((c) {
            return DiscoverableChannel(
              id: c['id'] as String,
              name: c['name'] as String? ?? 'Chat',
              description: c['description'] as String?,
              memberCount: 0,
              isMember: true,
            );
          }).toList();

          state = state.copyWith(commonChats: common);
        }
      }
    } catch (_) {}
  }
}

final chatInfoProvider =
    NotifierProvider.family<ChatInfoNotifier, ChatInfoState, ChatInfoArgs>(
  ChatInfoNotifier.new,
);
