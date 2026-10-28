import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/features/workflow/providers/workflow_provider.dart';
import 'package:alinha_ja/features/workflow/models/workflow_card_model.dart';
import 'package:alinha_ja/features/workflow/models/workflow_supporting_models.dart';
import 'package:alinha_ja/features/workflow/models/workflow_enums.dart';
import 'package:alinha_ja/features/workflow/ui/widgets/card_details_sheet.dart';
import 'package:alinha_ja/features/workflow/models/workflow_helpers.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';

class WorkflowBoardView extends ConsumerWidget {
  final String channelId;
  final String channelName;

  const WorkflowBoardView(
      {super.key, required this.channelId, required this.channelName});

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
            Icon(Icons.dashboard_customize_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Nenhum card ainda',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 8),
            Text('Crie um card para começar a organizar',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    final filteredCards = workflowState.filteredCards;
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

    final statusColumns =
        workflowState.statusConfig.where((s) => !s.isCancelled).toList();
    if (statusColumns.isEmpty) {
      return Center(
        child: Text('Configurando workspace...',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasUnmatched = filteredCards.any((c) =>
            !statusColumns.map((c) => c.status).toSet().contains(c.status));
        final totalColumns =
            (statusColumns.length + (hasUnmatched ? 1 : 0)).clamp(1, 99);

        const columnSpacing = 16.0;
        const padding = 32.0;

        final availableWidth = constraints.maxWidth - padding;
        final isMobile = constraints.maxWidth <
            800; // Tratando como mobile/tablet se for muito estreito

        // No mobile ajustamos pra tela inteira, no Desktop esprememos pra caber tudo em 1 linha sem wrap!
        final columnWidth = isMobile
            ? availableWidth
            : (availableWidth - ((totalColumns - 1) * columnSpacing)) /
                totalColumns;

        return RefreshIndicator(
          onRefresh: () =>
              ref.read(workflowProvider(channelId).notifier).loadCards(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: columnSpacing,
              runSpacing: columnSpacing,
              alignment: WrapAlignment.start,
              children: () {
                final configuredStatuses =
                    statusColumns.map((c) => c.status).toSet();
                final unmatchedCards = filteredCards
                    .where((c) =>
                        !configuredStatuses.contains(c.status) &&
                        !workflowState.isCancelledStatus(c.status))
                    .toList();

                final children = statusColumns.map((statusConfig) {
                  final cardsInStatus = filteredCards
                      .where((c) => c.status == statusConfig.status)
                      .toList();
                  return SizedBox(
                    width: columnWidth,
                    child: DragTarget<WorkflowCard>(
                      onAcceptWithDetails: (details) async {
                        final card = details.data;
                        if (card.status != statusConfig.status) {
                          final previousStatus = card.status;
                          try {
                            await ref
                                .read(workflowProvider(channelId).notifier)
                                .updateCardStatus(card.id, statusConfig.status);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(
                                    'Card movido para "${statusConfig.status}"',
                                    style:
                                        const TextStyle(color: Colors.white)),
                                backgroundColor: Colors.green.shade600,
                                action: SnackBarAction(
                                  label: 'Desfazer',
                                  textColor: Colors.white,
                                  onPressed: () {
                                    ref
                                        .read(workflowProvider(channelId)
                                            .notifier)
                                        .updateCardStatus(
                                            card.id, previousStatus);
                                  },
                                ),
                                duration: const Duration(seconds: 2),
                              ));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Falha: Sem permissão para mover este card.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isHovering = candidateData.isNotEmpty;
                        return _StatusColumn(
                            statusConfig: statusConfig,
                            cards: cardsInStatus,
                            channelId: channelId,
                            isHovering: isHovering,
                            columnWidth: columnWidth);
                      },
                    ),
                  );
                }).toList();

                if (unmatchedCards.isNotEmpty) {
                  final othersConfig = WorkflowStatusConfig(
                      id: 'outros',
                      channelId: channelId,
                      status: 'Não categorizados',
                      statusOrder: 99,
                      icon: 'warning',
                      color: '#6B7280');
                  children.add(SizedBox(
                      width: columnWidth,
                      child: DragTarget<WorkflowCard>(
                        onAcceptWithDetails: (details) async {
                          final card = details.data;
                          if (card.status != othersConfig.status) {
                            try {
                              await ref
                                  .read(workflowProvider(channelId).notifier)
                                  .updateCardStatus(
                                      card.id, othersConfig.status);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Falha: ${e.toString().replaceFirst('Exception: ', '')}'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          }
                        },
                        builder: (context, candidateData, rejectedData) {
                          final isHovering = candidateData.isNotEmpty;
                          return _StatusColumn(
                              statusConfig: othersConfig,
                              cards: unmatchedCards,
                              channelId: channelId,
                              isHovering: isHovering,
                              columnWidth: columnWidth);
                        },
                      )));
                }

                return children;
              }(),
            ),
          ),
        );
      },
    );
  }
}

class _StatusColumn extends ConsumerWidget {
  final WorkflowStatusConfig statusConfig;
  final List<WorkflowCard> cards;
  final String channelId;
  final bool isHovering;
  final double columnWidth;

  const _StatusColumn(
      {required this.statusConfig,
      required this.cards,
      required this.channelId,
      this.isHovering = false,
      this.columnWidth = 280});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColor = Color(statusConfig.colorValue);
    final currentUser = ref.watch(currentUserProvider).valueOrNull;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: columnWidth,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isHovering
            ? statusColor.withValues(alpha: 0.05)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: isHovering
            ? Border.all(color: statusColor, width: 2)
            : Border.all(color: Colors.transparent, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(_getIconForStatus(statusConfig.icon),
                    size: 16, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(statusConfig.status.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.8)))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('${cards.length}',
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              final canMove = currentUser != null &&
                  card.requestedBy != currentUser.id &&
                  (AppPermissions.canOperateWorkflowCard(
                          currentUser.roleLevel) ||
                      card.assignedTo == currentUser.id);

              if (!canMove) {
                return _WorkflowCardTile(card: card, channelId: channelId);
              }

              return Draggable<WorkflowCard>(
                data: card,
                feedback: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                        width: 260,
                        child: _WorkflowCardTile(
                            card: card,
                            channelId: channelId,
                            isDragging: true))),
                childWhenDragging: Opacity(
                    opacity: 0.5,
                    child: _WorkflowCardTile(card: card, channelId: channelId)),
                child: _WorkflowCardTile(card: card, channelId: channelId),
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _getIconForStatus(String iconName) {
    switch (iconName) {
      case 'add_circle':
        return Icons.add_circle_outline;
      case 'pending':
        return Icons.pending_outlined;
      case 'hourglass_empty':
        return Icons.hourglass_empty;
      case 'check_circle':
        return Icons.check_circle_outline;
      case 'cancel':
        return Icons.cancel_outlined;
      case 'payments':
        return Icons.payments_outlined;
      case 'sync':
        return Icons.sync;
      case 'warning':
        return Icons.warning_amber_outlined;
      case 'error_outline':
        return Icons.error_outline;
      case 'task_alt':
        return Icons.task_alt;
      case 'archive':
        return Icons.archive_outlined;
      case 'publish':
        return Icons.publish;
      case 'fact_check':
        return Icons.fact_check_outlined;
      default:
        return Icons.circle_outlined;
    }
  }
}

class _WorkflowCardTile extends ConsumerWidget {
  final WorkflowCard card;
  final String channelId;
  final bool isDragging;

  const _WorkflowCardTile(
      {required this.card, required this.channelId, this.isDragging = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final priorityColor = Color(card.priority.color);

    final statusConfig = ref
        .read(workflowProvider(channelId))
        .statusConfig
        .firstWhere((s) => s.status == card.status,
            orElse: () => WorkflowStatusConfig(
                id: '', channelId: '', status: '', statusOrder: 0));
    final slaExceeded = isSlaExceeded(card.updatedAt, card.priority.value,
        isFinalStatus: statusConfig.isFinal);

    String? displaySubtitle;
    if (card.cardType.value == 'conta_pagar' && card.amount != null) {
      displaySubtitle =
          'R\$ ${card.amount!.toStringAsFixed(2).replaceAll('.', ',')}';
    } else if (card.cardType.value == 'fat_moto' && card.clientName != null) {
      displaySubtitle = card.clientName;
    } else if (card.cardType.value == 'emplacamento' &&
        card.clientName != null) {
      displaySubtitle = card.clientName;
    }

    final hoverMessage = '''
${card.title}
${displaySubtitle != null ? '💳 $displaySubtitle' : ''}

📝 ${card.description ?? "Sem descrição."}
👤 Por: ${card.requestedByName?.split(' ').first ?? '---'}
⚙️ Resp: ${card.assignedToName?.split(' ').first ?? '---'}
'''
        .trim();

    return Tooltip(
      message: hoverMessage,
      waitDuration: const Duration(milliseconds: 600),
      textStyle:
          const TextStyle(fontSize: 12, color: Colors.white, height: 1.4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.black87, borderRadius: BorderRadius.circular(8)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: slaExceeded
              ? Colors.red.withValues(alpha: 0.05)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: slaExceeded
                  ? Colors.red
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: slaExceeded ? 2 : (card.isPinned ? 2 : 1)),
          boxShadow: [
            if (slaExceeded)
              BoxShadow(
                  color: Colors.red.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 1)
            else
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
                border: Border(
                    left: BorderSide(
                        color: slaExceeded ? Colors.red : priorityColor,
                        width: 4.0))),
            child: Material(
              color: Colors.transparent,
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
                  final isSelecting =
                      ref.read(workflowProvider(channelId)).isSelectionMode;
                  if (isSelecting) {
                    final currentUser =
                        ref.read(currentUserProvider).valueOrNull;
                    final canMove = currentUser != null &&
                        card.requestedBy != currentUser.id &&
                        (AppPermissions.canOperateWorkflowCard(
                                currentUser.roleLevel) ||
                            card.assignedTo == currentUser.id);
                    if (canMove) {
                      _showMoveMenu(context, ref);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Acesso Negado: Apenas membros responsáveis pelo card ou gestores podem movê-lo.')));
                    }
                  } else {
                    // First long-press enters selection mode
                    ref
                        .read(workflowProvider(channelId).notifier)
                        .toggleCardSelection(card.id);
                  }
                },
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (card.isPinned)
                                Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(Icons.push_pin,
                                        size: 14,
                                        color: theme.colorScheme.primary)),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(card.priority.label.toUpperCase(),
                                    style: TextStyle(
                                        color: theme
                                            .colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.8),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2)),
                              ),
                              const Spacer(),
                              if (card.cardType.value != 'generic' &&
                                  card.cardType.value != 'aviso')
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Icon(_getCardTypeIcon(card.cardType),
                                      size: 14,
                                      color: theme.colorScheme.outline),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (slaExceeded)
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
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
                          Text(card.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  height: 1.2),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          if (displaySubtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(displaySubtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildInfoChip(
                                  icon: Icons.access_time,
                                  label: _formatDate(card.createdAt),
                                  theme: theme),
                              const SizedBox(width: 6),
                              _buildStatusAgeChip(card.updatedAt, theme),
                              if (card.requestedByName != null &&
                                  card.requestedByName!.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                _buildInfoChip(
                                    icon: Icons.record_voice_over_outlined,
                                    label:
                                        card.requestedByName!.split(' ').first,
                                    theme: theme),
                              ],
                              if (card.assignedToName != null &&
                                  card.assignedToName!.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                _buildInfoChip(
                                    icon: Icons.engineering_outlined,
                                    label:
                                        card.assignedToName!.split(' ').first,
                                    theme: theme),
                              ],
                              // Badge de vencimento para Contas a Pagar
                              if (card.dueDate != null) ...[
                                const SizedBox(width: 6),
                                _buildDueDateChip(card.dueDate!, theme,
                                    isClosed: ref.watch(
                                        workflowProvider(channelId).select(
                                            (s) => s.isClosedStatus(card.status)))),
                              ],
                              const Spacer(),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Checkbox overlay for selection mode
                    if (ref.watch(workflowProvider(channelId)
                        .select((s) => s.selectedCardIds.contains(card.id))))
                      Positioned(
                        top: 6,
                        right: 6,
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
                          child: const Icon(Icons.check,
                              size: 14, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getCardTypeIcon(WorkflowCardType type) {
    switch (type.value) {
      case 'conta_pagar':
        return Icons.payments_outlined;
      case 'fat_moto':
        return Icons.fact_check_outlined;
      case 'emplacamento':
        return Icons.description_outlined;
      case 'faturamento_os':
        return Icons.receipt_long_outlined;
      case 'aviso':
        return Icons.campaign_outlined;
      default:
        return Icons.assignment_outlined;
    }
  }

  Widget _buildInfoChip(
      {required IconData icon,
      required String label,
      required ThemeData theme}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline, fontSize: 11)),
      ],
    );
  }

  String _formatDate(DateTime date) => formatWorkflowDate(date);

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

  Widget _buildStatusAgeChip(DateTime updatedAt, ThemeData theme) {
    final severity = statusAgeSeverity(updatedAt);
    final ageText = formatStatusAge(updatedAt);
    final Color color;
    switch (severity) {
      case 2:
        color = const Color(0xFFEF4444); // vermelho
        break;
      case 1:
        color = const Color(0xFFF97316); // laranja
        break;
      default:
        color = theme.colorScheme.outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: severity > 0
            ? Border.all(color: color.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(severity > 0 ? Icons.hourglass_top : Icons.schedule,
              size: 10, color: color),
          const SizedBox(width: 3),
          Text(ageText,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: severity > 0 ? FontWeight.w700 : FontWeight.w500,
                  color: color)),
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

  void _showMoveMenu(BuildContext context, WidgetRef ref) {
    final statusConfig = ref.read(workflowProvider(channelId)).statusConfig;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Mover para...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ...statusConfig.map((s) {
              if (s.status == card.status) return const SizedBox.shrink();
              return ListTile(
                leading:
                    Icon(Icons.circle, color: Color(s.colorValue), size: 12),
                title: Text(s.status),
                onTap: () {
                  Navigator.pop(ctx);
                  final previousStatus = card.status;
                  try {
                    ref
                        .read(workflowProvider(channelId).notifier)
                        .updateCardStatus(card.id, s.status);
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Card movido para "${s.status}"',
                          style: const TextStyle(color: Colors.white)),
                      backgroundColor: Colors.green.shade600,
                      action: SnackBarAction(
                        label: 'Desfazer',
                        textColor: Colors.white,
                        onPressed: () {
                          ref
                              .read(workflowProvider(channelId).notifier)
                              .updateCardStatus(card.id, previousStatus);
                        },
                      ),
                      duration: const Duration(seconds: 2),
                    ));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Falha: ${e.toString().replaceFirst('Exception: ', '')}')),
                    );
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
