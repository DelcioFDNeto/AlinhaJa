import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/extensions.dart';

/// Provider do histórico de atividades do usuário atual
final userActivityHistoryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  final response = await supabase
      .from('user_activity_history')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(50);

  return (response as List).cast<Map<String, dynamic>>();
});

/// Tela de histórico de atividades do usuário
class UserActivityHistoryScreen extends ConsumerWidget {
  const UserActivityHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(userActivityHistoryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Histórico de Atividades'),
        centerTitle: false,
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                'Erro ao carregar histórico:\n$e',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
        data: (activities) {
          if (activities.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma atividade registrada.',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: activities.length,
            itemBuilder: (context, index) {
              final activity = activities[index];
              return _ActivityTile(activity: activity, theme: theme);
            },
          );
        },
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Map<String, dynamic> activity;
  final ThemeData theme;

  const _ActivityTile({required this.activity, required this.theme});

  @override
  Widget build(BuildContext context) {
    final type = activity['activity_type'] as String? ?? '';
    final description = activity['description'] as String? ?? '';
    final targetName = activity['target_name'] as String?;
    final createdAt = activity['created_at'] as String?;
    final date = createdAt != null ? DateTime.tryParse(createdAt) : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getActivityColor(type).withValues(alpha: 0.15),
          child: Icon(_getActivityIcon(type),
              color: _getActivityColor(type), size: 20),
        ),
        title: Text(
          _getActivityTitle(type),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  description,
                  style: TextStyle(
                      fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (targetName != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  targetName,
                  style:
                      TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                ),
              ),
            if (date != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.timeFormatted}',
                  style:
                      TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getActivityIcon(String type) {
    switch (type) {
      case 'message_sent':
        return Icons.send_rounded;
      case 'message_deleted':
        return Icons.delete_outline;
      case 'message_edited':
        return Icons.edit_outlined;
      case 'chat_created':
        return Icons.group_add_outlined;
      case 'channel_joined':
        return Icons.add_circle_outline;
      case 'profile_updated':
        return Icons.person_outline;
      case 'call_made':
        return Icons.call_made;
      case 'call_received':
        return Icons.call_received;
      default:
        return Icons.history;
    }
  }

  Color _getActivityColor(String type) {
    switch (type) {
      case 'message_sent':
        return Colors.blue;
      case 'message_deleted':
        return Colors.red;
      case 'message_edited':
        return Colors.orange;
      case 'chat_created':
        return Colors.green;
      case 'channel_joined':
        return Colors.purple;
      case 'profile_updated':
        return Colors.teal;
      case 'call_made':
      case 'call_received':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  String _getActivityTitle(String type) {
    switch (type) {
      case 'message_sent':
        return 'Mensagem enviada';
      case 'message_deleted':
        return 'Mensagem apagada';
      case 'message_edited':
        return 'Mensagem editada';
      case 'chat_created':
        return 'Grupo criado';
      case 'channel_joined':
        return 'Entrou em canal';
      case 'profile_updated':
        return 'Perfil atualizado';
      case 'call_made':
        return 'Iniciou chamada';
      case 'call_received':
        return 'Recebeu chamada';
      default:
        return 'Atividade';
    }
  }
}
