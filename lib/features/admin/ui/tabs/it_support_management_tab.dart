import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/features/support/providers/support_provider.dart';
import 'package:alinha_ja/features/support/models/support_ticket_model.dart';

class ItSupportManagementTab extends ConsumerWidget {
  const ItSupportManagementTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(adminTicketsProvider);
    final theme = Theme.of(context);

    return ticketsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro: $e')),
      data: (tickets) {
        if (tickets.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded,
                    size: 64,
                    color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('Sem chamados pendentes!',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 4),
                Text('Todos os chamados estão resolvidos.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          );
        }

        // Agrupar por status
        final newTickets = tickets.where((t) => t.status == 'new').toList();
        final progressTickets =
            tickets.where((t) => t.status == 'in_progress').toList();
        final pendingTickets =
            tickets.where((t) => t.status == 'pending_vendor').toList();
        final resolvedTickets = tickets
            .where((t) => t.status == 'resolved' || t.status == 'cancelled')
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Stats Cards ──
            _StatsRow(
              newCount: newTickets.length,
              progressCount: progressTickets.length,
              pendingCount: pendingTickets.length,
              resolvedCount: resolvedTickets.length,
            ),
            const SizedBox(height: 20),

            if (newTickets.isNotEmpty) ...[
              _SectionHeader(
                  '🆕 NOVOS CHAMADOS', newTickets.length, Colors.blue),
              ...newTickets.map((t) => _AdminTicketCard(ticket: t)),
              const SizedBox(height: 16),
            ],

            if (progressTickets.isNotEmpty) ...[
              _SectionHeader(
                  '🔧 EM ATENDIMENTO', progressTickets.length, Colors.orange),
              ...progressTickets.map((t) => _AdminTicketCard(ticket: t)),
              const SizedBox(height: 16),
            ],

            if (pendingTickets.isNotEmpty) ...[
              _SectionHeader('⏳ PENDENTE FORNECEDOR', pendingTickets.length,
                  Colors.purple),
              ...pendingTickets.map((t) => _AdminTicketCard(ticket: t)),
              const SizedBox(height: 16),
            ],

            if (resolvedTickets.isNotEmpty) ...[
              _SectionHeader(
                  '✅ CONCLUÍDOS', resolvedTickets.length, AppConstants.success),
              ...resolvedTickets.map((t) => _AdminTicketCard(ticket: t)),
            ],
          ],
        );
      },
    );
  }
}

// ─── Stats Row ──────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int newCount;
  final int progressCount;
  final int pendingCount;
  final int resolvedCount;

  const _StatsRow({
    required this.newCount,
    required this.progressCount,
    required this.pendingCount,
    required this.resolvedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(
            label: 'Novos',
            count: newCount,
            color: Colors.blue,
            icon: Icons.fiber_new_rounded),
        const SizedBox(width: 8),
        _StatCard(
            label: 'Andamento',
            count: progressCount,
            color: Colors.orange,
            icon: Icons.build_circle_rounded),
        const SizedBox(width: 8),
        _StatCard(
            label: 'Pendentes',
            count: pendingCount,
            color: Colors.purple,
            icon: Icons.hourglass_top_rounded),
        const SizedBox(width: 8),
        _StatCard(
            label: 'Resolvidos',
            count: resolvedCount,
            color: AppConstants.success,
            icon: Icons.check_circle_rounded),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _StatCard(
      {required this.label,
      required this.count,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text('$count',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionHeader(this.title, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: color,
                  letterSpacing: 0.5)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(10)),
            child: Text('$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─── Ticket Card (Admin) ────────────────────────────────────────────────────

class _AdminTicketCard extends StatelessWidget {
  final SupportTicketModel ticket;
  const _AdminTicketCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priorityColor = _priorityColor(ticket.priority);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.12)),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/support/ticket/${ticket.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha 1: Título + tempo
              Row(
                children: [
                  // Indicador de prioridade
                  Container(
                    width: 4,
                    height: 32,
                    decoration: BoxDecoration(
                        color: priorityColor,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ticket.title,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(ticket.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(timeAgo(ticket.createdAt),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),

              const SizedBox(height: 10),

              // Linha 2: Tags + Info
              Row(
                children: [
                  _MiniChip(
                      label: translateCategory(ticket.category),
                      color: theme.colorScheme.secondary),
                  const SizedBox(width: 6),
                  _MiniChip(
                      label: translatePriority(ticket.priority),
                      color: priorityColor),
                  const Spacer(),
                  Icon(Icons.person_outline,
                      size: 12, color: theme.colorScheme.outline),
                  const SizedBox(width: 3),
                  Text(
                    ticket.creator?.fullName ?? 'Desconhecido',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),

              if (ticket.assignedTo != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.engineering_rounded,
                        size: 12, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text('Responsável: ${ticket.assignee?.fullName ?? '—'}',
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

Color _priorityColor(String priority) {
  switch (priority) {
    case 'low':
      return Colors.grey;
    case 'medium':
      return Colors.blue;
    case 'high':
      return Colors.orange;
    case 'urgent':
      return AppConstants.danger;
    default:
      return Colors.grey;
  }
}
