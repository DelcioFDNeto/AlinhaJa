import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/channels/models/channel_message_model.dart';
import 'package:alinha_ja/features/channels/providers/active_channel_provider.dart';
import 'package:alinha_ja/core/ui/composer/conversation_composer.dart';
import 'package:alinha_ja/features/channels/ui/widgets/channel_composer_delegate.dart';
import 'package:alinha_ja/features/channels/ui/widgets/channel_message_bubble.dart';

class ChannelThreadScreen extends ConsumerStatefulWidget {
  final ChannelMessageModel parentMessage;
  final String senderName; // Nome do criador do topico original

  const ChannelThreadScreen({
    super.key,
    required this.parentMessage,
    required this.senderName,
  });

  @override
  ConsumerState<ChannelThreadScreen> createState() =>
      _ChannelThreadScreenState();
}

class _ChannelThreadScreenState extends ConsumerState<ChannelThreadScreen> {
  /// Provider desta thread: mesmo canal, filtrado pelo tópico.
  ChannelArgs get _threadArgs => ChannelArgs(
        channelId: widget.parentMessage.channelId,
        parentMessageId: widget.parentMessage.id,
      );

  String? _senderNameFor(ChannelMessageModel? msg, ChannelState state) {
    if (msg == null) return null;
    if (msg.senderId == supabase.auth.currentUser?.id) return 'Você';
    if (msg.id == widget.parentMessage.id) return widget.senderName;
    return state.userCache[msg.senderId]?.fullName ?? 'Membro';
  }

  @override
  Widget build(BuildContext context) {
    // Escuta o provider com este `parentMessageId` para pegar apenas respostas desse tópico!
    final state = ref.watch(activeChannelProvider(_threadArgs));
    final isMe = widget.senderName ==
        'Você'; // simplificacao baseada no senderName pre-computado

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Respostas',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Tópico #${widget.parentMessage.channelId.substring(0, 4)}...',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 1. Mensagem Raiz (Parent Message) exibida na íntegra
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ChannelMessageBubble(
              message: widget.parentMessage,
              isMe: isMe,
              senderName: widget.senderName,
              // Ao estarmos no tópico, não precisamos do botão de abrir tópico da raiz de novo.
            ),
          ),

          // Divisor Visual Elegante
          Row(
            children: [
              Expanded(
                  child: Divider(
                      color: Theme.of(context).colorScheme.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${state.messages.length} Respostas',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              Expanded(
                  child: Divider(
                      color: Theme.of(context).colorScheme.outlineVariant)),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Stream de Respostas
          Expanded(
            child: state.isLoading && state.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    reverse:
                        true, // as mensagens do provedor estão sorteadas em ordem decrescente
                    itemCount: state.messages.length,
                    itemBuilder: (context, index) {
                      final msg = state.messages[index];
                      final isReplyMe =
                          msg.senderId == supabase.auth.currentUser?.id;

                      final senderUser = state.userCache[msg.senderId];
                      final senderName = isReplyMe
                          ? 'Você'
                          : (senderUser?.fullName ??
                              'Membro ${msg.senderId.substring(0, 4)}');

                      final quoted = msg.replyTo == widget.parentMessage.id
                          ? widget.parentMessage
                          : state.quotedFor(msg);

                      return ChannelMessageBubble(
                        message: msg,
                        isMe: isReplyMe,
                        senderName: senderName,
                        quoted: quoted,
                        quotedSenderName: _senderNameFor(quoted, state),
                      );
                    },
                  ),
          ),

          // 3. Input de Resposta — mesmo composer das demais conversas, então
          // a thread também aceita anexos, enquete, evento e localização.
          ConversationComposer(
            delegate: ChannelComposerDelegate(
              notifier: ref.read(activeChannelProvider(_threadArgs).notifier),
              channelName: 'tópico',
              members: state.userCache.values.toList(),
              replyingTo: state.replyingTo,
            ),
          ),
        ],
      ),
    );
  }
}
