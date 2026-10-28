import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/channels/models/channel_model.dart';

/// Provider que lista os canais/workspaces do usuário.
/// Canais operacionais ficam isolados em `channels`, fora de DMs/grupos.
final channelsListProvider = FutureProvider<List<ChannelModel>>((ref) async {
  ref.watch(authStateProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  Timer? debounce;
  bool membersPrimed = false;

  void scheduleRefresh() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), () {
      ref.invalidateSelf();
    });
  }

  // Apenas escuta channel_members (filtrado por user_id) para detectar
  // mudanças em canais relevantes ao usuário. O stream bruto de channels
  // não é filtrado por user_id e geraria refreshes desnecessários.
  final membersSub = supabase
      .from('channel_members')
      .stream(primaryKey: ['channel_id', 'user_id'])
      .eq('user_id', userId)
      .listen((_) {
        if (!membersPrimed) {
          membersPrimed = true;
          return;
        }
        scheduleRefresh();
      });

  ref.onDispose(() {
    debounce?.cancel();
    membersSub.cancel();
  });

  final memberChannelsRes = await supabase
      .from('channel_members')
      .select('channel_id, unread_count')
      .eq('user_id', userId);

  final List<dynamic> memberList = memberChannelsRes as List;
  final channelIds = memberList.map((m) => m['channel_id'] as String).toList();
  final unreadCounts = {
    for (var m in memberList)
      m['channel_id'] as String:
          int.tryParse(m['unread_count']?.toString() ?? '0') ?? 0
  };

  if (channelIds.isEmpty) return [];

  final result = await supabase
      .from('channels')
      .select('''
        id,
        name,
        description,
        created_by,
        type,
        posting_permission,
        last_message_at,
        created_at,
        updated_at,
        metadata
      ''')
      .inFilter('id', channelIds)
      .order('last_message_at', ascending: false, nullsFirst: false);

  final channels = <ChannelModel>[];
  for (final c in (result as List)) {
    final channelJson = Map<String, dynamic>.from(c as Map);
    final metadata =
        (channelJson['metadata'] as Map<String, dynamic>?) ?? const {};

    final isArchived = metadata['archived'] == true ||
        metadata['archived']?.toString() == 'true';

    if (!isArchived) {
      channelJson['unread_count'] = unreadCounts[channelJson['id']] ?? 0;
      channels.add(ChannelModel.fromJson(channelJson));
    }
  }

  return channels;
});
