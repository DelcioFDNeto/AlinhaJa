import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/models/message_receipts.dart';
import 'package:alinha_ja/core/providers/message_selection_provider.dart';
import 'package:alinha_ja/core/services/message_forward_service.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/widgets/forward_picker_sheet.dart';
import 'package:alinha_ja/core/widgets/message_info_sheet.dart';
import 'package:alinha_ja/core/widgets/selection_action_bar.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/chat/providers/chat_provider.dart';
import 'package:alinha_ja/features/chat/ui/widgets/message_bubble.dart';
import 'package:alinha_ja/features/chats/ui/chats_list_screen.dart';
import 'package:alinha_ja/core/extensions.dart';

class ChatMessageList extends ConsumerWidget {
  final String chatId;
  final String chatName;
  final bool isGroup;
  final void Function(MessageModel) onReply;
  final ScrollController? scrollController;

  const ChatMessageList({
    super.key,
    required this.chatId,
    required this.chatName,
    required this.isGroup,
    required this.onReply,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatProvider(ChatArgs(chatId: chatId)));
    final notifier = ref.read(chatProvider(ChatArgs(chatId: chatId)).notifier);
    final myId = supabase.auth.currentUser?.id;
    final selection = ref.watch(messageSelectionProvider(chatId));
    final selectionNotifier =
        ref.read(messageSelectionProvider(chatId).notifier);

    final filteredMessages = state.searchQuery.isEmpty
        ? state.messages
        : state.messages
            .where((m) => (m.content ?? '')
                .toLowerCase()
                .contains(state.searchQuery.toLowerCase()))
            .toList();

    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Erro ao carregar mensagens'),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              onPressed: () =>
                  ref.invalidate(chatProvider(ChatArgs(chatId: chatId))),
            ),
          ],
        ),
      );
    }

    if (state.messages.isEmpty) {
      final chatsList = ref.watch(chatsListProvider).valueOrNull ?? [];
      final chatModel = chatsList.firstWhereOrNull((c) => c.id == chatId);
      final avatarUrl = isGroup ? null : chatModel?.otherUser?.avatarUrl;

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: avatarUrl != null
                  ? CachedNetworkImageProvider(avatarUrl, maxWidth: 320)
                  : null,
              child: avatarUrl == null
                  ? Icon(
                      isGroup ? Icons.groups_rounded : Icons.person_rounded,
                      size: 40,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              chatName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Vocês ainda não conversaram — diga olá 👋',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (state.searchQuery.isNotEmpty && filteredMessages.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma mensagem encontrada para "${state.searchQuery}"',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 100) {
          notifier.loadMore();
        }
        return false;
      },
      child: ListView.builder(
        controller: scrollController,
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: filteredMessages.length,
        itemBuilder: (context, index) {
          final message = filteredMessages[index];
          final isMine = message.senderId == myId;
          final msgReactions = state.reactions[message.id] ?? [];

          // ── Grouping Logic ──
          const groupTimeThreshold = Duration(minutes: 2);
          bool isFirstInGroup = true;
          bool isLastInGroup = true;

          if (index > 0) {
            final prev = filteredMessages[index - 1];
            if (prev.senderId == message.senderId &&
                !prev.isBot &&
                !message.isBot &&
                prev.createdAt.difference(message.createdAt).abs() <
                    groupTimeThreshold) {
              isLastInGroup = false;
            }
          }

          if (index < filteredMessages.length - 1) {
            final next = filteredMessages[index + 1];
            if (next.senderId == message.senderId &&
                !next.isBot &&
                !message.isBot &&
                message.createdAt.difference(next.createdAt).abs() <
                    groupTimeThreshold) {
              isFirstInGroup = false;
            }
          }

          // ── Separador de Data ──
          Widget? dateSeparator;
          final currentDate = DateTime(
            message.createdAt.toLocal().year,
            message.createdAt.toLocal().month,
            message.createdAt.toLocal().day,
          );

          bool showDate = false;
          if (index == filteredMessages.length - 1) {
            // Última mensagem (mais antiga), sempre exibe a data
            showDate = true;
          } else {
            final nextMessage = filteredMessages[index + 1];
            final nextDate = DateTime(
              nextMessage.createdAt.toLocal().year,
              nextMessage.createdAt.toLocal().month,
              nextMessage.createdAt.toLocal().day,
            );
            showDate = currentDate != nextDate;
          }

          if (showDate) isFirstInGroup = true;

          if (showDate) {
            dateSeparator = Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  message.createdAt.dateSeparatorFormatted,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dateSeparator != null) dateSeparator,
              Dismissible(
                key: ValueKey('swipe-${message.id}'),
                // Durante a seleção o swipe sairia por cima do gesto de marcar.
                direction: selection.active
                    ? DismissDirection.none
                    : DismissDirection.startToEnd,
                confirmDismiss: (direction) async {
                  if (!message.isOptimistic) {
                    onReply(message);
                  }
                  return false;
                },
                background: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 16.0),
                  color: Colors.transparent,
                  child: Icon(Icons.reply_rounded,
                      color: Theme.of(context).colorScheme.primary),
                ),
                child: GestureDetector(
                  onTap: selection.active && !message.isOptimistic
                      ? () => selectionNotifier.toggle(message.id)
                      : null,
                  onDoubleTap: selection.active ||
                          message.isOptimistic ||
                          message.isDeleted
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          notifier.toggleReaction(message.id, '👍');
                        },
                  onLongPress: message.isOptimistic || message.isDeleted
                      ? null
                      : () {
                          if (selection.active) {
                            selectionNotifier.toggle(message.id);
                            return;
                          }
                          _showMessageOptions(
                            context,
                            ref,
                            message,
                            chatId,
                            isMine,
                          );
                        },
                  child: MessageSelectionWrapper(
                    active: selection.active,
                    selected: selection.contains(message.id),
                    child: MessageBubble(
                      message: message,
                      isMe: isMine,
                      isGroup: isGroup,
                      isFirstInGroup: isFirstInGroup,
                      isLastInGroup: isLastInGroup,
                      allMessages: state.messages,
                      quoted: state.quotedFor(message),
                      reactions: msgReactions,
                      onToggleReaction: (emoji) {
                        notifier.toggleReaction(message.id, emoji);
                      },
                      onAcknowledge: () {
                        notifier.acknowledgeMessage(message.id);
                      },
                      onCancelUpload:
                          message.isOptimistic && message.localFilePath != null
                              ? () => notifier.cancelUpload(message.id)
                              : null,
                      onRetryUpload: message.status == MessageStatus.error &&
                              message.localFilePath != null
                          ? () => notifier.retryMedia(message)
                          : null,
                      onTapThread: () {
                        context
                            .push('/chat/$chatId/thread/${message.id}', extra: {
                          'chatName': chatName,
                          'parentMessage': message,
                        });
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Trecho da mensagem para a folha de informações.
  ///
  /// Mídia sem legenda não tem texto nenhum; sem um rótulo, a folha abriria
  /// só com uma lista de nomes e sem dizer de qual mensagem se trata.
  static String _messagePreview(MessageModel message) {
    final text = message.content?.trim() ?? '';
    if (text.isNotEmpty) return text;

    return switch (message.contentType) {
      ContentType.image => 'Foto',
      ContentType.video => 'Vídeo',
      ContentType.audio => 'Áudio',
      ContentType.file => 'Arquivo',
      ContentType.meeting => 'Reunião',
      ContentType.text => 'Mensagem',
    };
  }

  void _showMessageOptions(
    BuildContext context,
    WidgetRef ref,
    MessageModel message,
    String chatId,
    bool isMine,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      ref
                          .read(chatProvider(ChatArgs(chatId: chatId)).notifier)
                          .toggleReaction(message.id, emoji);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.reply_rounded,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('Responder'),
              onTap: () {
                Navigator.pop(ctx);
                onReply(message);
              },
            ),
            ListTile(
              leading: Icon(Icons.checklist,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('Selecionar'),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(messageSelectionProvider(chatId).notifier)
                    .start(message.id);
              },
            ),
            if (!message.isBot)
              ListTile(
                leading: Icon(Icons.forum_outlined,
                    color: Theme.of(context).colorScheme.secondary),
                title: const Text('Responder em Tópico'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/chat/$chatId/thread/${message.id}', extra: {
                    'chatName': chatName,
                    'parentMessage': message,
                  });
                },
              ),
            // Mídia de visualização única não sai da conversa: encaminhar
            // copiava a URL (burlando o consumo), e fixar/favoritar a
            // deixariam acessível depois de aberta.
            if (!message.isViewOnce)
            ListTile(
              leading: const Icon(Icons.shortcut_rounded, color: Colors.teal),
              title: const Text('Encaminhar'),
              onTap: () {
                Navigator.pop(ctx);
                _showForwardPicker(context, ref, message);
              },
            ),
            if (!message.isViewOnce)
            ListTile(
              leading: const Icon(Icons.push_pin_rounded, color: Colors.amber),
              title: const Text('Fixar Mensagem'),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(chatProvider(ChatArgs(chatId: chatId)).notifier)
                    .pinMessage(message.id);
              },
            ),
            // Mensagem otimista ainda não existe no banco: abrir os recibos
            // dela daria "mensagem não encontrada".
            if (!message.isOptimistic)
              ListTile(
                leading: Icon(Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Informações'),
                subtitle: Text(
                  isGroup
                      ? 'Quem do grupo recebeu e leu'
                      : 'Quando foi recebida e lida',
                  style: const TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  MessageInfoSheet.show(
                    context,
                    messageId: message.id,
                    scope: ReceiptScope.chat,
                    preview: _messagePreview(message),
                  );
                },
              ),
            if (!message.isViewOnce)
            ListTile(
              leading:
                  const Icon(Icons.star_outline_rounded, color: Colors.amber),
              title: const Text('⭐ Favoritar'),
              onTap: () async {
                Navigator.pop(ctx);
                final myId = supabase.auth.currentUser?.id;
                if (myId == null) return;
                try {
                  final existing = await supabase
                      .from('starred_messages')
                      .select('id')
                      .eq('user_id', myId)
                      .eq('chat_message_id', message.id)
                      .maybeSingle();

                  if (existing != null) {
                    await supabase
                        .from('starred_messages')
                        .delete()
                        .eq('id', existing['id']);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Mensagem removida dos favoritos.')),
                      );
                    }
                  } else {
                    await supabase.from('starred_messages').insert({
                      'user_id': myId,
                      'chat_message_id': message.id,
                      'chat_id': chatId,
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('⭐ Mensagem favoritada!')),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Erro ao favoritar: $e'),
                          backgroundColor: AppConstants.danger),
                    );
                  }
                }
              },
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppConstants.danger),
                title: const Text('Apagar mensagem'),
                onTap: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('Apagar mensagem?'),
                      content: const Text(
                          'A mensagem será removida do chat para todos.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(dCtx);
                            ref
                                .read(chatProvider(ChatArgs(chatId: chatId))
                                    .notifier)
                                .deleteMessage(message.id);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppConstants.danger,
                          ),
                          child: const Text('Apagar'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (isMine && message.contentType == ContentType.text)
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.blue),
                title: const Text('Editar mensagem'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditMessageDialog(context, ref, message, chatId);
                },
              ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Excluir definitivamente'),
                subtitle: Text(
                  'Remove do banco permanentemente',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showPermanentDeleteDialog(context, ref, message, chatId);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showEditMessageDialog(
    BuildContext context,
    WidgetRef ref,
    MessageModel message,
    String chatId,
  ) {
    final controller = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Editar mensagem'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Digite o novo conteúdo...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final newContent = controller.text.trim();
              if (newContent.isNotEmpty && newContent != message.content) {
                ref
                    .read(chatProvider(ChatArgs(chatId: chatId)).notifier)
                    .editMessage(message.id, newContent);
              }
              Navigator.pop(dCtx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _showPermanentDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    MessageModel message,
    String chatId,
  ) {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Excluir permanentemente?'),
        content: const Text(
          'Esta ação NÃO pode ser desfeita. A mensagem será excluída do banco de dados completamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dCtx);
              ref
                  .read(chatProvider(ChatArgs(chatId: chatId)).notifier)
                  .permanentlyDeleteMessage(message.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Future<void> _showForwardPicker(
    BuildContext context,
    WidgetRef ref,
    MessageModel message,
  ) async {
    final target = await showForwardPicker(context, excludeId: chatId);
    if (target == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
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
      messenger.showSnackBar(
        SnackBar(
          content: Text('Mensagem encaminhada para ${target.name}'),
          backgroundColor: AppConstants.success,
        ),
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
}
