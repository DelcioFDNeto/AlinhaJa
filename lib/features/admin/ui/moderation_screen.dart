import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Provider para buscar mensagens que podem precisar de moderação
final moderationMessagesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  // Verifica se é admin
  final userData = await supabase
      .from('users')
      .select('role_level')
      .eq('id', userId)
      .maybeSingle();

  if (userData == null) {
    return [];
  }

  final roleLevel = userData['role_level'] as String?;
  if (!AppPermissions.canModerate(roleLevel)) {
    return [];
  }

  // Busca mensagens recentes (últimas 24h) para moderação
  final yesterday = DateTime.now().subtract(const Duration(hours: 24));

  final messages = await supabase
      .from('messages')
      .select('''
        id, content, content_type, created_at, chat_id,
        sender:users(id, full_name, avatar_url, department_id),
        chats!messages_chat_id_fkey(id, name, type)
      ''')
      .gte('created_at', yesterday.toIso8601String())
      .order('created_at', ascending: false)
      .limit(100);

  return (messages as List).cast<Map<String, dynamic>>();
});

/// Provider para buscar canais que precisam de moderação
final moderationChannelsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  final userData = await supabase
      .from('users')
      .select('role_level')
      .eq('id', userId)
      .maybeSingle();

  if (userData == null) {
    return [];
  }

  final roleLevel = userData['role_level'] as String?;
  if (!AppPermissions.canModerate(roleLevel)) {
    return [];
  }

  // Busca canais para moderação. Swapped to channel_members to prevent crashes
  final channels = await supabase
      .from('channels')
      .select('''
        id, name, description, created_at, created_by,
        metadata, member_count:channel_members(count)
      ''')
      .eq('type', 'channel')
      .order('created_at', ascending: false)
      .limit(50);

  return (channels as List).cast<Map<String, dynamic>>();
});

/// Tela de moderação para admins
class ModerationScreen extends ConsumerWidget {
  const ModerationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Moderação de Conteúdo'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Mensagens', icon: Icon(Icons.message)),
              Tab(text: 'Canais', icon: Icon(Icons.campaign)),
            ],
          ),
        ),
        body: const ResponsiveWidthContainer(
          child: TabBarView(
            children: [
              _MessagesModerationTab(),
              _ChannelsModerationTab(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessagesModerationTab extends ConsumerWidget {
  const _MessagesModerationTab();

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _warnUser(
      BuildContext context, String? userId, String? content) async {
    if (userId == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Advertência enviada ao usuário.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  /// Coleta a justificativa obrigatória da ação de moderação.
  ///
  /// A RPC recusa textos com menos de 10 caracteres — a validação aqui é
  /// só para dar retorno imediato, não é a garantia.
  Future<String?> _pedirJustificativa(
    BuildContext context, {
    required String titulo,
    required String descricao,
  }) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(descricao, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Motivo da moderação (mínimo 10 caracteres)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final texto = ctrl.text.trim();
              if (texto.length < 10) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Descreva o motivo com ao menos 10 caracteres.'),
                  ),
                );
                return;
              }
              Navigator.pop(ctx, texto);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _deleteMessage(
      BuildContext context, String messageId, WidgetRef ref) async {
    // Moderação exige justificativa registrada. O UPDATE direto que havia
    // aqui esbarrava na RLS (só o autor atualiza a própria mensagem), então
    // além de não deixar rastro, na prática não funcionava para conteúdo de
    // terceiros. A RPC valida o papel e grava em audit_log.
    final justificativa = await _pedirJustificativa(
      context,
      titulo: 'Excluir mensagem',
      descricao:
          'Registre o motivo da remoção. A ação fica no log de auditoria '
          'com seu nome e a data.',
    );
    if (justificativa == null) return;

    try {
      await supabase.rpc('admin_moderate_message', params: {
        'p_message_id': messageId,
        'p_justificativa': justificativa,
      });

      ref.invalidate(moderationMessagesProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mensagem excluída e registrada.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(moderationMessagesProvider);
    final theme = Theme.of(context);

    return messagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 8),
            Text('Erro: $e', style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
      data: (messages) {
        if (messages.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text('Nenhuma mensagem para moderar nas últimas 24h'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            final sender = msg['sender'] as Map<String, dynamic>?;
            final chat = msg['chats'] as Map<String, dynamic>?;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundImage: sender?['avatar_url'] != null
                              ? CachedNetworkImageProvider(sender!['avatar_url'] as String, maxWidth: 320)
                              : null,
                          child: sender?['avatar_url'] == null
                              ? Text((sender?['full_name'] as String? ?? '?')[0]
                                  .toUpperCase())
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sender?['full_name'] ?? 'Desconhecido',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Em: ${chat?['name'] ?? 'Chat'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatDate(msg['created_at'] as String),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        msg['content'] as String? ?? '',
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _warnUser(
                              context,
                              sender?['id'] as String?,
                              msg['content'] as String?),
                          icon: const Icon(Icons.warning_amber, size: 16),
                          label: const Text('Advertir'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () =>
                              _deleteMessage(context, msg['id'] as String, ref),
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Excluir'),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ChannelsModerationTab extends ConsumerWidget {
  const _ChannelsModerationTab();

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(moderationChannelsProvider);
    final theme = Theme.of(context);

    return channelsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro: $e')),
      data: (channels) {
        if (channels.isEmpty) {
          return const Center(child: Text('Nenhum canal encontrado'));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final channel = channels[index];
            final memberCount =
                (channel['member_count'] as List?)?.firstOrNull?['count'] ?? 0;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.campaign,
                        size: 32,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            channel['name'] as String? ?? 'Sem nome',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (channel['description'] != null &&
                              (channel['description'] as String)
                                  .isNotEmpty) ...[
                            Text(
                              channel['description'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.people_outline,
                                      size: 14,
                                      color: theme
                                          .colorScheme.onSecondaryContainer,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$memberCount membros',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: theme
                                            .colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Criado em: ${_formatDate(channel['created_at'] as String)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
