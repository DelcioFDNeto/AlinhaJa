import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/features/workflow/providers/workflow_provider.dart';
import 'package:alinha_ja/features/workflow/models/workflow_card_model.dart';
import 'package:alinha_ja/features/workflow/models/workflow_supporting_models.dart';
import 'package:alinha_ja/core/services/media_url_resolver.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';

Uint8List _encodeZip(List<PlatformFile> files) {
  final archive = Archive();
  for (var f in files) {
    final bytes = f.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      archive.addFile(ArchiveFile(f.name, bytes.length, bytes));
    }
  }
  final zipEncoder = ZipEncoder();
  return Uint8List.fromList(zipEncoder.encode(archive));
}

/// B3: Unified card details sheet — used by both Board and List views.
/// Combines all features: specific fields, comments, history, assign.
class CardDetailsSheet extends ConsumerStatefulWidget {
  final WorkflowCard card;
  final String channelId;

  const CardDetailsSheet({
    super.key,
    required this.card,
    required this.channelId,
  });

  @override
  ConsumerState<CardDetailsSheet> createState() => _CardDetailsSheetState();
}

class _CardDetailsSheetState extends ConsumerState<CardDetailsSheet> {
  // P2: Cache history and comments to avoid re-fetch on every rebuild
  List<WorkflowCardHistory>? _cachedHistory;
  List<WorkflowCardComment>? _cachedComments;
  final _commentController = TextEditingController();
  bool _isLoadingHistory = true;
  bool _isLoadingComments = true;
  bool _showAllHistory = false;
  bool _isZipping = false;
  bool _isClaiming = false;
  StreamSubscription<List<Map<String, dynamic>>>? _commentsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _historySub;
  Timer? _commentsDebounce;
  Timer? _historyDebounce;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadComments();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _commentsSub?.cancel();
    _historySub?.cancel();
    _commentsDebounce?.cancel();
    _historyDebounce?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    _commentsSub = supabase
        .from('workflow_card_comments')
        .stream(primaryKey: ['id'])
        .eq('card_id', widget.card.id)
        .listen((_) {
          _commentsDebounce?.cancel();
          _commentsDebounce =
              Timer(const Duration(milliseconds: 250), _loadComments);
        });

