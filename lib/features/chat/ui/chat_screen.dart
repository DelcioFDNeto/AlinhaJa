import 'package:alinha_ja/core/services/push_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/chat/providers/chat_provider.dart';
import 'package:alinha_ja/features/chat/ui/widgets/chat_app_bar.dart';
import 'package:alinha_ja/features/chat/ui/widgets/chat_banners.dart';
import 'package:alinha_ja/features/chat/ui/widgets/chat_message_list.dart';
import 'package:alinha_ja/core/ui/composer/composer_media.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/ui/composer/conversation_composer.dart';
import 'package:alinha_ja/features/chat/ui/widgets/chat_composer_delegate.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/features/chat/providers/chat_members_provider.dart';
import 'package:alinha_ja/features/chat/providers/chat_info_provider.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/core/providers/message_selection_provider.dart';
import 'package:alinha_ja/core/services/message_batch_actions.dart';
import 'package:alinha_ja/core/services/message_forward_service.dart';
import 'package:alinha_ja/core/services/message_star_service.dart';
import 'package:alinha_ja/core/widgets/forward_picker_sheet.dart';
import 'package:alinha_ja/core/widgets/selection_action_bar.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:image_picker/image_picker.dart';

// ─── Telas e Handlers ───────────

/// Tela de conversa — lista de mensagens + input.
class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String chatName;
  final bool isGroup;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.chatName,
    this.isGroup = false,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  MessageModel? _replyingTo;
  int? _groupMemberCount;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollDownButton = false;

  @override
  void initState() {
    super.initState();
    // Rastrear qual chat está aberto para suprimir notificações
    Globals.currentOpenChatId = widget.chatId;
    // Abrir a conversa lê as mensagens: tira a notificação dela da bandeja.
    PushNotificationService.dismissConversationNotification(widget.chatId);
    if (widget.isGroup) {
      _fetchMemberCount();
    }
    _scrollController.addListener(() {
      if (_scrollController.offset > 200 && !_showScrollDownButton) {
        setState(() => _showScrollDownButton = true);
      } else if (_scrollController.offset <= 200 && _showScrollDownButton) {
        setState(() => _showScrollDownButton = false);
      }
    });
  }

  @override
  void dispose() {
    // Limpar o rastreamento ao sair da tela
    if (Globals.currentOpenChatId == widget.chatId) {
      Globals.currentOpenChatId = null;
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMemberCount() async {
    try {
      final response = await supabase
          .from('chat_members')
          .select('user_id')
          .eq('chat_id', widget.chatId)
          .count();
      if (mounted) {
        setState(() {
          _groupMemberCount = response.count;
        });
      }
    } catch (_) {
      // Falha silenciosa
    }
  }

  void _setReply(MessageModel msg) => setState(() => _replyingTo = msg);
  void _clearReply() => setState(() => _replyingTo = null);

  // ── Envio ─────────────────────────────────────────────────

  /// Ponte entre a tela e o composer unificado.
  ///
  /// [members] só é conhecido dentro do `Consumer` do rodapé; nas chamadas de
  /// fora (arrastar e soltar) a lista não faz falta.
  ChatComposerDelegate _composerDelegate({
    List<UserModel> members = const [],
    bool locked = false,
  }) {
    final notifier =
        ref.read(chatProvider(ChatArgs(chatId: widget.chatId)).notifier);

    return ChatComposerDelegate(
      notifier: notifier,
      chatName: widget.chatName,
      members: members,
      // Mídia respeita a resposta em curso; o vínculo é consumido no envio,
      // como acontece com o texto.
      replyingTo: _replyingTo,
      onReplyConsumed: _clearReply,
      onCancelReply: _clearReply,
      locked: locked,
      // Anúncio oficial só faz sentido em grupo: numa conversa de duas
      // pessoas, comunicado com confirmação de leitura é só uma mensagem.
      canAnnounce:
          widget.isGroup && ref.watch(canPublishAnnouncementProvider),
      onTypingChanged: (text) {
        if (text.trim().isNotEmpty) {
          final userName =
              ref.read(currentUserProvider).value?.fullName ?? 'Usuário';
          notifier.sendTypingEvent(userName);
        }
      },
    );
  }

  /// Arquivos soltos na janela (desktop): passam pelo mesmo preview do
  /// composer antes de subir, em vez de irem direto como documento.
  Future<void> _handleDroppedFiles(List<XFile> files) async {
    if (files.isEmpty) return;

    final preview = await ComposerMedia.previewFiles(
      context,
      files: files,
      destinationName: widget.chatName,
      allowViewOnce: true,
    );
    if (preview == null || preview.files.isEmpty || !mounted) return;

    await _composerDelegate().sendFromPreview(preview);
  }

  // ── Ações em lote da seleção múltipla ─────────────────────

  /// Mensagens carregadas correspondentes aos [ids], em ordem cronológica.
  List<MessageModel> _selectedMessages(Set<String> ids) {
    final all =
        ref.read(chatProvider(ChatArgs(chatId: widget.chatId))).messages;
    final picked = all.where((m) => ids.contains(m.id)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return picked;
  }

  /// Excluir em lote só é oferecido quando tudo na seleção é do próprio
  /// usuário — apagar mensagem de terceiro é ação de moderação, fora daqui.
  bool _canDeleteSelected(Set<String> ids) {
    final myId = supabase.auth.currentUser?.id;
    final picked = _selectedMessages(ids);
    return picked.isNotEmpty && picked.every((m) => m.senderId == myId);
  }

  void _endSelection() =>
      ref.read(messageSelectionProvider(widget.chatId).notifier).clear();

  Future<void> _forwardSelected(Set<String> ids) async {
    // Mídia de visualização única não se encaminha (burlaria o consumo).
    final picked =
        _selectedMessages(ids).where((m) => !m.isViewOnce).toList();
    if (picked.isEmpty) return;

    final target = await showForwardPicker(context, excludeId: widget.chatId);
    if (target == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    var sent = 0;
    try {
      // Em ordem cronológica para a conversa de destino ficar legível.
      for (final message in picked) {
        await MessageForwardService.forward(
          target: target,
          originalSenderName: message.sender?.fullName ?? 'Desconhecido',
          content: message.content,
          contentType: message.contentTypeString,
          mediaUrl: message.mediaUrl,
          metadata: {
            ...message.metadata,
            if (message.mediaMimeType != null)
              'media_mime_type': message.mediaMimeType,
            if (message.mediaSizeBytes != null)
              'media_size_bytes': message.mediaSizeBytes,
          },
        );
        sent++;
      }
      _endSelection();
      messenger.showSnackBar(
        SnackBar(
          content: Text(sent == 1
              ? 'Mensagem encaminhada para ${target.name}'
              : '$sent mensagens encaminhadas para ${target.name}'),
          backgroundColor: AppConstants.success,
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

  Future<void> _copySelected(Set<String> ids) async {
    final picked = _selectedMessages(ids);
    if (picked.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    await MessageBatchActions.copyToClipboard([
      for (final m in picked)
        SelectedMessage(
          id: m.id,
          senderName: m.sender?.fullName ?? 'Desconhecido',
          content: m.content,
          contentType: m.contentTypeString,
          mediaUrl: m.mediaUrl,
          metadata: m.metadata,
          createdAt: m.createdAt,
          isMine: m.senderId == supabase.auth.currentUser?.id,
        ),
    ]);

    _endSelection();
    messenger.showSnackBar(
      SnackBar(
        content: Text(picked.length == 1
            ? 'Mensagem copiada'
            : '${picked.length} mensagens copiadas'),
      ),
    );
  }

  Future<void> _starSelected(Set<String> selected) async {
    // Nem se favorita: ficaria acessível depois de aberta.
    final ids = _selectedMessages(selected)
        .where((m) => !m.isViewOnce)
        .map((m) => m.id)
        .toSet();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      final result = await MessageStarService.toggleAll(
        ids,
        scopeId: widget.chatId,
        isChannel: false,
      );
      _endSelection();
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

  Future<void> _deleteSelected(Set<String> ids) async {
    final picked = _selectedMessages(ids);
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

    final notifier =
        ref.read(chatProvider(ChatArgs(chatId: widget.chatId)).notifier);
    for (final message in picked) {
      await notifier.deleteMessage(message.id);
    }
    _endSelection();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider(ChatArgs(chatId: widget.chatId)));
    final notifier =
        ref.read(chatProvider(ChatArgs(chatId: widget.chatId)).notifier);
    final selection = ref.watch(messageSelectionProvider(widget.chatId));

    return DropTarget(
      onDragDone: (details) => _handleDroppedFiles(details.files),
      child: Scaffold(
        appBar: selection.active
            ? SelectionActionBar(
                count: selection.count,
                onClose: () => ref
                    .read(messageSelectionProvider(widget.chatId).notifier)
                    .clear(),
                onForward: () => _forwardSelected(selection.ids),
                onCopy: () => _copySelected(selection.ids),
                onStar: () => _starSelected(selection.ids),
                onDelete: _canDeleteSelected(selection.ids)
                    ? () => _deleteSelected(selection.ids)
                    : null,
                deleteDisabledReason: _canDeleteSelected(selection.ids)
                    ? null
                    : 'Só é possível excluir as suas próprias mensagens',
              )
            : ChatAppBar(
                chatId: widget.chatId,
                chatName: widget.chatName,
                isGroup: widget.isGroup,
                groupMemberCount: _groupMemberCount,
                onCreateMeetingRoom: () =>
                    _showCreateMeetingRoomDialog(context, ref),
                onJoinMeetingRoom: () =>
                    _showJoinMeetingRoomDialog(context, ref),
              ),
        floatingActionButton: _showScrollDownButton
            ? Padding(
                padding: const EdgeInsets.only(bottom: 80.0),
                child: FloatingActionButton.small(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  onPressed: () {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              )
            : null,
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Column(
          children: [
            ChatBanners(
              chatId: widget.chatId,
              chatName: widget.chatName,
            ),
            // ── Banner de mensagem fixada ────────────────────────
            if (state.pinnedMessage != null)
              GestureDetector(
                onTap: () {
                  final index = state.messages
                      .indexWhere((m) => m.id == state.pinnedMessage!.id);
                  if (index != -1 && _scrollController.hasClients) {
                    _scrollController.animateTo(
                      index * 80.0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    border: const Border(
                      bottom: BorderSide(color: Colors.amber, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.push_pin_rounded,
                          size: 16, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.pinnedMessage!.content ?? '📎 Mídia fixada',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => notifier.pinMessage(null),
                        child: Icon(Icons.close,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Lista de mensagens ───────────────────────────
            Expanded(
              child: ChatMessageList(
                chatId: widget.chatId,
                chatName: widget.chatName,
                isGroup: widget.isGroup,
                onReply: _setReply,
                scrollController: _scrollController,
              ),
            ),

            // Durante a seleção o rodapé é a barra de ações, não o input.
            if (selection.active)
              const SizedBox.shrink()
            else
              Consumer(builder: (context, ref, child) {
                final memberModels =
                    ref.watch(chatMembersProvider(widget.chatId)).valueOrNull ??
                        [];
                final members = memberModels.map((m) => m.user).toList();

                // Calcular se o chat de grupo possui envio de mensagens restrito a administradores
                bool isDisabled = false;
                if (widget.isGroup) {
                  final chatInfoArgs = ChatInfoArgs(
                    chatId: widget.chatId,
                    isGroup: true,
                  );
                  final chatInfoState =
                      ref.watch(chatInfoProvider(chatInfoArgs));
                  final chatDetails = chatInfoState.chatDetails;
                  final metadata =
                      chatDetails?['metadata'] as Map<String, dynamic>? ?? {};
                  final onlyAdminsSend = metadata['only_admins_send'] == true ||
                      metadata['only_admins_send']?.toString() == 'true';

                  final currentUserId = supabase.auth.currentUser?.id;
                  final isCurrentUserAdmin = memberModels
                      .any((m) => m.user.id == currentUserId && m.isAdminGroup);

                  isDisabled = onlyAdminsSend && !isCurrentUserAdmin;
                }

                return ConversationComposer(
                  delegate: _composerDelegate(
                    members: members,
                    locked: isDisabled,
                  ),
                );
              }), // <-- Close Builder
          ],
        ),
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
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
                hintText: 'Pauta da reunião',
              ),
              maxLines: 2,
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

              final currentUser = ref.read(currentUserProvider).value;
              if (currentUser == null) return;

              final roomId = await CallService.instance.createMeetingRoom(
                name: nameController.text.trim(),
                chatId: widget.chatId,
                description: descController.text.trim(),
              );

              if (roomId != null && context.mounted) {
                // Ao criar com sucesso, injeta o "Meeting Card" diretamente no histórico de mensagens do Chat!
                ref
                    .read(
                        chatProvider(ChatArgs(chatId: widget.chatId)).notifier)
                    .sendMeetingCard(roomId, nameController.text.trim());

                // Criador entra automaticamente na sala
                CallService.instance.joinMeetingRoom(
                  roomId: roomId,
                  userName: currentUser.fullName,
                );
              }
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );
  }

  void _showJoinMeetingRoomDialog(BuildContext context, WidgetRef ref) {
    final roomIdController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entrar em Sala de Reunião'),
        content: TextField(
          controller: roomIdController,
          decoration: const InputDecoration(
            labelText: 'ID da Sala',
            hintText: 'Cole o ID da sala aqui',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (roomIdController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Digite o ID da sala')),
                );
                return;
              }

              Navigator.pop(ctx);

              final currentUser = ref.read(currentUserProvider).value;
              if (currentUser == null) return;

              await CallService.instance.joinMeetingRoom(
                roomId: roomIdController.text.trim(),
                userName: currentUser.fullName,
              );
            },
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
  }
}
