import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/supabase_client.dart';

/// Provider que carrega todos os canais e grupos para auditoria.
final _auditListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // Busca todos os canais institucionais (canais são chats com type = 'channel')
  final channelsRes = await supabase
      .from('channels')
      .select('id, name, description, type, created_at')
      .eq('type', 'channel');

  // Busca todos os chats do tipo group
  final groupsRes = await supabase
      .from('channels')
      .select('id, name, description, created_at')
      .eq('type', 'group');

  final List<Map<String, dynamic>> combined = [];

  for (final row in channelsRes) {
    combined.add({
      'id': row['id'],
      'name': row['name'] ?? 'Canal sem nome',
      'description': row['description'],
      'type': 'channel',
      'created_at': row['created_at'],
    });
  }

  for (final row in groupsRes) {
    combined.add({
      'id': row['id'],
      'name': row['name'] ?? 'Grupo sem nome',
      'description': row['description'],
      'type': 'group',
      'created_at': row['created_at'],
    });
  }

  // Ordenar alfabeticamente
  combined.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

  return combined;
});

class AuditManagementTab extends ConsumerWidget {
  const AuditManagementTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(_auditListProvider);
    final theme = Theme.of(context);

    return auditAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'Erro ao carregar auditoria:\n$e',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => ref.invalidate(_auditListProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.policy_outlined,
                    size: 64, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  'Nenhum canal ou grupo disponível.',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          );
        }

        final channels = items.where((i) => i['type'] == 'channel').toList();
        final groups = items.where((i) => i['type'] == 'group').toList();

        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // Dica de Auditoria
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined,
                        color: theme.colorScheme.primary, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Modo Auditoria: Administradores podem visualizar o conteúdo de canais e grupos da empresa, mesmo sem serem membros diretos ou caso já tenham sido arquivados.',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (channels.isNotEmpty) ...[
              _SectionTitle(title: 'Canais Oficiais', theme: theme),
              ...channels.map((ch) => _AuditCard(item: ch, theme: theme)),
            ],

            if (groups.isNotEmpty) ...[
              _SectionTitle(title: 'Grupos Abertos', theme: theme),
              ...groups.map((gr) => _AuditCard(item: gr, theme: theme)),
            ],
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final ThemeData theme;
  const _SectionTitle({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final ThemeData theme;

  const _AuditCard({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    final String name = item['name'];
    final String? description = item['description'];
    final String type = item['type'];
    final String id = item['id'];

    final bool isChannel = type == 'channel';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        onTap: () {
          if (isChannel) {
            context.push('/channel/$id', extra: {'channelName': name});
          } else {
            context.push('/chat/$id', extra: {'name': name, 'isGroup': true});
          }
        },
        leading: CircleAvatar(
          backgroundColor: isChannel
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.tertiaryContainer,
          child: Icon(
            isChannel ? Icons.campaign_rounded : Icons.groups_rounded,
            color: isChannel
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onTertiaryContainer,
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: description != null && description.isNotEmpty
            ? Text(description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 12, color: theme.colorScheme.outline))
            : null,
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
