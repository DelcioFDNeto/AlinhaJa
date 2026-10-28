import 'package:flutter/material.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/support/providers/support_provider.dart';

class TicketChatScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const TicketChatScreen({super.key, required this.ticketId});

  @override
  ConsumerState<TicketChatScreen> createState() => _TicketChatScreenState();
}

class _TicketChatScreenState extends ConsumerState<TicketChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    _msgCtrl.clear();
    try {
      await SupportService.sendMessage(widget.ticketId, text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgsAsync = ref.watch(ticketMessagesProvider(widget.ticketId));
    final ticketAsync = ref.watch(ticketDetailProvider(widget.ticketId));
    final theme = Theme.of(context);
    final currentUser = ref.watch(currentUserProvider).value;
    final myId = currentUser?.id;
    final isSuperAdmin = currentUser?.roleLevel == AppPermissions.superAdmin;

    final ticket = ticketAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title:
            Text(ticket?.title ?? 'Chamado', overflow: TextOverflow.ellipsis),
        actions: [
          if (isSuperAdmin && ticket != null) ...[
            if (ticket.assignedTo == null)
              IconButton(
                tooltip: 'Assumir Chamado',
                icon: const Icon(Icons.back_hand_rounded, color: Colors.orange),
                onPressed: () async {
                  await SupportService.assignTicket(widget.ticketId, myId!);
                  ref.invalidate(ticketDetailProvider(widget.ticketId));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Chamado atribuído a você.')));
                },
              ),
            if (ticket.status != 'resolved' && ticket.status != 'cancelled')
              IconButton(
                tooltip: 'Marcar como Resolvido',
                icon: const Icon(Icons.check_circle_outline,
                    color: AppConstants.success),
                onPressed: () async {
                  await SupportService.updateTicketStatus(
                      widget.ticketId, 'resolved');
                  ref.invalidate(ticketDetailProvider(widget.ticketId));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chamado resolvido.')));
                },
              ),
            PopupMenuButton<String>(
              tooltip: 'Mais ações',
              onSelected: (value) async {
                await SupportService.updateTicketStatus(widget.ticketId, value);
                ref.invalidate(ticketDetailProvider(widget.ticketId));
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'pending_vendor',
                    child: Text('Pendente Fornecedor')),
                const PopupMenuItem(
                    value: 'cancelled', child: Text('Cancelar Chamado')),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // ── Header com infos do ticket ──
          if (ticket != null) _TicketInfoHeader(ticket: ticket),

          // ── Lista de mensagens ──
          Expanded(
            child: msgsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (messages) {
                // Auto-scroll
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_outlined,
                            size: 48,
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                            'Nenhuma mensagem ainda.\nEnvie uma mensagem para iniciar a conversa.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == myId;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isMe) ...[
                            CircleAvatar(
                              radius: 14,
                              backgroundImage: msg.sender?.avatarUrl != null
                                  ? CachedNetworkImageProvider(
                                      msg.sender!.avatarUrl!, maxWidth: 320)
                                  : null,
                              child: msg.sender?.avatarUrl == null
                                  ? Text(
                                      msg.sender?.fullName[0].toUpperCase() ??
                                          '?',
                                      style: const TextStyle(fontSize: 10))
                                  : null,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 4, bottom: 2),
                                    child: Text(msg.sender?.fullName ?? 'TI',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.primary)),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme
                                            .surfaceContainerHighest,
                                    borderRadius:
                                        BorderRadius.circular(16).copyWith(
                                      bottomRight: isMe
                                          ? const Radius.circular(2)
                                          : const Radius.circular(16),
                                      bottomLeft: !isMe
                                          ? const Radius.circular(2)
                                          : const Radius.circular(16),
                                    ),
                                  ),
                                  child: Text(msg.content,
                                      style: TextStyle(
                                          color: isMe
                                              ? theme.colorScheme.onPrimary
                                              : theme
                                                  .colorScheme.onSurfaceVariant,
                                          fontSize: 14)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: 2, left: 4, right: 4),
                                  child: Text(timeAgo(msg.createdAt),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: theme.colorScheme.outline)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // ── Barra de Input (Apenas Super Admin) ──
          if (isSuperAdmin)
            Container(
              padding: const EdgeInsets.all(8)
                  .copyWith(bottom: 8 + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                    top: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.2))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Escreva uma mensagem...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    radius: 22,
                    child: IconButton(
                        icon: Icon(Icons.send_rounded,
                            color: theme.colorScheme.onPrimary, size: 20),
                        onPressed: _send),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16)
                  .copyWith(bottom: 16 + MediaQuery.paddingOf(context).bottom),
              color: theme.colorScheme.surface,
              child: Center(
                child: Text(
                  'Apenas Super Administradores podem enviar mensagens neste chamado.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Widget de Header com informações do Ticket ─────────────────────────────

class _TicketInfoHeader extends StatelessWidget {
  final dynamic ticket;
  const _TicketInfoHeader({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(ticket.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
            bottom: BorderSide(
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status + Categoria + Prioridade
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _MiniChip(
                  label: translateStatus(ticket.status), color: statusColor),
              _MiniChip(
                  label: translateCategory(ticket.category),
                  color: theme.colorScheme.secondary),
              _MiniChip(
                  label: translatePriority(ticket.priority),
                  color: _priorityColor(ticket.priority)),
            ],
          ),
          const SizedBox(height: 8),
          Text(ticket.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.schedule_rounded,
                  size: 12, color: theme.colorScheme.outline),
              const SizedBox(width: 4),
              Text('Aberto ${timeAgo(ticket.createdAt)}',
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.outline)),
              if (ticket.assignee != null) ...[
                const SizedBox(width: 12),
                Icon(Icons.engineering_rounded,
                    size: 12, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(ticket.assignee!.fullName,
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis)),
              ],
            ],
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
