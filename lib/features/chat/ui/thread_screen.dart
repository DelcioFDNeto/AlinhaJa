import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/chat/providers/chat_provider.dart';
import 'package:alinha_ja/features/chat/ui/widgets/message_bubble.dart';
import 'package:alinha_ja/core/ui/composer/conversation_composer.dart';
import 'package:alinha_ja/features/chat/ui/widgets/chat_composer_delegate.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';

/// Tela de Thread (Tópico) — exibe a mensagem original fixada no topo
/// e as respostas a ela (onde message.thread_id == parentMessage.id)
class ThreadScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String chatName;
  final MessageModel parentMessage;

  const ThreadScreen({
    super.key,
    required this.chatId,
    required this.chatName,
    required this.parentMessage,
  });

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _scrollController = ScrollController();
  MessageModel? _replyingTo;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref
          .read(chatProvider(ChatArgs(
                  chatId: widget.chatId, threadId: widget.parentMessage.id))
              .notifier)
          .loadMore();
    }
  }

  void _clearReply() => setState(() => _replyingTo = null);

  @override
  Widget build(BuildContext context) {
    // Escuta apenas as mensagens atreladas a esta thread
    final threadArgs =
        ChatArgs(chatId: widget.chatId, threadId: widget.parentMessage.id);
    final state = ref.watch(chatProvider(threadArgs));
    final notifier = ref.read(chatProvider(threadArgs).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tópico'),
            Text(
              widget.chatName,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Parent Message (Fixada no Topo) ──
          Container(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.3),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MessageBubble(
                  message: widget.parentMessage,
                  isMe: widget.parentMessage.senderId ==
                      ref.read(currentUserProvider).value?.id,
                  isGroup:
                      false, // Pode ser grupo, mas no contexto do topico tanto faz
                  allMessages: [widget.parentMessage],
                  reactions: const [], // Reações na parent message simplificadas por hora
                  onToggleReaction: (_) {},
                  onAcknowledge: null,
                ),
                const SizedBox(height: 8),
                const Divider(),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    '${state.messages.length} respostas',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Thread Replies ──
          Expanded(
            child: state.isLoading && state.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true, // Começa de baixo pra cima
                    padding: const EdgeInsets.all(16),
                    itemCount: state.messages.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == state.messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final message = state.messages[index];
                      final isMine = message.senderId ==
                          ref.read(currentUserProvider).value?.id;
                      final msgReactions = state.reactions[message.id] ?? [];

                      return GestureDetector(
                        onLongPress: isMine
                            ? () {
                                // Apagar mensagem simplificado para threads
                                showDialog(
                                  context: context,
                                  builder: (dCtx) => AlertDialog(
                                    title: const Text('Apagar mensagem?'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(dCtx),
                                          child: const Text('Cancelar')),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(dCtx);
                                          notifier.deleteMessage(message.id);
                                        },
                                        child: const Text('Apagar',
                                            style:
                                                TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            : null,
                        child: MessageBubble(
                          message: message,
                          isMe: isMine,
                          isGroup:
                              true, // Sempre verdadeiro para mostrar avatares na thread
                          allMessages: state.messages,
                          quoted: message.replyTo == widget.parentMessage.id
                              ? widget.parentMessage
                              : state.quotedFor(message),
                          reactions: msgReactions,
                          onToggleReaction: (emoji) =>
                              notifier.toggleReaction(message.id, emoji),
                          onAcknowledge: null,
                        ),
                      );
                    },
                  ),
          ),

          // ── Input ────────────────────────────────────────
          ConversationComposer(
            delegate: ChatComposerDelegate(
              notifier: notifier,
              chatName: widget.chatName,
              replyingTo: _replyingTo,
              onReplyConsumed: _clearReply,
              onCancelReply: _clearReply,
            ),
          ),
        ],
      ),
    );
  }
}
