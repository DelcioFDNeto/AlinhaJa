import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/features/workflow/providers/workflow_provider.dart';
import 'package:alinha_ja/features/workflow/models/workflow_card_model.dart';
import 'package:alinha_ja/features/workflow/models/workflow_supporting_models.dart';
import 'package:alinha_ja/features/workflow/ui/widgets/card_details_sheet.dart';
import 'package:alinha_ja/features/workflow/models/workflow_helpers.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';

/// Visualização compacta (estilo spreadsheet/Notion) para ver 3x mais cards na tela.
class WorkflowCompactView extends ConsumerWidget {
  final String channelId;
  final String channelName;

  const WorkflowCompactView({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflowState = ref.watch(workflowProvider(channelId));
    final theme = Theme.of(context);

    if (workflowState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (workflowState.cards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_headline,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Nenhum card ainda',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    final currentUserId = supabase.auth.currentUser?.id;
    final filteredCards = workflowState.getFilteredCards(currentUserId);

    if (filteredCards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_off,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Nenhum card encontrado',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    // Grupo por status
    final statusGroups = <String, List<WorkflowCard>>{};
    for (final config in workflowState.statusConfig) {
      final cardsInStatus =
          filteredCards.where((c) => c.status == config.status).toList();
      if (cardsInStatus.isNotEmpty) {
        statusGroups[config.status] = cardsInStatus;
      }
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(workflowProvider(channelId).notifier).loadCards(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: statusGroups.length,
        itemBuilder: (context, groupIndex) {
          final status = statusGroups.keys.elementAt(groupIndex);
          final cards = statusGroups[status]!;
          final statusConfig = workflowState.statusConfig.firstWhere(
            (s) => s.status == status,
            orElse: () => workflowState.statusConfig.first,
          );
          final statusColor = Color(statusConfig.colorValue);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status header
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6, left: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(status.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${cards.length}',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusColor)),
                    ),
                  ],
                ),
              ),
              // Card rows
              ...cards.map((card) =>
                  _SwipeableCompactRow(card: card, channelId: channelId)),
              const SizedBox(height: 4),
            ],
          );
        },
      ),
    );
  }
}

class _CompactCardRow extends ConsumerWidget {
  final WorkflowCard card;
  final String channelId;

  const _CompactCardRow({required this.card, required this.channelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final priorityColor = Color(card.priority.color);
    final isSelected = ref.watch(workflowProvider(channelId)
        .select((s) => s.selectedCardIds.contains(card.id)));

    final statusConfig = ref
        .read(workflowProvider(channelId))
        .statusConfig
        .firstWhere((s) => s.status == card.status,
            orElse: () => WorkflowStatusConfig(
                id: '', channelId: '', status: '', statusOrder: 0));
    final slaExceeded = isSlaExceeded(card.updatedAt, card.priority.value,
        isFinalStatus: statusConfig.isFinal);

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : (slaExceeded
                ? Colors.red.withValues(alpha: 0.05)
                : theme.colorScheme.surface),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : (slaExceeded
                  ? Colors.red
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
          width: slaExceeded ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            final isSelecting =
                ref.read(workflowProvider(channelId)).isSelectionMode;
            if (isSelecting) {
              ref
                  .read(workflowProvider(channelId).notifier)
                  .toggleCardSelection(card.id);
            } else {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) =>
                    CardDetailsSheet(card: card, channelId: channelId),
              );
            }
          },
          onLongPress: () {
            ref
                .read(workflowProvider(channelId).notifier)
                .toggleCardSelection(card.id);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                // Priority indicator
                Container(
                  width: 3,
                  height: 28,
                  decoration: BoxDecoration(
                    color: slaExceeded ? Colors.red : priorityColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),

                // Checkbox (selection mode)
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.check_circle,
                        size: 18, color: theme.colorScheme.primary),
                  ),

                if (slaExceeded)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('SLA',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold)),
                  ),

                // Title
                Expanded(
                  flex: 4,
                  child: Text(card.title,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),

                // Assignee
                if (card.assignedToName != null &&
                    card.assignedToName!.isNotEmpty) ...[
                  SizedBox(
                    width: 60,
                    child: Text(card.assignedToName!.split(' ').first,
                        style: TextStyle(
                            fontSize: 11, color: theme.colorScheme.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                ],

                // Due date badge
                if (card.dueDate != null) ...[
                  _buildMiniDueBadge(card.dueDate!, theme,
                                    isClosed: ref.watch(
                                        workflowProvider(channelId).select(
                                            (s) => s.isClosedStatus(card.status)))),
                  const SizedBox(width: 8),
                ],

                // Date
                Text(formatWorkflowDate(card.createdAt),
                    style: TextStyle(
                        fontSize: 10, color: theme.colorScheme.outline)),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniDueBadge(DateTime dueDate, ThemeData theme,
      {required bool isClosed}) {
    final days = daysUntilDue(dueDate);
    // Card encerrado nao cobra prazo: sem esta checagem um card concluido
    // com atraso continua vermelho para sempre no historico.
    final overdue = !isClosed && isOverdue(dueDate);
    final color = overdue
        ? const Color(0xFFEF4444)
        : (days <= 3 ? const Color(0xFFF97316) : theme.colorScheme.outline);
    final label = overdue ? '${-days}d' : (days == 0 ? 'Hoje' : '${days}d');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// Wrapper de swipe para a view compacta.
class _SwipeableCompactRow extends ConsumerWidget {
  final WorkflowCard card;
  final String channelId;

  const _SwipeableCompactRow({required this.card, required this.channelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(workflowProvider(channelId).notifier);
    final nextStatus = notifier.getNextStatus(card.status);
    final prevStatus = notifier.getPreviousStatus(card.status);
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final canOperate = currentUser != null &&
        card.requestedBy != currentUser.id &&
        (AppPermissions.canOperateWorkflowCard(currentUser.roleLevel) ||
            card.assignedTo == currentUser.id);

    return Dismissible(
      key: ValueKey('compact_swipe_${card.id}'),
      confirmDismiss: (direction) async {
        if (!canOperate) return false;
        if (direction == DismissDirection.startToEnd && nextStatus != null) {
          final previousStatus = card.status;
          try {
            await notifier.updateCardStatus(card.id, nextStatus);
            if (context.mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('→ Avançado para "$nextStatus"'),
                action: SnackBarAction(
                    label: 'Desfazer',
                    textColor: Colors.amber,
                    onPressed: () =>
                        notifier.updateCardStatus(card.id, previousStatus)),
                duration: const Duration(seconds: 5),
              ));
            }
          } catch (_) {}
        } else if (direction == DismissDirection.endToStart &&
            prevStatus != null) {
          final previousStatus = card.status;
          try {
            await notifier.updateCardStatus(card.id, prevStatus);
            if (context.mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('← Voltou para "$prevStatus"'),
                action: SnackBarAction(
                    label: 'Desfazer',
                    textColor: Colors.amber,
                    onPressed: () =>
                        notifier.updateCardStatus(card.id, previousStatus)),
                duration: const Duration(seconds: 5),
              ));
            }
          } catch (_) {}
        }
        return false;
      },
      background: nextStatus != null
          ? Container(
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(6)),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(nextStatus,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11)),
              ]),
            )
          : const SizedBox.shrink(),
      secondaryBackground: prevStatus != null
          ? Container(
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFFF97316),
                  borderRadius: BorderRadius.circular(6)),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(prevStatus,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_back, color: Colors.white, size: 16),
              ]),
            )
          : const SizedBox.shrink(),
      child: _CompactCardRow(card: card, channelId: channelId),
    );
  }
}
