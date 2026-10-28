import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/workflow/models/workflow_helpers.dart';
import 'package:alinha_ja/features/workflow/providers/my_operation_provider.dart';

/// "Minha operação" — os cards do usuário em todos os workspaces.
///
/// Responde a pergunta que nenhuma tela respondia: "o que está comigo hoje".
/// Sem ela, quem atua em vários workspaces tem de abrir cada quadro para
/// descobrir o que tem na mão, e o workspace vira mais um lugar para conferir
/// em vez de o lugar onde a operação acontece.
class MyOperationScreen extends ConsumerWidget {
  const MyOperationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(myOperationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha operação'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
            onPressed: () => ref.invalidate(myOperationProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          onRetry: () => ref.invalidate(myOperationProvider),
          theme: theme,
        ),
        data: (cards) {
          if (cards.isEmpty) return _EmptyState(theme: theme);

          final grouped = groupMyCards(cards);
          final overdue = grouped[OperationBucket.atrasados]?.length ?? 0;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myOperationProvider),
            child: ResponsiveWidthContainer(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _Summary(total: cards.length, overdue: overdue, theme: theme),
                  for (final bucket in OperationBucket.values)
                    if ((grouped[bucket] ?? const []).isNotEmpty) ...[
                      _BucketHeader(
                        bucket: bucket,
                        count: grouped[bucket]!.length,
                        theme: theme,
                      ),
                      ...grouped[bucket]!.map(
                        (c) => _MyCardTile(item: c, theme: theme),
                      ),
                    ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final int total;
  final int overdue;
  final ThemeData theme;

  const _Summary(
      {required this.total, required this.overdue, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(
            total == 1 ? '1 card com você' : '$total cards com você',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (overdue > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                overdue == 1 ? '1 em atraso' : '$overdue em atraso',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BucketHeader extends StatelessWidget {
  final OperationBucket bucket;
  final int count;
  final ThemeData theme;

  const _BucketHeader(
      {required this.bucket, required this.count, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isOverdueBucket = bucket == OperationBucket.atrasados;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: [
          Icon(
            switch (bucket) {
              OperationBucket.atrasados => Icons.warning_amber_rounded,
              OperationBucket.hoje => Icons.today_rounded,
              OperationBucket.proximos => Icons.event_rounded,
              OperationBucket.semPrazo => Icons.remove_circle_outline_rounded,
              OperationBucket.concluidos => Icons.check_circle_outline_rounded,
            },
            size: 16,
            color: isOverdueBucket
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '${bucket.label} ($count)',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .3,
              color: isOverdueBucket
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyCardTile extends StatelessWidget {
  final MyCard item;
  final ThemeData theme;

  const _MyCardTile({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    final card = item.card;
    final overdue = item.isOverdueNow;
    final days = card.dueDate == null ? null : daysUntilDue(card.dueDate);

    return ListTile(
      onTap: () => context.push(
        '/channel/${item.channelId}',
        extra: {'channelName': item.channelName},
      ),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: overdue
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.secondaryContainer,
        child: Icon(
          overdue ? Icons.priority_high_rounded : Icons.assignment_outlined,
          size: 18,
          color: overdue
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(
        card.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        '${item.channelName} · ${card.status}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: days == null
          ? null
          : Text(
              days < 0
                  ? '${-days}d atrás'
                  : (days == 0 ? 'Hoje' : '${days}d'),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color:
                    overdue ? theme.colorScheme.error : theme.colorScheme.outline,
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.task_alt_rounded,
              size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          const Text('Nada com você agora',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Cards atribuídos a você aparecem aqui,\nde todos os workspaces.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final ThemeData theme;

  const _ErrorState({required this.onRetry, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          const Text('Não foi possível carregar seus cards'),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
