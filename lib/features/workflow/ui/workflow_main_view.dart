import 'package:alinha_ja/core/services/push_notification_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:alinha_ja/core/models/message_receipts.dart';
import 'package:alinha_ja/core/services/media_url_resolver.dart';
import 'package:alinha_ja/core/providers/message_selection_provider.dart';
import 'package:alinha_ja/core/widgets/message_info_sheet.dart';
import 'package:alinha_ja/core/widgets/signed_network_image.dart';
import 'package:alinha_ja/core/services/message_batch_actions.dart';
import 'package:alinha_ja/core/services/message_forward_service.dart';
import 'package:alinha_ja/core/services/message_star_service.dart';
import 'package:alinha_ja/core/widgets/forward_picker_sheet.dart';
import 'package:alinha_ja/core/widgets/selection_action_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/workflow/ui/create_card_sheet.dart';
import 'package:alinha_ja/features/workflow/ui/workflow_board_view.dart';
import 'package:alinha_ja/features/workflow/ui/workflow_list_view.dart';
import 'package:alinha_ja/features/workflow/ui/workflow_compact_view.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/ui/composer/conversation_composer.dart';
import 'package:alinha_ja/features/channels/ui/widgets/channel_composer_delegate.dart';
import 'package:alinha_ja/features/workflow/providers/workflow_provider.dart';
import 'package:alinha_ja/features/channels/providers/active_channel_provider.dart';
import 'package:alinha_ja/features/channels/providers/channel_info_provider.dart';
import 'package:alinha_ja/features/channels/models/channel_message_model.dart';
import 'package:alinha_ja/features/channels/ui/widgets/channel_message_bubble.dart';
import 'package:alinha_ja/features/channels/ui/widgets/channel_notification_selector.dart';
import 'package:alinha_ja/features/channels/ui/widgets/channel_reply_quote.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/features/workflow/ui/widgets/card_details_sheet.dart';
import 'package:alinha_ja/features/workflow/models/workflow_helpers.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/core/extensions.dart';
import 'package:alinha_ja/features/workflow/ui/widgets/workflow_dashboard_sheet.dart';
import 'package:alinha_ja/core/providers/desktop_selection_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class WorkflowMainView extends ConsumerStatefulWidget {
  final String channelId;
  final String channelName;

  const WorkflowMainView({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  ConsumerState<WorkflowMainView> createState() => _WorkflowMainViewState();
}

class _WorkflowMainViewState extends ConsumerState<WorkflowMainView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription? _notifSubscription;

  /// Monta o composer do canal com as permissões do estado atual.
  Widget _buildChannelComposer(ChannelState channelState) {
    final notifier = ref.read(
        activeChannelProvider(ChannelArgs(channelId: widget.channelId))
            .notifier);
    final members =
        ref.watch(channelInfoProvider(widget.channelId)).channelMembers;

    return ConversationComposer(
      delegate: ChannelComposerDelegate(
        notifier: notifier,
        channelName: widget.channelName,
        members: members,
        replyingTo: channelState.replyingTo,
        locked: !channelState.canPost,
        canAnnounce: ref.watch(canPublishAnnouncementProvider),
      ),
    );
  }

  Color _getChannelColor(String channelName) {
    final name = channelName.toUpperCase();
    if (name.contains('CONTAS A PAGAR')) return const Color(0xFF2E7D32);
    if (name.contains('FAT MOTO') ||
        name.contains('PEDIDO') ||
        name.contains('LIBERAÇÃO')) {
      return const Color(0xFF7B1FA2);
    }
    if (name.contains('EMPLACAMENTO') ||
        name.contains('DOCUMENTAÇÃO') ||
        name.contains('CADASTRO')) {
      return const Color(0xFF1565C0);
    }
    if (name.contains('FATURAMENTO')) return const Color(0xFFE65100);
    if (name.contains('AVISOS')) return const Color(0xFFC62828);
    return const Color(0xFF616161);
  }

  IconData _getChannelIcon(String channelName) {
    final name = channelName.toUpperCase();
    if (name.contains('CONTAS A PAGAR')) return Icons.payments_outlined;
    if (name.contains('FAT MOTO') ||
        name.contains('PEDIDO') ||
        name.contains('LIBERAÇÃO')) {
      return Icons.fact_check_outlined;
    }
    if (name.contains('EMPLACAMENTO') ||
        name.contains('DOCUMENTAÇÃO') ||
        name.contains('CADASTRO')) {
      return Icons.description_outlined;
    }
    if (name.contains('FATURAMENTO')) return Icons.receipt_long_outlined;
    if (name.contains('AVISOS')) return Icons.campaign_outlined;
    return Icons.workspaces_rounded;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);
    // Abrir o canal lê as mensagens: tira a notificação dele da bandeja.
    PushNotificationService.dismissConversationNotification(widget.channelId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifSubscription = ref
          .read(workflowProvider(widget.channelId).notifier)
          .notificationStream
          .listen((notif) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notif.title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color:
                          notif.isUrgent ? Colors.red[200] : Colors.blue[200])),
              Text(notif.message),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.onSurface,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ));
      });
    });
  }

  void _handleTabSelection() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _notifSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workflowState = ref.watch(workflowProvider(widget.channelId));
    final channelState = ref.watch(
      activeChannelProvider(ChannelArgs(channelId: widget.channelId)),
    );
    final channelColor = _getChannelColor(widget.channelName);
    final inProgressCount = workflowState.cards.length -
        workflowState.cards
            .where((c) => workflowState.statusConfig
                .where((s) => s.isFinal)
                .map((s) => s.status)
                .contains(c.status))
            .length;

    // Calcular Progresso
    final totalCards = workflowState.cards.length;
    final finalStatuses = workflowState.statusConfig
        .where((s) => s.isFinal)
        .map((s) => s.status)
        .toList();
    final doneCount = workflowState.cards
        .where((c) => finalStatuses.contains(c.status))
        .length;
    final progress = totalCards == 0 ? 0.0 : doneCount / totalCards;

    final hasActiveFilters = workflowState.filterStatus != null ||
        workflowState.filterPriority != null ||
        workflowState.filterAssignedTo != null ||
        workflowState.filterMyCards == true;

    // Selection mode AppBar (cards do workflow)
    if (workflowState.isSelectionMode && _tabController.index == 1) {
      return _buildSelectionScaffold(
          context, theme, workflowState, channelState);
    }

    // Seleção múltipla de mensagens (aba de conversa) — barra própria, para
    // não se confundir com a seleção de cards acima.
    final msgSelection = ref.watch(messageSelectionProvider(widget.channelId));

    return Scaffold(
      appBar: msgSelection.active
          ? SelectionActionBar(
              count: msgSelection.count,
              onClose: () => ref
                  .read(messageSelectionProvider(widget.channelId).notifier)
                  .clear(),
              onForward: () =>
                  _forwardSelectedMessages(msgSelection.ids, channelState),
              onCopy: () =>
                  _copySelectedMessages(msgSelection.ids, channelState),
              onStar: () => _starSelectedMessages(msgSelection.ids),
              onDelete: _canDeleteSelectedMessages(msgSelection.ids)
                  ? () => _deleteSelectedMessages(msgSelection.ids)
                  : null,
              deleteDisabledReason: _canDeleteSelectedMessages(msgSelection.ids)
                  ? null
                  : 'Só é possível excluir as suas próprias mensagens',
            )
          : AppBar(
              toolbarHeight: 96,
              title: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: channelColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: channelColor.withValues(alpha: 0.2),
                            width: 1),
                      ),
                      child: Icon(_getChannelIcon(widget.channelName),
                          color: channelColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.channelName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3)),
                          const SizedBox(height: 2),
                          Text(
                            '$doneCount finalizados  •  $inProgressCount em andamento',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.8),
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 4,
                                    backgroundColor: theme
                                        .colorScheme.surfaceContainerHighest,
                                    color: const Color(0xFF10B981),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(progress * 100).toInt()}%',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
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
              elevation: 0,
              backgroundColor: theme.colorScheme.surface,
              bottom: (channelState.metadata?['workflow_enabled'] as bool? ??
                      false)
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(48),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          border: Border(
                              bottom: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.2))),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          tabs: const [
                            Tab(
                                icon: Icon(Icons.chat_bubble_outline, size: 20),
                                text: 'Conversa'),
                            Tab(
                                icon: Icon(Icons.dashboard_customize_outlined,
                                    size: 20),
                                text: 'Workflow'),
                            Tab(
                                icon: Icon(Icons.cancel_outlined, size: 20),
                                text: 'Cancelados'),
                          ],
                          labelStyle:
                              const TextStyle(fontWeight: FontWeight.bold),
                          unselectedLabelStyle:
                              const TextStyle(fontWeight: FontWeight.w500),
                          labelColor: theme.colorScheme.primary,
                          unselectedLabelColor: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                          indicator: UnderlineTabIndicator(
                            borderSide: BorderSide(
                                width: 3.0, color: theme.colorScheme.primary),
                            borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(4),
                                topRight: Radius.circular(4)),
                          ),
                        ),
                      ),
                    )
                  : null,
              actions: [
                ChannelNotificationButton(channelId: widget.channelId),
                IconButton(
                  icon: const Icon(Icons.videocam_outlined),
                  tooltip: 'Nova Reunião',
                  onPressed: () => _showCreateMeetingRoomDialog(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Informações',
                  onPressed: () {
                    final metadata = channelState.metadata;
                    context.push('/channel/${widget.channelId}/info', extra: {
                      'channelName': widget.channelName,
                      'metadata': metadata,
                    });
                  },
                ),
                if (channelState.canGovernChannel ||
                    (channelState.currentUserRoleLevel == 'admin') ||
                    (supabase.auth.currentUser?.userMetadata?['role'] ==
                        'admin')) ...[
                  IconButton(
                    icon: const Icon(Icons.dashboard_outlined),
                    tooltip: 'Dashboard de Workflow',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) =>
                            WorkflowDashboardSheet(channelId: widget.channelId),
                      );
                    },
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Ações de TI',
                    onSelected: (value) async {
                      if (value == 'archive') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Arquivar Workspace?'),
                            content: const Text(
                                'Todos os membros serão removidos e o workspace inativado. As mensagens e cards continuarão no banco para auditoria futura.\n\nEsta ação não pode ser desfeita pelo app.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancelar')),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Sim, Arquivar',
                                    style: TextStyle(color: Colors.orange)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          if (!context.mounted) return;
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (c) => const Center(
                                child: CircularProgressIndicator()),
                          );
                          try {
                            await ref
                                .read(activeChannelProvider(ChannelArgs(
                                        channelId: widget.channelId))
                                    .notifier)
                                .archiveChannel();

                            final selection =
                                ref.read(desktopSelectionProvider);
                            if (selection != null &&
                                selection.id == widget.channelId) {
                              ref
                                  .read(desktopSelectionProvider.notifier)
                                  .state = null;
                            }

                            if (context.mounted) {
                              Navigator.of(context).pop(); // loading
                              context.go('/chats');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      backgroundColor: Colors.red,
                                      content: Text('Erro ao arquivar: $e')));
                            }
                          }
                        }
                      } else if (value == 'delete') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Excluir Totalmente?'),
                            content: const Text(
                                'Atenção Operador de TI: Esta é uma EXCLUSÃO FÍSICA.\n\nO workspace, todas as conversas, threads, anexos e cards de workflow serão apagados em cascata do banco de dados para sempre.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancelar')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Excluir p/ Sempre'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          if (!context.mounted) return;
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (c) => const Center(
                                child: CircularProgressIndicator()),
                          );
                          try {
                            await ref
                                .read(activeChannelProvider(ChannelArgs(
                                        channelId: widget.channelId))
                                    .notifier)
                                .deleteChannel();

                            final selection =
                                ref.read(desktopSelectionProvider);
                            if (selection != null &&
                                selection.id == widget.channelId) {
                              ref
                                  .read(desktopSelectionProvider.notifier)
                                  .state = null;
                            }

                            if (context.mounted) {
                              Navigator.of(context).pop(); // loading
                              context.go('/chats');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      backgroundColor: Colors.red,
                                      content: Text('Erro ao excluir: $e')));
                            }
                          }
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'archive',
                        child: Row(
                          children: [
                            Icon(Icons.archive, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('Arquivar (Limbo)',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_forever, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Destruir Workspace',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (_tabController.index == 1 &&
                    (channelState.metadata?['workflow_enabled'] as bool? ??
                        false))
                  PopupMenuButton<String>(
                    icon: Icon(hasActiveFilters
                        ? Icons.filter_alt
                        : Icons.view_agenda_outlined),
                    tooltip: 'Visualização',
                    onSelected: (mode) => ref
                        .read(workflowProvider(widget.channelId).notifier)
                        .setViewMode(mode),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'board',
                        child: Row(children: [
                          Icon(Icons.view_kanban_outlined,
                              color: workflowState.viewMode == 'board'
                                  ? theme.colorScheme.primary
                                  : null),
                          const SizedBox(width: 12),
                          Text('Board',
                              style: TextStyle(
                                  color: workflowState.viewMode == 'board'
                                      ? theme.colorScheme.primary
                                      : null)),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'list',
                        child: Row(children: [
                          Icon(Icons.view_list_outlined,
                              color: workflowState.viewMode == 'list'
                                  ? theme.colorScheme.primary
                                  : null),
                          const SizedBox(width: 12),
                          Text('Lista',
                              style: TextStyle(
                                  color: workflowState.viewMode == 'list'
                                      ? theme.colorScheme.primary
                                      : null)),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'compact',
                        child: Row(children: [
                          Icon(Icons.view_headline_outlined,
                              color: workflowState.viewMode == 'compact'
                                  ? theme.colorScheme.primary
                                  : null),
                          const SizedBox(width: 12),
                          Text('Compacto',
                              style: TextStyle(
                                  color: workflowState.viewMode == 'compact'
                                      ? theme.colorScheme.primary
                                      : null)),
                        ]),
                      ),
                    ],
                  ),
                if (_tabController.index == 1 && hasActiveFilters)
                  IconButton(
                    icon: const Icon(Icons.filter_alt_off),
                    tooltip: 'Limpar Filtros',
                    onPressed: () => ref
                        .read(workflowProvider(widget.channelId).notifier)
                        .clearFilters(),
                  )
                else if (_tabController.index == 1)
                  IconButton(
                      icon: const Icon(Icons.filter_list),
                      tooltip: 'Filtrar',
                      onPressed: () => _showFilterSheet(context)),
                if (_tabController.index == 1)
                  IconButton(
                    icon: Icon(
                      workflowState.showArchived
                          ? Icons.inventory_2
                          : Icons.inventory_2_outlined,
                      color: workflowState.showArchived ? Colors.orange : null,
                    ),
                    tooltip: workflowState.showArchived
                        ? 'Ver Cards Ativos'
                        : 'Ver Histórico (Arquivados)',
                    onPressed: () => ref
                        .read(workflowProvider(widget.channelId).notifier)
                        .toggleArchived(),
                  ),
              ],
            ),
      body: (channelState.metadata?['workflow_enabled'] as bool? ?? false)
          ? Column(
              children: [
                if (_tabController.index == 1 && workflowState.showArchived)
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.orange.withValues(alpha: 0.15),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2,
                            color: Colors.orange, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Visualizando cards arquivados (histórico)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => ref
                              .read(workflowProvider(widget.channelId).notifier)
                              .toggleArchived(),
                          child: const Text('Voltar',
                              style: TextStyle(color: Colors.orange)),
                        ),
                      ],
                    ),
                  ),
                if (_tabController.index == 1)
                  _buildFilterBar(context, ref, workflowState),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildConversaView(theme, channelState),
                      workflowState.viewMode == 'board'
                          ? WorkflowBoardView(
                              channelId: widget.channelId,
                              channelName: widget.channelName)
                          : workflowState.viewMode == 'compact'
                              ? WorkflowCompactView(
                                  channelId: widget.channelId,
                                  channelName: widget.channelName)
                              : WorkflowListView(
                                  channelId: widget.channelId,
                                  channelName: widget.channelName),
                      _buildCancelledTab(context, theme, workflowState),
                    ],
                  ),
                ),
              ],
            )
          : _buildConversaView(theme, channelState),
      floatingActionButton: _tabController.index == 1 &&
              !workflowState.showArchived &&
              (channelState.metadata?['workflow_enabled'] as bool? ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateCardSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Novo Card'),
            )
          : null,
    );
  }

  Widget _buildSelectionScaffold(BuildContext context, ThemeData theme,
      WorkflowState workflowState, dynamic channelState) {
    final count = workflowState.selectedCardIds.length;
    final notifier = ref.read(workflowProvider(widget.channelId).notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => notifier.clearSelection(),
        ),
        title: Text('$count selecionado${count > 1 ? 's' : ''}',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: 'Selecionar Todos',
            onPressed: () => notifier.selectAllVisible(),
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move_outlined),
            tooltip: 'Mover para...',
            onPressed: () {
              final statusConfig = workflowState.statusConfig;
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16))),
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Mover $count cards para...',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      ...statusConfig.map((s) => ListTile(
                            leading: Icon(Icons.circle,
                                color: Color(s.colorValue), size: 12),
                            title: Text(s.status),
                            onTap: () {
                              Navigator.pop(ctx);
                              notifier.bulkUpdateStatus(s.status);
                            },
                          )),
                    ],
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Arquivar Selecionados',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Arquivar cards?'),
                  content: Text(
                      'Deseja arquivar $count card${count > 1 ? 's' : ''}?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Arquivar',
                          style: TextStyle(color: Colors.orange)),
                    ),
                  ],
                ),
              );
              if (confirm == true) notifier.bulkArchive();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_tabController.index == 1)
            _buildFilterBar(context, ref, workflowState),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildConversaView(theme, channelState),
                workflowState.viewMode == 'board'
                    ? WorkflowBoardView(
                        channelId: widget.channelId,
                        channelName: widget.channelName)
                    : workflowState.viewMode == 'compact'
                        ? WorkflowCompactView(
                            channelId: widget.channelId,
                            channelName: widget.channelName)
                        : WorkflowListView(
                            channelId: widget.channelId,
                            channelName: widget.channelName),
                _buildCancelledTab(context, theme, workflowState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateMeetingRoomDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Criar Sala de Reunião'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nome da Reunião',
                hintText: 'Ex: Reunião de Equipe',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
                hintText: 'Pauta da reunião',
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Digite um nome para a reunião')),
                );
                return;
              }

              Navigator.pop(ctx);

              final currentUser = supabase.auth.currentUser;
              if (currentUser == null) return;
              final fullName =
                  currentUser.userMetadata?['full_name'] ?? 'Usuário';

              try {
                final roomId = await CallService.instance.createMeetingRoom(
                  name: nameController.text.trim(),
                  chatId: widget.channelId,
                  description: descController.text.trim(),
                );

                if (roomId != null && context.mounted) {
                  // Host inicia a reunião - entra primeiro para validar a sala
                  await CallService.instance.joinMeetingRoom(
                    roomId: roomId,
                    userName: fullName,
                  );

                  // Após host entrar, envia card com descrição para os membros
                  final descText = descController.text.trim().isNotEmpty
                      ? '\n\n📝 Descrição: ${descController.text.trim()}'
                      : '';
                  await ref
                      .read(activeChannelProvider(
                              ChannelArgs(channelId: widget.channelId))
                          .notifier)
                      .sendMessage(
                          '🚀 Reunião Iniciada: ${nameController.text.trim()}$descText',
                          metadata: {
                        'type': 'meeting',
                        'room_id': roomId,
                      });
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro ao criar reunião: $e')),
                  );
                }
              }
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );
  }

  Widget _buildConversaView(ThemeData theme, ChannelState channelState) {
    final msgSelection = ref.watch(messageSelectionProvider(widget.channelId));

    if (channelState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (channelState.messages.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('Nenhuma mensagem ainda',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 8),
                  Text('Envie uma mensagem para iniciar a conversa',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            ),
          ),
          _buildChannelComposer(channelState),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(16),
            itemCount: channelState.messages.length +
                (channelState.hasMoreMessages ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == channelState.messages.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: channelState.isLoadingMore
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton.icon(
                            onPressed: () => ref
                                .read(activeChannelProvider(
                                        ChannelArgs(channelId: widget.channelId))
                                    .notifier)
                                .loadMoreMessages(),
                            icon: const Icon(Icons.history, size: 16),
                            label: const Text('Carregar mensagens anteriores'),
                          ),
                  ),
                );
              }

              final msg = channelState.messages[index];
              final nextMsg = index < channelState.messages.length - 1
                  ? channelState.messages[index + 1]
                  : null;
              final isSubsequent = nextMsg != null &&
                  nextMsg.senderId == msg.senderId &&
                  nextMsg.isAnnouncement == msg.isAnnouncement &&
                  nextMsg.metadata.type == msg.metadata.type;

              // ── Separador de Data ──
              Widget? dateSeparator;
              final currentDate = DateTime(
                msg.createdAt.toLocal().year,
                msg.createdAt.toLocal().month,
                msg.createdAt.toLocal().day,
              );
              bool showDate = false;
              if (index == channelState.messages.length - 1) {
                showDate = true;
              } else {
                final nextDate = DateTime(
                  nextMsg!.createdAt.toLocal().year,
                  nextMsg.createdAt.toLocal().month,
                  nextMsg.createdAt.toLocal().day,
                );
                showDate = currentDate != nextDate;
              }
              if (showDate) {
                dateSeparator = Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      msg.createdAt.dateSeparatorFormatted,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }

              // ── Régua de não lidas ──
              // A lista é `reverse: true`, então o que vem antes da mensagem
              // na Column aparece acima dela na tela.
              final showUnreadMarker =
                  msg.id == channelState.firstUnreadMessageId;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dateSeparator != null) dateSeparator,
                  if (showUnreadMarker) _buildUnreadDivider(theme),
                  Dismissible(
                    key: ValueKey('swipe-${msg.id}'),
                    direction: msgSelection.active
                        ? DismissDirection.none
                        : DismissDirection.startToEnd,
                    confirmDismiss: (direction) async {
                      if (!msg.isOptimistic) {
                        ref
                            .read(activeChannelProvider(
                                    ChannelArgs(channelId: widget.channelId))
                                .notifier)
                            .setReply(msg);
                      }
                      return false;
                    },
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 16.0),
                      color: Colors.transparent,
                      child: Icon(Icons.reply_rounded,
                          color: theme.colorScheme.primary),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: msgSelection.active && !msg.isOptimistic
                          ? () => ref
                              .read(messageSelectionProvider(widget.channelId)
                                  .notifier)
                              .toggle(msg.id)
                          : null,
                      onLongPress: msg.isOptimistic
                          ? null
                          : () {
                              if (msgSelection.active) {
                                ref
                                    .read(messageSelectionProvider(
                                            widget.channelId)
                                        .notifier)
                                    .toggle(msg.id);
                                return;
                              }
                              _showMessageActions(
                                  context, msg, channelState.userCache);
                            },
                      child: MessageSelectionWrapper(
                        active: msgSelection.active,
                        selected: msgSelection.contains(msg.id),
                        child: _MessageTile(
                          message: msg,
                          theme: theme,
                          userCache: channelState.userCache,
                          isSubsequent: isSubsequent && !showDate,
                          quoted: channelState.quotedFor(msg),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Durante a seleção o rodapé é a barra de ações, não o input.
        if (!msgSelection.active) _buildChannelComposer(channelState),
      ],
    );
  }

  /// Marcador "novas mensagens", posicionado na primeira mensagem que chegou
  /// depois do último `last_read_at` do usuário.
  Widget _buildUnreadDivider(ThemeData theme) {
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Divider(color: accent.withValues(alpha: 0.5))),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Text(
              'Novas mensagens',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          Expanded(child: Divider(color: accent.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  // ── Ações em lote da seleção múltipla de mensagens ────────

  List<ChannelMessageModel> _selectedChannelMessages(
      Set<String> ids, ChannelState channelState) {
    final picked = channelState.messages
        .where((m) => ids.contains(m.id))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return picked;
  }

  /// Igual ao chat: excluir em lote só vale para as próprias mensagens.
  bool _canDeleteSelectedMessages(Set<String> ids) {
    final myId = supabase.auth.currentUser?.id;
    final channelState = ref
        .read(activeChannelProvider(ChannelArgs(channelId: widget.channelId)));
    final picked = _selectedChannelMessages(ids, channelState);
    return picked.isNotEmpty && picked.every((m) => m.senderId == myId);
  }

  void _endMessageSelection() =>
      ref.read(messageSelectionProvider(widget.channelId).notifier).clear();

  Future<void> _forwardSelectedMessages(
      Set<String> ids, ChannelState channelState) async {
    final picked = _selectedChannelMessages(ids, channelState);
    if (picked.isEmpty) return;

    final target =
        await showForwardPicker(context, excludeId: widget.channelId);
    if (target == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final myId = supabase.auth.currentUser?.id;
    var sent = 0;

    try {
      for (final msg in picked) {
        final senderName = msg.senderId == myId
            ? 'Você'
            : (channelState.userCache[msg.senderId]?.fullName ?? 'Membro');
        await MessageForwardService.forward(
          target: target,
          originalSenderName: senderName,
          content: msg.content,
          contentType: msg.contentType,
          mediaUrl: msg.mediaUrl,
          metadata: msg.metadata.toMap(),
        );
        sent++;
      }
      _endMessageSelection();
      messenger.showSnackBar(
        SnackBar(
          content: Text(sent == 1
              ? 'Mensagem encaminhada para ${target.name}'
              : '$sent mensagens encaminhadas para ${target.name}'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(sent == 0
              ? 'Não foi possível encaminhar para ${target.name}.'
              : 'Encaminhadas $sent de ${picked.length}; o restante falhou.'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _copySelectedMessages(
      Set<String> ids, ChannelState channelState) async {
    final picked = _selectedChannelMessages(ids, channelState);
    if (picked.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final myId = supabase.auth.currentUser?.id;

    await MessageBatchActions.copyToClipboard([
      for (final m in picked)
        SelectedMessage(
          id: m.id,
          senderName: m.senderId == myId
              ? 'Você'
              : (channelState.userCache[m.senderId]?.fullName ?? 'Membro'),
          content: m.content,
          contentType: m.contentType,
          mediaUrl: m.mediaUrl,
          metadata: m.metadata.toMap(),
          createdAt: m.createdAt,
          isMine: m.senderId == myId,
        ),
    ]);

    _endMessageSelection();
    messenger.showSnackBar(
      SnackBar(
        content: Text(picked.length == 1
            ? 'Mensagem copiada'
            : '${picked.length} mensagens copiadas'),
      ),
    );
  }

  Future<void> _starSelectedMessages(Set<String> ids) async {
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      final result = await MessageStarService.toggleAll(
        ids,
        scopeId: widget.channelId,
        isChannel: true,
      );
      _endMessageSelection();
      if (result.isEmpty) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.removed > 0
              ? '${result.removed} removida(s) dos favoritos'
              : '${result.added} adicionada(s) aos favoritos'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Não foi possível atualizar os favoritos.'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _deleteSelectedMessages(Set<String> ids) async {
    final channelState = ref
        .read(activeChannelProvider(ChannelArgs(channelId: widget.channelId)));
    final picked = _selectedChannelMessages(ids, channelState);
    if (picked.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(picked.length == 1
            ? 'Apagar mensagem?'
            : 'Apagar ${picked.length} mensagens?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Apagar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final notifier = ref.read(
        activeChannelProvider(ChannelArgs(channelId: widget.channelId))
            .notifier);
    final messenger = ScaffoldMessenger.of(context);

    // `deleteMessage` propaga o erro da RPC; uma recusa em uma mensagem não
    // pode abortar as demais do lote.
    var failed = 0;
    for (final msg in picked) {
      try {
        await notifier.deleteMessage(msg.id);
      } catch (_) {
        failed++;
      }
    }

    if (failed > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(failed == picked.length
              ? 'Não foi possível apagar as mensagens.'
              : '$failed de ${picked.length} mensagens não puderam ser apagadas.'),
          backgroundColor: Colors.red,
        ),
      );
    }
    _endMessageSelection();
  }

  /// Trecho da mensagem para a folha de informações.
  ///
  /// Mídia sem legenda não tem texto nenhum; sem um rótulo, a folha abriria
  /// só com uma lista de nomes e sem dizer de qual mensagem se trata.
  static String _channelMessagePreview(ChannelMessageModel msg) {
    final text = msg.content?.trim() ?? '';
    if (text.isNotEmpty) return text;

    return switch (msg.contentType) {
      'image' => 'Foto',
      'video' => 'Vídeo',
      'audio' => 'Áudio',
      'file' => 'Arquivo',
      _ => 'Mensagem',
    };
  }

  /// Ações de uma mensagem do canal: responder, abrir tópico, encaminhar.
  void _showMessageActions(
    BuildContext context,
    ChannelMessageModel msg,
    Map<String, UserModel> userCache,
  ) {
    final isMe = msg.senderId == supabase.auth.currentUser?.id;
    final senderName =
        isMe ? 'Você' : (userCache[msg.senderId]?.fullName ?? 'Membro');

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.reply,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('Responder'),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(activeChannelProvider(
                            ChannelArgs(channelId: widget.channelId))
                        .notifier)
                    .setReply(msg);
              },
            ),
            ListTile(
              leading: Icon(Icons.forum,
                  color: Theme.of(context).colorScheme.secondary),
              title: const Text('Responder em Tópico'),
              onTap: () {
                Navigator.pop(ctx);
                context.push(
                  '/channel/${widget.channelId}/thread/${msg.id}',
                  extra: {'parentMessage': msg, 'senderName': senderName},
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.checklist,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('Selecionar'),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(messageSelectionProvider(widget.channelId).notifier)
                    .start(msg.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shortcut, color: Colors.teal),
              title: const Text('Encaminhar'),
              onTap: () {
                Navigator.pop(ctx);
                _forwardChannelMessage(context, msg, senderName);
              },
            ),
            // Mensagem otimista ainda não existe no banco: abrir os recibos
            // dela daria "mensagem não encontrada".
            if (!msg.isOptimistic)
              ListTile(
                leading: Icon(Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Informações'),
                subtitle: const Text(
                  'Quem do canal recebeu e leu',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  MessageInfoSheet.show(
                    context,
                    messageId: msg.id,
                    scope: ReceiptScope.channel,
                    preview: _channelMessagePreview(msg),
                  );
                },
              ),
            if (msg.content != null && msg.content!.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copiar'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: msg.content!));
                },
              ),
            if (_canEditChannelMessage(msg, isMe))
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Editar'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editChannelMessage(msg);
                },
              ),
            if (isMe || _canModerateChannel())
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(isMe ? 'Apagar' : 'Apagar (moderação)',
                    style: const TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteChannelMessage(msg, moderated: !isMe);
                },
              ),
          ],
        ),
      ),
    );
  }

  bool _canModerateChannel() {
    final channelState = ref
        .read(activeChannelProvider(ChannelArgs(channelId: widget.channelId)));
    return channelState.canGovernChannel;
  }

  /// Espelha o que `edit_channel_message` aceita no banco: só o autor, só
  /// mensagem viva, e nada de anúncio/enquete (que carregam ciência e votos).
  bool _canEditChannelMessage(ChannelMessageModel msg, bool isMe) {
    if (!isMe || msg.isDeleted || msg.isOptimistic) return false;
    if (!const {'text', 'image', 'video', 'file'}.contains(msg.contentType)) {
      return false;
    }
    if (msg.metadata.isAnnouncement ||
        msg.metadata.isPoll ||
        msg.metadata.isDateEvent) {
      return false;
    }
    return (msg.content ?? '').trim().isNotEmpty;
  }

  Future<void> _editChannelMessage(ChannelMessageModel msg) async {
    final controller = TextEditingController(text: msg.content ?? '');
    final messenger = ScaffoldMessenger.of(context);

    final newContent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar mensagem'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 1,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Mensagem',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (newContent == null ||
        newContent.isEmpty ||
        newContent == (msg.content ?? '').trim()) {
      return;
    }

    try {
      await ref
          .read(activeChannelProvider(ChannelArgs(channelId: widget.channelId))
              .notifier)
          .editMessage(msg.id, newContent);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao editar: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteChannelMessage(ChannelMessageModel msg,
      {required bool moderated}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar mensagem'),
        content: Text(moderated
            ? 'Apagar esta mensagem de outro membro? A ação fica registrada na auditoria.'
            : 'Apagar esta mensagem para todos?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(activeChannelProvider(ChannelArgs(channelId: widget.channelId))
              .notifier)
          .deleteMessage(msg.id);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao apagar: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _forwardChannelMessage(
    BuildContext context,
    ChannelMessageModel msg,
    String senderName,
  ) async {
    final target =
        await showForwardPicker(context, excludeId: widget.channelId);
    if (target == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await MessageForwardService.forward(
        target: target,
        originalSenderName: senderName,
        content: msg.content,
        contentType: msg.contentType,
        mediaUrl: msg.mediaUrl,
        metadata: msg.metadata.toMap(),
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Mensagem encaminhada para ${target.name}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Não foi possível encaminhar para ${target.name}.'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  void _showFilterSheet(BuildContext context) {
    final workflowState = ref.read(workflowProvider(widget.channelId));
    final notifier = ref.read(workflowProvider(widget.channelId).notifier);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          String? selectedStatus = workflowState.filterStatus;
          String? selectedPriority = workflowState.filterPriority;
          bool myCardsOnly = workflowState.filterMyCards ?? false;

          return Container(
            height: MediaQuery.of(context).size.height * 0.55,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Filtrar Cards',
                          style: Theme.of(context).textTheme.titleLarge),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx)),
                    ]),
              ),
              const Divider(),
              Expanded(
                  child: ListView(children: [
                ListTile(
                    leading: Icon(
                      Icons.person_outline,
                      color: myCardsOnly
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: const Text('Meus Cards'),
                    subtitle: const Text('Cards que eu criei'),
                    trailing: Switch(
                      value: myCardsOnly,
                      onChanged: (v) => setModalState(() => myCardsOnly = v),
                    )),
                const Divider(),
                ListTile(
                    leading: const Icon(Icons.assignment_outlined),
                    title: const Text('Por Status'),
                    trailing: DropdownButton<String>(
                      value: selectedStatus,
                      hint: const Text('Todos'),
                      underline: const SizedBox(),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Todos')),
                        ...workflowState.statusConfig.map(
                          (s) => DropdownMenuItem(
                              value: s.status, child: Text(s.status)),
                        ),
                      ],
                      onChanged: (v) => setModalState(() => selectedStatus = v),
                    ),
                    onTap: () {}),
                const Divider(),
                ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Por Prioridade'),
                    trailing: DropdownButton<String>(
                      value: selectedPriority,
                      hint: const Text('Todas'),
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Todas')),
                        DropdownMenuItem(value: 'low', child: Text('Baixa')),
                        DropdownMenuItem(value: 'medium', child: Text('Média')),
                        DropdownMenuItem(value: 'high', child: Text('Alta')),
                        DropdownMenuItem(
                            value: 'urgent', child: Text('Urgente')),
                      ],
                      onChanged: (v) =>
                          setModalState(() => selectedPriority = v),
                    ),
                    onTap: () {}),
              ])),
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          notifier.clearFilters();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Limpar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          notifier.setFilter(
                            status: selectedStatus,
                            priority: selectedPriority,
                            myCards: myCardsOnly,
                          );
                          Navigator.pop(ctx);
                        },
                        child: const Text('Aplicar'),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  void _showCreateCardSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreateCardSheet(
        channelId: widget.channelId,
        channelName: widget.channelName,
        onCreated: () =>
            ref.read(workflowProvider(widget.channelId).notifier).loadCards(),
      ),
    );
  }

  Widget _buildFilterBar(
      BuildContext context, WidgetRef ref, WorkflowState workflowState) {
    final myId = supabase.auth.currentUser?.id;
    final myCount = workflowState.myCardsCount(myId);
    final isSearching = workflowState.searchQuery.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // Search field compacto
          Expanded(
            flex: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isSearching ? 180 : 42,
              height: 36,
              child: isSearching
                  ? TextField(
                      autofocus: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Buscar cards...',
                        hintStyle: const TextStyle(fontSize: 12),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => ref
                              .read(workflowProvider(widget.channelId).notifier)
                              .setSearchQuery(''),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                      ),
                      onChanged: (v) => ref
                          .read(workflowProvider(widget.channelId).notifier)
                          .setSearchQuery(v),
                    )
                  : IconButton(
                      icon: const Icon(Icons.search, size: 20),
                      tooltip: 'Buscar',
                      onPressed: () => ref
                          .read(workflowProvider(widget.channelId).notifier)
                          .setSearchQuery(''),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          // Chips scrolláveis
          Expanded(
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Meus Cards',
                            style: TextStyle(fontSize: 12)),
                        if (myCount > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: workflowState.filterMyCards == true
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onPrimary
                                      .withValues(alpha: 0.2)
                                  : Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$myCount',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: workflowState.filterMyCards == true
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    selected: workflowState.filterMyCards == true,
                    onSelected: (val) {
                      final currentMyCards =
                          workflowState.filterMyCards ?? false;
                      ref
                          .read(workflowProvider(widget.channelId).notifier)
                          .setFilter(
                            myCards: currentMyCards ? null : true,
                            status: workflowState.filterStatus,
                            priority: workflowState.filterPriority,
                            assignedTo: workflowState.filterAssignedTo,
                          );
                    },
                    showCheckmark: false,
                    avatar: const Icon(Icons.person, size: 16),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(workflowState.filterStatus ?? 'Status',
                        style: const TextStyle(fontSize: 12)),
                    selected: workflowState.filterStatus != null,
                    onSelected: (_) {
                      if (workflowState.filterStatus != null) {
                        ref
                            .read(workflowProvider(widget.channelId).notifier)
                            .setFilter(
                              status: null,
                              myCards: workflowState.filterMyCards,
                              priority: workflowState.filterPriority,
                              assignedTo: workflowState.filterAssignedTo,
                            );
                      } else {
                        _showFilterSheet(context);
                      }
                    },
                    showCheckmark: false,
                    avatar: workflowState.filterStatus != null
                        ? const Icon(Icons.close, size: 16)
                        : const Icon(Icons.arrow_drop_down, size: 16),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(workflowState.filterPriority ?? 'Prioridade',
                        style: const TextStyle(fontSize: 12)),
                    selected: workflowState.filterPriority != null,
                    onSelected: (_) {
                      if (workflowState.filterPriority != null) {
                        ref
                            .read(workflowProvider(widget.channelId).notifier)
                            .setFilter(
                              priority: null,
                              myCards: workflowState.filterMyCards,
                              status: workflowState.filterStatus,
                              assignedTo: workflowState.filterAssignedTo,
                            );
                      } else {
                        _showFilterSheet(context);
                      }
                    },
                    showCheckmark: false,
                    avatar: workflowState.filterPriority != null
                        ? const Icon(Icons.close, size: 16)
                        : const Icon(Icons.arrow_drop_down, size: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelledTab(
      BuildContext context, ThemeData theme, WorkflowState workflowState) {
    final cancelledCards = workflowState.cards
        .where((c) => workflowState.isCancelledStatus(c.status))
        .toList();
    if (cancelledCards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_outline,
                  size: 40, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 20),
            Text('Nenhuma solicitação cancelada',
                style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Cards cancelados aparecerão aqui',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header with count
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.red.withValues(alpha: 0.08),
          child: Row(
            children: [
              const Icon(Icons.cancel, color: Colors.red, size: 18),
              const SizedBox(width: 10),
              Text(
                '${cancelledCards.length} solicita\u00e7\u00e3o${cancelledCards.length > 1 ? '\u00f5es' : ''} cancelada${cancelledCards.length > 1 ? 's' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: cancelledCards.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final card = cancelledCards[index];
              final priorityColor = Color(card.priority.color);
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => CardDetailsSheet(
                          card: card,
                          channelId: widget.channelId,
                        ),
                      );
                    },
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Priority stripe
                          Container(
                            width: 5,
                            decoration: BoxDecoration(
                              color: priorityColor,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(14),
                                bottomLeft: Radius.circular(14),
                              ),
                            ),
                          ),
                          // Content
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(card.title,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    decoration: TextDecoration
                                                        .lineThrough,
                                                    decorationColor: Colors.red
                                                        .withValues(
                                                            alpha: 0.5))),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.red
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: const Text('CANCELADO',
                                            style: TextStyle(
                                                color: Colors.red,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      // Card type badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.tertiary
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(card.cardType.label,
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: theme
                                                    .colorScheme.tertiary)),
                                      ),
                                      const SizedBox(width: 8),
                                      // Priority badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: priorityColor.withValues(
                                              alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(card.priority.label,
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: priorityColor)),
                                      ),
                                      const Spacer(),
                                      // Date
                                      Text(formatWorkflowDate(card.updatedAt),
                                          style: TextStyle(
                                              fontSize: 10,
                                              color:
                                                  theme.colorScheme.outline)),
                                    ],
                                  ),
                                  if (card.requestedByName != null &&
                                      card.requestedByName!.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.person_outline,
                                            size: 13,
                                            color: theme.colorScheme.outline),
                                        const SizedBox(width: 4),
                                        Text(
                                            'Solicitante: ${card.requestedByName}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color:
                                                    theme.colorScheme.outline)),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          // Chevron
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(Icons.chevron_right,
                                color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MessageTile extends StatelessWidget {
  final ChannelMessageModel message;
  final ThemeData theme;
  final Map<String, UserModel> userCache;
  final bool isSubsequent;
  final ChannelMessageModel? quoted;

  const _MessageTile({
    required this.message,
    required this.theme,
    this.userCache = const {},
    this.isSubsequent = false,
    this.quoted,
  });

  /// Nome de quem escreveu a mensagem citada.
  String? get _quotedSenderName {
    final q = quoted;
    if (q == null) return null;
    if (q.senderId == supabase.auth.currentUser?.id) return 'Você';
    return userCache[q.senderId]?.fullName ?? 'Usuário';
  }

  @override
  Widget build(BuildContext context) {
    final sender = userCache[message.senderId];
    final senderName = sender?.fullName ?? 'Usuário';
    final isMe = message.senderId == supabase.auth.currentUser?.id;

    if (message.isAnnouncement ||
        message.metadata.isMeeting ||
        message.metadata.isStructuredCard) {
      return ChannelMessageBubble(
        message: message,
        isMe: isMe,
        senderName: senderName,
        quoted: quoted,
        quotedSenderName: _quotedSenderName,
        onTapThread: () => context.push(
          '/channel/${message.channelId}/thread/${message.id}',
          extra: {
            'parentMessage': message,
            'senderName': isMe ? 'Você' : senderName,
          },
        ),
      );
    }

    final senderAvatar = sender?.avatarUrl;

    return Padding(
      padding: EdgeInsets.only(bottom: isSubsequent ? 2 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            if (isSubsequent)
              const SizedBox(width: 40) // placeholder for hidden avatar
            else
              CircleAvatar(
                radius: 16,
                backgroundColor: _getAvatarColor(senderName),
                backgroundImage:
                    senderAvatar != null ? CachedNetworkImageProvider(senderAvatar, maxWidth: 320) : null,
                child: senderAvatar == null
                    ? Text(
                        senderName.isNotEmpty
                            ? senderName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      )
                    : null,
              ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe && !isSubsequent)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      senderName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.65,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isSubsequent && !isMe ? 8 : 16),
                      topRight: Radius.circular(isSubsequent && isMe ? 8 : 16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyTo != null)
                        ChannelReplyQuote(
                          quoted: quoted,
                          senderName: _quotedSenderName,
                          accentColor:
                              isMe ? Colors.white : theme.colorScheme.primary,
                          textColor:
                              isMe ? Colors.white : theme.colorScheme.onSurface,
                        ),
                      if (message.contentType == 'image' &&
                          message.mediaUrl != null)
                        _buildImageMessage(context),
                      if (message.contentType == 'file')
                        _buildFileMessage(context, theme, isMe),
                      if (message.content != null &&
                          message.content!.isNotEmpty &&
                          message.contentType != 'file')
                        Text(
                          message.content!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isMe
                                ? Colors.white
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(message.createdAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isMe
                                  ? Colors.white70
                                  : theme.colorScheme.outline,
                              fontSize: 10,
                            ),
                          ),
                          if (message.isEdited) ...[
                            const SizedBox(width: 4),
                            Text(
                              '• editado',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isMe
                                    ? Colors.white60
                                    : theme.colorScheme.outline,
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.done_all,
                              size: 14,
                              color: Colors.white70,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (message.metadata.hasReactions) _buildReactions(theme),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 24),
        ],
      ),
    );
  }

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF6750A4),
      const Color(0xFF2196F3),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFFE91E63),
      const Color(0xFF00BCD4),
      const Color(0xFF9C27B0),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays == 0) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Ontem';
    } else if (diff.inDays < 7) {
      const weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
      return weekdays[dateTime.weekday - 1];
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }

  Widget _buildImageMessage(BuildContext context) {
    final heroTag = 'hero_workflow_channel_${message.id}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          if (message.mediaUrl == null || message.mediaUrl!.isEmpty) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                iconTheme: const IconThemeData(color: Colors.white),
                elevation: 0,
              ),
              extendBodyBehindAppBar: true,
              body: Center(
                child: Hero(
                  tag: heroTag,
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: SignedNetworkImage(
                      storedUrl: message.mediaUrl!,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ));
        },
        child: Hero(
          tag: heroTag,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SignedNetworkImage(
              storedUrl: message.mediaUrl!,
              width: 220,
              height: 180,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: 220,
                height: 180,
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileMessage(BuildContext context, ThemeData theme, bool isMe) {
    final fileName = message.content ?? 'Arquivo';
    final fileSize = message.metadata.formattedSize;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: (message.mediaUrl != null || message.localFilePath != null)
              ? () async {
                  final rawUrl = message.mediaUrl ?? message.localFilePath;
                  if (rawUrl == null || rawUrl.isEmpty) return;
                  try {
                    final url = await MediaUrlResolver.resolve(
                      rawUrl,
                      downloadFileName: fileName,
                    );
                    final uri = Uri.parse(url);
                    bool launched = false;
                    try {
                      launched = await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                        webOnlyWindowName: '_blank',
                      );
                    } catch (_) {}

                    if (!launched) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.platformDefault,
                        webOnlyWindowName: '_blank',
                      );
                    }
                  } catch (e) {
                    debugPrint('Erro ao abrir documento no workflow: $e');
                  }
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isMe ? Colors.white.withValues(alpha: 0.18) : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isMe ? Colors.white.withValues(alpha: 0.3) : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  color: isMe ? Colors.white : theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fileName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isMe ? Colors.white : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (fileSize.isNotEmpty)
                        Text(
                          fileSize,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isMe ? Colors.white70 : theme.colorScheme.outline,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.download_rounded,
                  color: isMe ? Colors.white70 : theme.colorScheme.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReactions(ThemeData theme) {
    final reactions = message.metadata.reactions;
    if (reactions == null || reactions.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: reactions.entries.map((entry) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${entry.key} ${entry.value}',
              style: theme.textTheme.labelSmall,
            ),
          );
        }).toList(),
      ),
    );
  }
}
