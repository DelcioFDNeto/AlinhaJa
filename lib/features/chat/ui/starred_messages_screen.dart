import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/extensions.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';

/// Provider que busca as mensagens favoritadas pelo usuário atual.
final starredMessagesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  // Favoritos de conversas (DMs e grupos)
  final starred = await supabase
      .from('starred_messages')
      .select(
          'id, created_at, chat_message_id, messages!inner(id, content, content_type, media_url, created_at, chat_id, sender:users(id, full_name, avatar_url), chats(type))')
      .eq('user_id', userId)
      .not('chat_message_id', 'is', null)
      .order('created_at', ascending: false);

  // Normaliza os resultados num formato unificado
  final List<Map<String, dynamic>> unified = [];

  for (final row in starred) {
    final msg = row['messages'] as Map<String, dynamic>?;
    if (msg == null) continue;
    final chats = msg['chats'] as Map<String, dynamic>?;
    final isChannel = chats?['type'] == 'channel';
    unified.add({
      'starred_id': row['id'],
      'starred_at': row['created_at'],
      'source': isChannel ? 'channel' : 'chat',
      'message': msg,
    });
  }

  // Favoritos de canais. `channel_messages.sender_id` aponta para auth.users,
  // então o autor é resolvido numa segunda consulta em vez de embed.
  final starredChannel = await supabase
      .from('starred_messages')
      .select(
          'id, created_at, channel_message_id, channel_messages!inner(id, content, content_type, media_url, created_at, channel_id, sender_id)')
      .eq('user_id', userId)
      .not('channel_message_id', 'is', null)
      .order('created_at', ascending: false);

  final channelRows = (starredChannel as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  if (channelRows.isNotEmpty) {
    final senderIds = <String>{
      for (final row in channelRows)
        if ((row['channel_messages'] as Map?)?['sender_id'] != null)
          (row['channel_messages'] as Map)['sender_id'].toString(),
    };

    final senders = <String, Map<String, dynamic>>{};
    if (senderIds.isNotEmpty) {
      final usersRes = await supabase
          .from('users')
          .select('id, full_name, avatar_url')
          .inFilter('id', senderIds.toList());
      for (final u in (usersRes as List)) {
        senders[u['id'].toString()] = Map<String, dynamic>.from(u as Map);
      }
    }

    for (final row in channelRows) {
      final msg = (row['channel_messages'] as Map?) == null
          ? null
          : Map<String, dynamic>.from(row['channel_messages'] as Map);
      if (msg == null) continue;
      // A tela navega por `chat_id`; no canal o equivalente é `channel_id`.
      msg['chat_id'] = msg['channel_id'];
      msg['sender'] = senders[msg['sender_id']?.toString()];
      unified.add({
        'starred_id': row['id'],
        'starred_at': row['created_at'],
        'source': 'channel',
        'message': msg,
      });
    }
  }

  // Ordena tudo junto por data de favoritação (mais recente primeiro)
  unified.sort((a, b) =>
      (b['starred_at'] as String).compareTo(a['starred_at'] as String));

  return unified;
});

/// Tela que exibe todas as mensagens favoritas do usuário.
class StarredMessagesScreen extends ConsumerWidget {
  const StarredMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starredAsync = ref.watch(starredMessagesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('⭐ Mensagens Favoritas',
            style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: ResponsiveWidthContainer(
        child: starredAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erro: $e')),
          data: (items) {
            if (items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_border_rounded,
                        size: 64, color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhuma mensagem favorita ainda.',
                      style: TextStyle(
                          fontSize: 16, color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Segure uma mensagem para favoritar.',
                      style: TextStyle(
                          fontSize: 13, color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () => ref.refresh(starredMessagesProvider.future),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final msg = item['message'] as Map<String, dynamic>;
                  final sender = msg['sender'] as Map<String, dynamic>?;
                  final source = item['source'] as String;
                  final contentType = msg['content_type'] as String? ?? 'text';

                  String preview;
                  switch (contentType) {
                    case 'image':
                      preview = '📷 Foto';
                      break;
                    case 'audio':
                      preview = '🎤 Áudio';
                      break;
                    case 'file':
                      preview = '📎 Documento';
                      break;
                    case 'meeting':
                      preview = '📹 Reunião';
                      break;
                    default:
                      preview = msg['content'] as String? ?? '';
                  }

                  final senderName =
                      sender?['full_name'] as String? ?? 'Desconhecido';
                  final avatarUrl = sender?['avatar_url'] as String?;
                  final createdAt =
                      DateTime.tryParse(msg['created_at'] as String? ?? '');

                  return Dismissible(
                    key: Key(item['starred_id'].toString()),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.redAccent,
                      child: const Icon(Icons.star_border, color: Colors.white),
                    ),
                    onDismissed: (_) async {
                      try {
                        await supabase
                            .from('starred_messages')
                            .delete()
                            .eq('id', item['starred_id']);
                        ref.invalidate(starredMessagesProvider);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Erro ao desfavoritar: $e'),
                                backgroundColor: AppConstants.danger),
                          );
                        }
                      }
                    },
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        backgroundImage: avatarUrl != null
                            ? CachedNetworkImageProvider(avatarUrl, maxWidth: 320)
                            : null,
                        child: avatarUrl == null
                            ? Text(
                                senderName.isNotEmpty
                                    ? senderName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              )
                            : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              senderName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (createdAt != null)
                            Text(
                              createdAt.chatListFormatted,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.outline),
                            ),
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Icon(
                            source == 'channel'
                                ? Icons.campaign_rounded
                                : Icons.chat_bubble_outline_rounded,
                            size: 14,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        // Navega para o chat/canal de origem da mensagem
                        final chatId = msg['chat_id'] as String?;
                        if (chatId == null) return;
                        if (source == 'channel') {
                          context.push('/channel/$chatId',
                              extra: {'channelName': 'Canal (Via Favoritos)'});
                        } else {
                          context.push('/chat/$chatId',
                              extra: {'name': senderName, 'isGroup': false});
                        }
                      },
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