    _historySub = supabase
        .from('workflow_card_history')
        .stream(primaryKey: ['id'])
        .eq('card_id', widget.card.id)
        .listen((_) {
          _historyDebounce?.cancel();
          _historyDebounce =
              Timer(const Duration(milliseconds: 250), _loadHistory);
        });
  }

  Future<void> _completeWithAttachment(WorkflowNotifier notifier) async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    final isRequester = currentUser?.id == widget.card.requestedBy;
    if (isRequester || currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sem permissão para finalizar o card.'),
            backgroundColor: Colors.red));
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _isZipping = true);

    try {
      final zipData = await compute(_encodeZip, result.files);
      final zipFileName =
          'anexos_finais_${DateTime.now().millisecondsSinceEpoch}.zip';
      final storagePath = 'workflow_attachments/$zipFileName';

      await supabase.storage
          .from('chat-media')
          .uploadBinary(storagePath, zipData);
      final publicUrl =
          supabase.storage.from('chat-media').getPublicUrl(storagePath);

      final currentAttachments =
          List<Map<String, dynamic>>.from(widget.card.attachments);
      currentAttachments
          .add({'name': 'Documento Final (Operador).zip', 'url': publicUrl});

      await supabase
          .from('workflow_cards')
          .update({'attachments': currentAttachments}).eq('id', widget.card.id);
      await notifier.completeCard(widget.card.id);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Card finalizado com sucesso!'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Falha ao finalizar: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isZipping = false);
    }
  }

  void _handleCancelCard(WorkflowCard card, WorkflowNotifier notifier) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    final currentUser = ref.read(currentUserProvider).valueOrNull;
    final isAdmin = currentUser != null &&
        AppPermissions.canManageWorkflow(currentUser.roleLevel);
    final isCreator = card.requestedBy == currentUserId;
    final isOperator = card.assignedTo == currentUserId;

    if (isCreator || (!isOperator && !isAdmin)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(isCreator
                ? 'O solicitante nao pode cancelar ou operar o proprio card. Aguarde a conclusao para interagir.'
                : 'Sem permissao para cancelar este card. Apenas gestores ou o operador associado podem cancelar.'),
            backgroundColor: Colors.red),
      );
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Solicitação?'),
        content: const Text(
            'Tem certeza de que deseja cancelar este card? Ele será removido do painel principal (Kaban) e movido para a aba de Cancelados. Esta ação não excluirá o card do sistema.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Não, Voltar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, Cancelar Card',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // A etapa de cancelamento é configurável por workspace; só cai no
        // literal quando o canal não tem nenhuma etapa marcada como tal.
        await notifier.updateCardStatus(
            card.id, notifier.getCancelledStatus() ?? 'Cancelado');
        if (mounted) {
          Navigator.pop(context); // Fechar sheet
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Card cancelado e movido para a aba de Cancelados.'),
                backgroundColor: Colors.orange),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Erro ao cancelar: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// Abre um anexo do card.
  ///
  /// A URL vai gravada em `workflow_cards.attachments` no formato público, de
  /// quando o bucket `chat-media` era aberto. Com o bucket privado ela deixa de
  /// resolver sozinha: `MediaUrlResolver` extrai o path e assina na hora, sob a
  /// policy de membership. Passar pelo resolver tambem enquanto o bucket ainda
  /// e publico e inofensivo — ele devolve a URL original se a assinatura falhar.
  Future<void> _abrirAnexo(String storedUrl, String fileName) async {
    try {
      final url = await MediaUrlResolver.resolve(
        storedUrl,
        downloadFileName: fileName,
      );
      final uri = Uri.parse(url);

      // Mesmo par de tentativas do workflow_main_view: no Web o
      // externalApplication e barrado como popup em alguns navegadores.
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
      debugPrint('Erro ao abrir anexo do card: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel abrir o anexo.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadHistory() async {
    final notifier = ref.read(workflowProvider(widget.channelId).notifier);
    final history = await notifier.getCardHistory(widget.card.id);
    if (mounted) {
      setState(() {
        _cachedHistory = history;
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _loadComments() async {
    final notifier = ref.read(workflowProvider(widget.channelId).notifier);
    final comments = await notifier.getCardComments(widget.card.id);
    if (mounted) {
      setState(() {
        _cachedComments = comments;
        _isLoadingComments = false;
      });
    }
  }

  void _copyCardSummary(WorkflowCard card) {
    final lines = <String>[
      '📋 ${card.title}',
      '━━━━━━━━━━━━━━━━━━━',
      '📌 Status: ${card.status}',
      '🔴 Prioridade: ${card.priority.label}',
      '📂 Tipo: ${card.cardType.label}',
    ];
    if (card.requestedByName != null) {
      lines.add('👤 Solicitante: ${card.requestedByName}');
    }
    if (card.assignedToName != null) {
      lines.add('⚙️ Responsável: ${card.assignedToName}');
    }
    if (card.description != null && card.description!.isNotEmpty) {
      lines.add('📝 Descrição: ${card.description}');
    }
    if (card.supplier != null) lines.add('🏢 Fornecedor: ${card.supplier}');
    if (card.amount != null) lines.add('💰 Valor: ${card.displayAmount}');
    if (card.dueDate != null) {
      lines.add('📅 Vencimento: ${card.displayDueDate}');
    }
    if (card.clientName != null) lines.add('👤 Cliente: ${card.clientName}');
    if (card.orderNumber != null) {
      lines.add('📦 Nº Pedido: ${card.orderNumber}');
    }
    if (card.vehicleModel != null) {
      lines.add('🚗 Veículo: ${card.vehicleModel}');
    }
    if (card.plate != null) lines.add('🔖 Placa: ${card.plate}');
    if (card.osNumber != null) lines.add('🔧 OS: ${card.osNumber}');
    if (card.observations != null && card.observations!.isNotEmpty) {
      lines.add('💬 Observações: ${card.observations}');
    }
    lines.add('━━━━━━━━━━━━━━━━━━━');
    lines.add(
        '🕐 Criado: ${card.createdAt.toLocal().toString().substring(0, 16)}');

    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('📋 Resumo copiado!'),
            duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _claimCard(WorkflowNotifier notifier) async {
    setState(() => _isClaiming = true);
    try {
      await notifier.claimCard(widget.card.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Atendimento assumido.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao assumir atendimento: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Re-read the card from the provider to get realtime updates
    final workflowState = ref.watch(workflowProvider(widget.channelId));
    final card = workflowState.cards.firstWhere(
      (c) => c.id == widget.card.id,
      orElse: () => widget.card,
    );
    final notifier = ref.read(workflowProvider(widget.channelId).notifier);
    final priorityColor = Color(card.priority.color);

    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final isMember = currentUser == null ||
        currentUser.roleLevel == 'member' ||
        currentUser.roleLevel == 'manager';
    final isRequester = currentUser?.id == card.requestedBy;
    final canManageWorkflow = currentUser != null && !isMember;
    final canOperateCard = currentUser != null && !isRequester;
    final isCancelled = workflowState.isCancelledStatus(card.status);
    final canComment = currentUser != null && !isCancelled;
    final canCancelOrEdit = currentUser != null &&
        !isRequester &&
        (canManageWorkflow || card.assignedTo == currentUser.id);
    final canClaim = currentUser != null &&
        !isRequester &&
        workflowState.canUserClaimCard(
          currentUser.id,
          card,
        );

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ── Header with gradient ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  priorityColor.withValues(alpha: 0.1),
                  theme.colorScheme.surface,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        card.title,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      tooltip: 'Copiar Resumo',
                      onPressed: () => _copyCardSummary(card),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildChip(
                        label: card.priority.label, color: priorityColor),
                    _buildChip(
                        label: card.status, color: theme.colorScheme.primary),
                    _buildChip(
                        label: card.cardType.label,
                        color: theme.colorScheme.tertiary),
                  ],
                ),
              ],
            ),
          ),
          // ── Body ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Status progression stepper
                _buildStatusStepper(card, theme,
                    ref.watch(workflowProvider(widget.channelId)).statusConfig),
                const SizedBox(height: 24),

                // Description
                if (card.description != null &&
                    card.description!.isNotEmpty) ...[
                  _buildSectionTitle('Descrição', theme),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(card.description!,
                        style: theme.textTheme.bodyMedium),
                  ),
                  const SizedBox(height: 24),
                ],

                // Specific fields per card type
                _buildSpecificFields(card, theme),

                // Participants
                if (card.requestedByName != null ||
                    card.assignedToName != null) ...[
                  const SizedBox(height: 24),
                  _buildSectionTitle('Participantes', theme),
                  const SizedBox(height: 12),
                  if (card.requestedByName != null &&
                      card.requestedByName!.isNotEmpty)
                    _buildInfoRow(Icons.record_voice_over_outlined,
                        'Solicitante', card.requestedByName!, theme),
                  if (card.assignedToName != null &&
                      card.assignedToName!.isNotEmpty)
                    _buildInfoRow(Icons.engineering_outlined, 'Responsável',
                        card.assignedToName!, theme),
                ],

                // Attachments
                if (card.attachments.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildSectionTitle('Anexos', theme),
                  const SizedBox(height: 12),
                  ...card.attachments.map((attachment) {
                    final attachName = attachment['name'] ?? 'Arquivo';
                    final attachUrl = attachment['url'] as String?;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.folder_zip_outlined,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(attachName.toString(),
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          if (attachUrl != null)
                            IconButton(
                              icon: Icon(Icons.download,
                                  color: theme.colorScheme.primary),
                              tooltip: 'Baixar Anexo',
                              onPressed: () => _abrirAnexo(
                                attachUrl,
                                attachName.toString(),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],

                // Actions
                const SizedBox(height: 24),
                _buildSectionTitle('Ações', theme),
                const SizedBox(height: 12),
                if (!canOperateCard) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      'Voce criou este card. O acompanhamento fica liberado, mas as operacoes do workflow ficam com operadores/gestores ate a conclusao.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    if (canOperateCard)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => notifier.togglePin(card.id),
                          icon: Icon(card.isPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined),
                          label: Text(card.isPinned ? 'Desafixar' : 'Fixar'),
                        ),
                      ),
                    if (canOperateCard && !isMember) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showAssignSheet(context, theme, notifier),
                          icon: const Icon(Icons.person_add_outlined),
                          label: const Text('Atribuir'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (canClaim)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          _isClaiming ? null : () => _claimCard(notifier),
                      icon: _isClaiming
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.engineering_outlined),
                      label: Text(
                          _isClaiming ? 'Assumindo...' : 'Assumir atendimento'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                if (canClaim) const SizedBox(height: 12),
                if (canOperateCard &&
                    (!isMember || currentUser.id == card.assignedTo))
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isZipping
                          ? null
                          : () => _completeWithAttachment(notifier),
                      icon: _isZipping
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline,
                              color: Colors.white),
                      label: Text(
                          _isZipping
                              ? 'Enviando Anexo e Finalizando...'
                              : 'Finalizar com Anexo (Operador)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (!isMember)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Arquivar Card?'),
                            content: const Text(
                                'O card será arquivado e não aparecerá mais no board.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancelar')),
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Arquivar',
                                      style: TextStyle(color: Colors.orange))),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          try {
                            await notifier.archiveCard(card.id);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Card arquivado'),
                                      backgroundColor: Colors.green));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Erro: $e'),
                                      backgroundColor: Colors.red));
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Arquivar Card'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade100,
                          foregroundColor: Colors.orange.shade900,
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),

                // ── Prominent Cancel Button ──
                if (!workflowState.isCancelledStatus(card.status) &&
                    canCancelOrEdit) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _handleCancelCard(card, notifier),
                      icon:
                          const Icon(Icons.cancel_outlined, color: Colors.red),
                      label: const Text('Cancelar Solicitação',
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],

                // U5: Comments section
                const SizedBox(height: 24),
                _buildSectionTitle('Comentários', theme),
                const SizedBox(height: 12),
                _buildCommentsSection(theme, notifier, card, canComment),

                // History section (P2: cached)
                const SizedBox(height: 24),
                _buildSectionTitle('Histórico', theme),
                const SizedBox(height: 12),
                _buildHistorySection(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── U5: Comments UI ──
  Widget _buildCommentsSection(ThemeData theme, WorkflowNotifier notifier,
      WorkflowCard card, bool canComment) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isLoadingComments)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator()))
        else if (_cachedComments == null || _cachedComments!.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Nenhum comentário ainda',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          )
        else
          ...(_cachedComments!.map((c) => _buildCommentTile(c, theme))),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                enabled: canComment,
                decoration: InputDecoration(
                  hintText: canComment
                      ? 'Adicionar comentário...'
                      : 'Comentários desativados para cards cancelados',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                maxLines: null,
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: canComment
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              child: IconButton(
                icon: const Icon(Icons.send, size: 18, color: Colors.white),
                onPressed: canComment
                    ? () async {
                        final text = _commentController.text.trim();
                        if (text.isEmpty) return;
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await notifier.addComment(card.id, text);
                        } catch (e) {
                          // Mantém o texto no campo para nova tentativa.
                          messenger.showSnackBar(SnackBar(
                            content: Text(e
                                .toString()
                                .replaceFirst('Exception: ', '')),
                            backgroundColor: Colors.red,
                          ));
                          return;
                        }
                        _commentController.clear();
                        _loadComments(); // Refresh after posting
                      }
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommentTile(WorkflowCardComment comment, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage: comment.userAvatar != null
                ? CachedNetworkImageProvider(comment.userAvatar!, maxWidth: 320)
                : null,
            child: comment.userAvatar == null
                ? Text(
                    (comment.userName ?? 'U')[0].toUpperCase(),
                    style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.userName ?? 'Usuário',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text(
                      '${comment.createdAt.day.toString().padLeft(2, '0')}/${comment.createdAt.month.toString().padLeft(2, '0')} ${comment.createdAt.hour.toString().padLeft(2, '0')}:${comment.createdAt.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      Text(comment.content, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── P2: Cached history ──
  Widget _buildHistorySection(ThemeData theme) {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cachedHistory == null || _cachedHistory!.isEmpty) {
      return Text('Nenhum histórico',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline));
    }

    final displayList =
        _showAllHistory ? _cachedHistory! : _cachedHistory!.take(5).toList();

    return Column(
      children: [
        ...displayList.map((h) => _buildHistoryItem(h, theme)),
        if (_cachedHistory!.length > 5)
          TextButton.icon(
            onPressed: () => setState(() => _showAllHistory = !_showAllHistory),
            icon: Icon(_showAllHistory ? Icons.expand_less : Icons.expand_more,
                size: 18),
            label: Text(_showAllHistory
                ? 'Mostrar menos'
                : 'Ver todos (${_cachedHistory!.length})'),
          ),
      ],
    );
  }

  // ── Assign Sheet ──
  void _showAssignSheet(
      BuildContext context, ThemeData theme, WorkflowNotifier notifier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.2)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_add_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text('Transferir/Atribuir',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder(
                  future: supabase
                      .from('users')
                      .select('id, full_name, role_level, branches(name)')
                      .eq('is_active', true)
                      .order('full_name'),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                          child: Text('Erro ao carregar',
                              style:
                                  TextStyle(color: theme.colorScheme.error)));
                    }
                    final users = snapshot.data as List;
                    if (users.isEmpty) {
                      return const Center(child: Text('Nenhum usuário ativo'));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: users.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final branchObj = user['branches'];
                        final branchName = branchObj != null
                            ? branchObj['name'] as String
                            : null;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              (user['full_name'] as String).isNotEmpty
                                  ? (user['full_name'] as String)[0]
                                      .toUpperCase()
                                  : 'U',
                              style:
                                  TextStyle(color: theme.colorScheme.primary),
                            ),
                          ),
                          title: Text(user['full_name'] as String,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(branchName ?? 'Sede Principal',
                              style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 12)),
                          onTap: () {
                            notifier.assignCard(
                                widget.card.id, user['id'] as String);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Status Stepper Visual ──
  Widget _buildStatusStepper(WorkflowCard card, ThemeData theme,
      List<WorkflowStatusConfig> statusConfig) {
    if (statusConfig.isEmpty) return const SizedBox.shrink();

    // Separar a etapa de cancelamento do fluxo linear (flag configurável).
    final cancelledStatuses = statusConfig
        .where((s) => s.isCancelled)
        .map((s) => s.status.toLowerCase())
        .toSet();
    final isCancelled = cancelledStatuses.contains(card.status.toLowerCase()) ||
        (cancelledStatuses.isEmpty &&
            WorkflowStatusConfig.legacyCancelledNames
                .contains(card.status.toLowerCase()));

    // Fluxo linear: apenas os status que fazem parte da progressão natural
    final linearStatuses = statusConfig.where((s) => !s.isCancelled).toList();

    int currentIndex =
        linearStatuses.indexWhere((s) => s.status == card.status);
    if (currentIndex == -1 && !isCancelled) currentIndex = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Progresso', theme),
        const SizedBox(height: 12),

        // Banner de cancelado (se aplicável)
        if (isCancelled) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.cancel, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Este card foi cancelado',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Stepper linear (sem "Cancelado")
        if (linearStatuses.isNotEmpty)
          SizedBox(
            height: 56,
            child: Row(
              children: List.generate(linearStatuses.length * 2 - 1, (index) {
                // Separadores (linhas) nos índices ímpares
                if (index.isOdd) {
                  final stepBefore = index ~/ 2;
                  final isCompleted = !isCancelled && stepBefore < currentIndex;
                  return Expanded(
                    child: Container(
                      height: 3,
                      color: isCompleted
                          ? Color(linearStatuses[stepBefore].colorValue)
                          : theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.3),
                    ),
                  );
                }

                // Steps nos índices pares
                final stepIndex = index ~/ 2;
                final config = linearStatuses[stepIndex];
                final isCurrent = !isCancelled && stepIndex == currentIndex;
                final isCompleted = !isCancelled && stepIndex < currentIndex;
                final stepColor = Color(config.colorValue);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: isCurrent ? 28 : 22,
                      height: isCurrent ? 28 : 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCancelled
                            ? theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5)
                            : isCurrent
                                ? stepColor
                                : isCompleted
                                    ? stepColor.withValues(alpha: 0.7)
                                    : theme.colorScheme.surfaceContainerHighest,
                        border: isCurrent
                            ? Border.all(
                                color: stepColor.withValues(alpha: 0.3),
                                width: 3)
                            : null,
                      ),
                      child: Icon(
                        isCancelled
                            ? Icons.remove
                            : isCompleted
                                ? Icons.check
                                : isCurrent
                                    ? Icons.circle
                                    : Icons.circle_outlined,
                        size: isCurrent ? 12 : 10,
                        color: isCancelled
                            ? theme.colorScheme.outline.withValues(alpha: 0.5)
                            : isCompleted || isCurrent
                                ? Colors.white
                                : theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 56,
                      child: Text(
                        config.status,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight:
                              isCurrent ? FontWeight.w800 : FontWeight.w500,
                          color: isCancelled
                              ? theme.colorScheme.outline.withValues(alpha: 0.5)
                              : isCurrent
                                  ? stepColor
                                  : theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
      ],
    );
  }

  // ── Helper widgets ──

  Widget _buildSectionTitle(String title, ThemeData theme) {
    return Row(children: [
      Container(
        width: 4,
        height: 20,
        decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 12),
      Text(title,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildInfoRow(
      IconData icon, String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }

  Widget _buildSpecificFields(WorkflowCard card, ThemeData theme) {
    if (card.cardType.value == 'conta_pagar') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionTitle('Dados da Conta', theme),
        const SizedBox(height: 12),
        if (card.supplier != null)
          _buildField('Fornecedor', card.supplier!, theme),
        if (card.amount != null)
          _buildField(
              'Valor',
              'R\$ ${card.amount!.toStringAsFixed(2).replaceAll('.', ',')}',
              theme),
        if (card.dueDate != null)
          _buildField(
              'Vencimento',
              '${card.dueDate!.day}/${card.dueDate!.month}/${card.dueDate!.year}',
              theme),
        if (card.costCenter != null)
          _buildField('Centro Custo', card.costCenter!, theme),
      ]);
    } else if (card.cardType.value == 'fat_moto') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionTitle('Liberação de Pedido', theme),
        const SizedBox(height: 12),
        if (card.clientName != null)
          _buildField('Cliente', card.clientName!, theme),
        if (card.orderNumber != null)
          _buildField('Pedido', card.orderNumber!, theme),
        if (card.fichaNumber != null)
          _buildField('Referência', card.fichaNumber!, theme),
        if (card.consultant != null)
          _buildField('Responsável', card.consultant!, theme),
      ]);
    } else if (card.cardType.value == 'emplacamento') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionTitle('Documentação/Cadastro', theme),
        const SizedBox(height: 12),
        if (card.clientName != null)
          _buildField('Cliente', card.clientName!, theme),
        if (card.clientCpfCnpj != null)
          _buildField('CPF/CNPJ', card.clientCpfCnpj!, theme),
        if (card.vehicleModel != null)
          _buildField('Item/Objeto', card.vehicleModel!, theme),
        if (card.chassisNumber != null)
          _buildField('Nº Documento/Série', card.chassisNumber!, theme),
        if (card.plate != null)
          _buildField('Código/Identificação', card.plate!, theme),
        if (card.branch != null) _buildField('Filial', card.branch!, theme),
      ]);
    } else if (card.cardType.value == 'faturamento_os') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionTitle('Faturamento OS', theme),
        const SizedBox(height: 12),
        if (card.osNumber != null) _buildField('Nº OS', card.osNumber!, theme),
        if (card.budgetNumber != null)
          _buildField('Orçamento', card.budgetNumber!, theme),
        if (card.billingType != null)
          _buildField('Tipo', card.billingType!, theme),
        if (card.itemsDetails != null)
          _buildField('Itens', card.itemsDetails!, theme),
      ]);
    }
    return const SizedBox.shrink();
  }

  Widget _buildField(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 120,
          child: Text('$label:',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ),
        Expanded(
          child: Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  Widget _buildHistoryItem(WorkflowCardHistory history, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle),
          child:
              Icon(Icons.history, size: 16, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${history.action}${history.userName != null ? ' por ${history.userName}' : ''}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (history.newValue != null)
              Text(history.newValue!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            Text(
                '${history.createdAt.day.toString().padLeft(2, '0')}/${history.createdAt.month.toString().padLeft(2, '0')} ${history.createdAt.hour.toString().padLeft(2, '0')}:${history.createdAt.minute.toString().padLeft(2, '0')}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }
}
