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

class WorkflowListView extends ConsumerWidget {
  final String channelId;
  final String channelName;

  const WorkflowListView({
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
            Icon(
              Icons.list_alt_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum card ainda',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Crie um card para começar a organizar',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    final currentUserId = supabase.auth.currentUser?.id;
    final filteredCards = workflowState.getFilteredCards(currentUserId);

    // U2: Differentiate "no cards" vs "no filter match"
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
            const SizedBox(height: 8),
            Text('Nenhum card corresponde aos filtros aplicados',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }
    final pinnedCards = filteredCards.where((c) => c.isPinned).toList();
    final unpinnedCards = filteredCards.where((c) => !c.isPinned).toList();

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(workflowProvider(channelId).notifier).loadCards(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (pinnedCards.isNotEmpty) ...[
            _SectionHeader(
              title: 'Fixados',
              icon: Icons.push_pin,
              theme: theme,
            ),
            const SizedBox(height: 8),
            ...pinnedCards.map((card) =>
                _SwipeableWorkflowCard(card: card, channelId: channelId)),
            const SizedBox(height: 24),
          ],
          if (unpinnedCards.isNotEmpty) ...[
            _SectionHeader(
              title: filteredCards.length != workflowState.cards.length
                  ? '${filteredCards.length} Cards Filtrados'
                  : 'Todos os Cards',
              icon: Icons.assignment_outlined,
              theme: theme,
            ),
            const SizedBox(height: 8),
            ...unpinnedCards.map((card) =>
                _SwipeableWorkflowCard(card: card, channelId: channelId)),
          ],
          // U3: Bottom padding so FAB doesn't overlap last card
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final ThemeData theme;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _WorkflowListCard extends ConsumerWidget {
  final WorkflowCard card;
  final String channelId;

  const _WorkflowListCard({required this.card, required this.channelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final priorityColor = Color(card.priority.color);

    final statusConfig = ref
        .read(workflowProvider(channelId))
        .statusConfig
        .firstWhere((s) => s.status == card.status,
            orElse: () => WorkflowStatusConfig(
                id: '', channelId: '', status: card.status, statusOrder: 0));
    final statusColor = Color(statusConfig.colorValue);
    final slaExceeded = isSlaExceeded(card.updatedAt, card.priority.value,
        isFinalStatus: statusConfig.isFinal);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: slaExceeded
            ? Colors.red.withValues(alpha: 0.05)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: slaExceeded
              ? Colors.red
              : theme.colorScheme.outline.withValues(alpha: 0.1),
          width: slaExceeded ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            final isSelecting =
                ref.read(workflowProvider(channelId)).isSelectionMode;
            if (isSelecting) {
              ref
                  .read(workflowProvider(channelId).notifier)
                  .toggleCardSelection(card.id);
            } else {
              _showCardDetails(context, ref);
            }
          },
          onLongPress: () {
            ref
                .read(workflowProvider(channelId).notifier)
                .toggleCardSelection(card.id);
          },
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 60,
                      decoration: BoxDecoration(
                        color: slaExceeded ? Colors.red : priorityColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (card.isPinned)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(
                                    Icons.push_pin,
                                    size: 14,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              if (slaExceeded)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('SLA EXCEDIDO',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold)),
                                ),
                              Expanded(
                                child: Text(
                                  card.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (card.description != null &&
                              card.description!.isNotEmpty)
                            Text(
                              card.description!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildChip(
                                label: statusConfig.status,
                                color: statusColor,
                                theme: theme,
                              ),
                              _buildChip(
                                label: card.priority.label,
                                color: priorityColor,
                                theme: theme,
                              ),
                              if (card.requestedByName != null &&
                                  card.requestedByName!.isNotEmpty)
                                _buildChip(
                                  label: card.requestedByName!.split(' ').first,
                                  color: theme.colorScheme.secondary,
                                  theme: theme,
                                ),
                              if (card.assignedToName != null &&
                                  card.assignedToName!.isNotEmpty)
                                _buildChip(
                                  label: card.assignedToName!.split(' ').first,
                                  color: theme.colorScheme.tertiary,
                                  theme: theme,
                                ),
                              if (card.dueDate != null)
                                _buildDueDateChip(card.dueDate!, theme,
                                    isClosed: ref.watch(
                                        workflowProvider(channelId).select(
                                            (s) => s.isClosedStatus(card.status)))),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 12,
                                    color: theme.colorScheme.outline,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    formatWorkflowDate(card.createdAt),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
              // Checkbox overlay for selection mode
              if (ref.watch(workflowProvider(channelId)
                  .select((s) => s.selectedCardIds.contains(card.id))))
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 4)
                      ],
                    ),
                    padding: const EdgeInsets.all(2),
                    child:
                        const Icon(Icons.check, size: 14, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required Color color,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDueDateChip(DateTime dueDate, ThemeData theme,
      {required bool isClosed}) {
    final days = daysUntilDue(dueDate);
    // Card encerrado nao cobra prazo: sem esta checagem um card concluido
    // com atraso continua vermelho para sempre no historico.
    final overdue = !isClosed && isOverdue(dueDate);
    final color = overdue
        ? const Color(0xFFEF4444)
        : (days <= 3 ? const Color(0xFFF97316) : theme.colorScheme.outline);
    final label =
        overdue ? '${-days}d atrás' : (days == 0 ? 'Hoje' : '${days}d');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(overdue ? Icons.warning_amber_rounded : Icons.event_rounded,
              size: 10, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  void _showCardDetails(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // B3: Use shared CardDetailsSheet widget
      builder: (ctx) => CardDetailsSheet(card: card, channelId: channelId),
    );
  }
}

/// Wrapper que adiciona swipe-to-advance (→) e swipe-to-revert (←) nos cards.
class _SwipeableWorkflowCard extends ConsumerWidget {
  final WorkflowCard card;
  final String channelId;

  const _SwipeableWorkflowCard({required this.card, required this.channelId});

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
      key: ValueKey('swipe_${card.id}'),
      confirmDismiss: (direction) async {
        if (!canOperate) return false;
        if (direction == DismissDirection.startToEnd && nextStatus != null) {
          // Swipe → = avançar status
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
                      notifier.updateCardStatus(card.id, previousStatus),
                ),
                duration: const Duration(seconds: 5),
              ));
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Falha: ${e.toString().replaceFirst("Exception: ", "")}'),
                    backgroundColor: Colors.red),
              );
            }
          }
        } else if (direction == DismissDirection.endToStart &&
            prevStatus != null) {
          // Swipe ← = voltar status
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
                      notifier.updateCardStatus(card.id, previousStatus),
                ),
                duration: const Duration(seconds: 5),
              ));
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Falha: ${e.toString().replaceFirst("Exception: ", "")}'),
                    backgroundColor: Colors.red),
              );
            }
          }
        }
        return false; // Nunca remove — só atualiza o status
      },
      background: nextStatus != null
          ? Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.arrow_forward,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(nextStatus,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ),
            )
          : const SizedBox.shrink(),
      secondaryBackground: prevStatus != null
          ? Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF97316),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(prevStatus,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                ],
              ),
            )
          : const SizedBox.shrink(),
      child: _WorkflowListCard(card: card, channelId: channelId),
    );
  }
}
