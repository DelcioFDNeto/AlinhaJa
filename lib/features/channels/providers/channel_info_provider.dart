import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/channels/models/channel_message_model.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';

class ChannelInfoState {
  final Map<String, int> messageCounts; // userId -> count
  final List<ChannelMessageModel> sharedMedia;
  final List<UserModel> channelMembers;

  /// userId -> papel em `channel_members.role` ('admin' | 'editor' | 'viewer').
  /// Alimenta o menu de gestão de membros da tela de info.
  final Map<String, String> memberRoles;
  final List<Map<String, dynamic>> pendingRequests;
  final Map<String, dynamic>? channelDetails;
  final bool isLoading;

  const ChannelInfoState({
    this.messageCounts = const {},
    this.sharedMedia = const [],
    this.channelMembers = const [],
    this.memberRoles = const {},
    this.pendingRequests = const [],
    this.channelDetails,
    this.isLoading = true,
  });

  ChannelInfoState copyWith({
    Map<String, int>? messageCounts,
    List<ChannelMessageModel>? sharedMedia,
    List<UserModel>? channelMembers,
    Map<String, String>? memberRoles,
    List<Map<String, dynamic>>? pendingRequests,
    Map<String, dynamic>? channelDetails,
    bool? isLoading,
  }) {
    return ChannelInfoState(
      messageCounts: messageCounts ?? this.messageCounts,
      sharedMedia: sharedMedia ?? this.sharedMedia,
      channelMembers: channelMembers ?? this.channelMembers,
      memberRoles: memberRoles ?? this.memberRoles,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      channelDetails: channelDetails ?? this.channelDetails,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ChannelInfoNotifier extends FamilyNotifier<ChannelInfoState, String> {
  String get channelId => arg;

  @override
  ChannelInfoState build(String arg) {
    Future.microtask(() => _loadData());
    return const ChannelInfoState(isLoading: true);
  }

  Future<void> _loadData() async {
    await Future.wait([
      _fetchChannelDetails(),
      _fetchMessageCounts(),
      _fetchSharedMedia(),
      _fetchPendingRequests(),
    ]);

    state = state.copyWith(isLoading: false);
  }

  Future<void> _fetchChannelDetails() async {
    try {
      final res = await supabase
          .from('channels')
          .select(
              'id, name, description, created_by, type, metadata, posting_permission')
          .eq('id', channelId)
          .maybeSingle();
      if (res != null) {
        state = state.copyWith(channelDetails: res);
      }
    } catch (_) {}
  }

  Future<void> _fetchPendingRequests() async {
    try {
      final res = await supabase
          .from('channel_join_requests')
          .select(
              'id, status, created_at, user_id, users(id, full_name, avatar_url, email, role_level)')
          .eq('channel_id', channelId)
          .eq('status', 'pending');

      state = state.copyWith(
          pendingRequests: List<Map<String, dynamic>>.from(res as List));
    } catch (e) {
      debugPrint('Erro ao buscar solicitacoes pendentes: $e');
    }
  }

  Future<void> _fetchMessageCounts() async {
    try {
      final membersRes = await supabase
          .from('channel_members')
          .select('user_id, role')
          .eq('channel_id', channelId);

      final memberIds =
          (membersRes as List).map((m) => m['user_id'] as String).toList();
      final roles = <String, String>{
        for (final m in membersRes)
          m['user_id'] as String: (m['role'] as String?) ?? 'viewer',
      };

      final usersRes = await supabase
          .from('users')
          .select(UserModel.selectColumns)
          .inFilter('id', memberIds);

      final members =
          (usersRes as List).map((u) => UserModel.fromJson(u)).toList();

      final counts = await _countMessagesBySender();

      state = state.copyWith(
        messageCounts: counts,
        channelMembers: members,
        memberRoles: roles,
      );
    } catch (e) {
      debugPrint('Erro ao buscar contagens de mensagens: $e');
    }
  }

  /// Mensagens por membro, agregadas no banco.
  ///
  /// Baixar o `sender_id` de cada mensagem esbarrava no limite de 1000 linhas
  /// do PostgREST (contagem errada em canal grande), contava mensagens
  /// apagadas e quebrava com remetente nulo (usuário excluído).
  Future<Map<String, int>> _countMessagesBySender() async {
    final counts = <String, int>{};
    try {
      final rows = await supabase.rpc('get_channel_message_counts',
          params: {'p_channel_id': channelId});
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final sid = row['sender_id']?.toString();
        if (sid == null) continue;
        counts[sid] = (row['total'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      // Contagem é enfeite da lista: sem ela, os membros aparecem mesmo assim.
      debugPrint('Contagem de mensagens indisponível: $e');
    }
    return counts;
  }

  Future<void> _fetchSharedMedia() async {
    try {
      final res = await supabase
          .from('channel_messages')
          .select('*')
          .eq('channel_id', channelId)
          .inFilter('content_type', ['image', 'video', 'file'])
          // Arquivo apagado no chat não pode continuar acessível na galeria.
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(100);

      final media = (res as List)
          .map((m) => ChannelMessageModel.fromJson(m as Map<String, dynamic>))
          .toList();
      state = state.copyWith(sharedMedia: media);
    } catch (_) {}
  }
}

final channelInfoProvider =
    NotifierProvider.family<ChannelInfoNotifier, ChannelInfoState, String>(
  ChannelInfoNotifier.new,
);
