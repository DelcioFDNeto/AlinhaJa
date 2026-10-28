import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';

/// Model leve para um canal descoberto.
class DiscoverableChannel {
  final String id;
  final String name;
  final String? description;
  final int memberCount;
  final bool isMember;
  final String? requestStatus; // 'pending', 'approved', 'rejected' ou null

  const DiscoverableChannel({
    required this.id,
    required this.name,
    this.description,
    required this.memberCount,
    required this.isMember,
    this.requestStatus,
  });
}

/// Provider que busca todos os canais com flag se o usuário já participa e status da solicitação.
final discoverChannelsProvider =
    FutureProvider.autoDispose<List<DiscoverableChannel>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  // Busca todos os canais dedicados.
  final channels = await supabase
      .from('channels')
      .select('id, name, description, metadata')
      .order('name');

  // Busca solicitações de entrada feitas pelo usuário
  final requestsResp = await supabase
      .from('channel_join_requests')
      .select('channel_id, status')
      .eq('user_id', userId);

  final Map<String, String> requestStatuses = {
    for (var r in (requestsResp as List))
      r['channel_id'] as String: r['status'] as String
  };

  // Para cada canal, conta membros e verifica participação. As consultas
  // rodam em paralelo: em série eram 2 idas ao banco por canal, e a tela
  // demorava proporcionalmente ao número de canais da empresa.
  final visible = (channels as List).where((ch) {
    final metadata = (ch['metadata'] as Map<String, dynamic>?) ?? const {};
    return !(metadata['archived'] == true ||
        metadata['archived']?.toString() == 'true');
  }).toList();

  final myMemberships = await supabase
      .from('channel_members')
      .select('channel_id')
      .eq('user_id', userId);
  final memberOf = {
    for (final m in (myMemberships as List)) m['channel_id'] as String,
  };

  final result = await Future.wait(visible.map((ch) async {
    final channelId = ch['id'] as String;
    final countResp = await supabase
        .from('channel_members')
        .select('user_id')
        .eq('channel_id', channelId)
        .count();

    return DiscoverableChannel(
      id: channelId,
      name: ch['name'] as String? ?? 'Canal',
      description: ch['description'] as String?,
      memberCount: countResp.count,
      isMember: memberOf.contains(channelId),
      requestStatus: requestStatuses[channelId],
    );
  }));

  return result;
});

/// Tela de Descoberta de Canais — lista canais públicos com opção de solicitar entrada.
class ChannelDiscoveryScreen extends ConsumerWidget {
  const ChannelDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(discoverChannelsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorar Canais'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: channelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (channels) {
          if (channels.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.explore_off_rounded,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum canal disponível',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(discoverChannelsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: channels.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final channel = channels[index];
                return _ChannelDiscoveryTile(
                  channel: channel,
                  onJoin: () => _joinChannel(context, ref, channel),
                  onOpen: () {
                    context.push('/channel/${channel.id}', extra: {
                      'channelName': channel.name,
                    });
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _joinChannel(
      BuildContext context, WidgetRef ref, DiscoverableChannel channel) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      if (channel.requestStatus == 'rejected') {
        // Se já foi recusado antes, remove a solicitação antiga primeiro
        await supabase
            .from('channel_join_requests')
            .delete()
            .eq('channel_id', channel.id)
            .eq('user_id', userId);
      }

      await supabase.from('channel_join_requests').insert({
        'channel_id': channel.id,
        'user_id': userId,
        'status': 'pending',
      });

      ref.invalidate(discoverChannelsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Solicitação de entrada enviada para o canal "${channel.name}"!'),
            backgroundColor: AppConstants.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar solicitação: $e'),
            backgroundColor: AppConstants.danger,
          ),
        );
      }
    }
  }
}

class _ChannelDiscoveryTile extends StatelessWidget {
  final DiscoverableChannel channel;
  final VoidCallback onJoin;
  final VoidCallback onOpen;

  const _ChannelDiscoveryTile({
    required this.channel,
    required this.onJoin,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: channel.isMember ? onOpen : null,
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: channel.isMember
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Text(
          '#',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: channel.isMember
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.outline,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              channel.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (channel.isMember)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppConstants.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppConstants.success.withValues(alpha: 0.5)),
              ),
              child: const Text(
                'Participando',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.success,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (channel.description != null && channel.description!.isNotEmpty)
            Text(
              channel.description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.outline,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            '${channel.memberCount} membros',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
      trailing: channel.isMember
          ? const Icon(Icons.check_circle_rounded, color: AppConstants.success)
          : channel.requestStatus == 'pending'
              ? OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.hourglass_empty_rounded, size: 16),
                  label: const Text('Pendente'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                )
              : FilledButton.tonalIcon(
                  onPressed: onJoin,
                  icon: const Icon(Icons.add_moderator_rounded, size: 16),
                  label: const Text('Solicitar'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
    );
  }
}
