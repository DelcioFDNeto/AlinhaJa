import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/features/support/providers/support_provider.dart';
import 'package:alinha_ja/features/support/models/support_ticket_model.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';

class SupportDashboardScreen extends ConsumerWidget {
  const SupportDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Chamados'),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/support/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo Chamado'),
      ),
      body: const ResponsiveWidthContainer(child: MyTicketsView()),
    );
  }
}

/// Lista reativa dos chamados do próprio usuário. Reutilizada pela tela cheia
/// [SupportDashboardScreen] e pela aba "Meus Chamados" da Central de Ajuda.
class MyTicketsView extends ConsumerWidget {
  const MyTicketsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(myTicketsProvider);
    final theme = Theme.of(context);

    return ticketsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 12),
                  Text('Erro ao carregar chamados',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('$e',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          data: (tickets) {
            if (tickets.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.support_agent_rounded,
                        size: 72,
                        color:
                            theme.colorScheme.outline.withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    Text('Nenhum chamado aberto',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: theme.colorScheme.outline)),
                    const SizedBox(height: 4),
                    Text(
                        'Toque no botão abaixo para registrar uma solicitação.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 80, top: 8),
              itemCount: tickets.length,
              itemBuilder: (context, index) {
                final ticket = tickets[index];
                return _TicketCard(ticket: ticket);
              },
            );
          },
        );
  }
}

class _TicketCard extends StatelessWidget {
  final SupportTicketModel ticket;
  const _TicketCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final statusColor = _statusColor(ticket.status);
    final priorityColor = _priorityColor(ticket.priority);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/support/ticket/${ticket.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha 1: Título + tempo
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(ticket.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Text(timeAgo(ticket.createdAt),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),

              const SizedBox(height: 6),
              Text(ticket.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),

              const SizedBox(height: 12),
              // Linha 3: Tags
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _StatusChip(
                      label: translateStatus(ticket.status),
                      color: statusColor),
                  _StatusChip(
                      label: translateCategory(ticket.category),
                      color: theme.colorScheme.secondary),
                  _StatusChip(
                      label: translatePriority(ticket.priority),
                      color: priorityColor),
                ],
              ),

              // Responsável
              if (ticket.assignee != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Atendido por ${ticket.assignee!.fullName}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600),
                    ),
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

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'new':
      return Colors.blue;
    case 'in_progress':
      return Colors.orange;
    case 'pending_vendor':
      return Colors.purple;
    case 'resolved':
      return AppConstants.success;
    case 'cancelled':
      return AppConstants.danger;
    default:
      return Colors.grey;
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
