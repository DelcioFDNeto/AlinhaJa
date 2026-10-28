import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/extensions.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/features/chat/providers/chat_provider.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/services/media_cache_manager.dart';
import 'package:alinha_ja/core/models/announcement_spec.dart';
import 'package:alinha_ja/core/models/message_extras.dart';
import 'package:alinha_ja/core/models/message_ref.dart';
import 'package:alinha_ja/core/ui/message_cards/announcement_card.dart';
import 'package:alinha_ja/core/ui/message_cards/structured_message_card.dart';
import 'package:alinha_ja/core/services/media_url_resolver.dart';
import 'package:alinha_ja/core/widgets/signed_network_image.dart';
import 'package:alinha_ja/features/chat/ui/widgets/view_once_bubble.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:alinha_ja/core/brand/org_identity.dart';

/// Balão de mensagem que adapta sua exibição ao [ContentType]:
/// - **text** — texto simples
/// - **image** — FileImage (otimista) ou NetworkImage (confirmada)
/// - **audio** — botão de reprodução + waveform decorativo
/// - **file** — ícone + nome do arquivo
class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool isGroup;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final VoidCallback? onAcknowledge;

  /// Lista onde procurar a mensagem citada. Quando a original está fora da
  /// página carregada, use [quoted] — resolvido pelo provider.
  final List<MessageModel> allMessages;
  final MessageModel? quoted;
  final List<Map<String, dynamic>> reactions;
  final ValueChanged<String>? onToggleReaction;
  final VoidCallback? onTapThread;

  /// Cancela o upload em andamento desta mensagem otimista.
  final VoidCallback? onCancelUpload;

  /// Reenvia uma mídia cujo upload falhou.
  final VoidCallback? onRetryUpload;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isGroup = false,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.onAcknowledge,
    this.allMessages = const [],
    this.quoted,
    this.reactions = const [],
    this.onToggleReaction,
    this.onTapThread,
    this.onCancelUpload,
    this.onRetryUpload,
  });

  @override
  Widget build(BuildContext context) {
    // ── Mensagem apagada (soft delete) — exibe placeholder estilo WhatsApp ──
    if (message.isDeleted) {
      return _buildDeletedBubble(context);
    }

    // ── Layout especial para mensagens de Bot/Webhook ──
    if (message.isBot) {
      return _buildBotBubble(context);
    }

    return Consumer(
      builder: (context, ref, child) {
        final chatState = ref.watch(chatProvider(
            ChatArgs(chatId: message.chatId, threadId: message.threadId)));

        final theme = Theme.of(context);

        // ── Detecção de menção pessoal ──
        final currentUserId = supabase.auth.currentUser?.id;
        final mentions = (message.metadata['mentions'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final isMentioned =
            currentUserId != null && mentions.contains(currentUserId);

        // O layout "WhatsApp Corporativo": mensagens próprias à direita, as outras à esquerda.
        // As cores agora usam a paleta real do tema logado (mais visibilidade/contraste).
        final isMyMessage = isMe;
        Color bubbleColor;
        if (isMentioned && !isMyMessage) {
          // Alerta pessoal: destaque sutil para menção direta
          bubbleColor = theme.colorScheme.tertiary.withValues(alpha: 0.15);
        } else if (isMyMessage) {
          bubbleColor = theme.colorScheme.primary.withValues(alpha: 0.85);
        } else {
          bubbleColor = theme.colorScheme.surfaceContainerHigh;
        }

        final textColor = isMyMessage
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface;

        return Align(
          alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(
              left: isMyMessage ? 48 : 12,
              right: isMyMessage ? 12 : 48,
              top: isFirstInGroup ? 8 : 2,
              bottom: isLastInGroup ? 6 : 1,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ── AVATAR (Apenas na base do grupo para outras pessoas) ──
                if (!isMyMessage && isGroup)
                  if (isLastInGroup)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        backgroundImage: message.sender?.avatarUrl != null
                            ? CachedNetworkImageProvider(
                                message.sender!.avatarUrl!, maxWidth: 320)
                            : null,
                        child: message.sender?.avatarUrl == null
                            ? Text(
                                message.sender?.fullName.isNotEmpty == true
                                    ? message.sender!.fullName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              )
                            : null,
                      ),
                    )
                  else
                    const SizedBox(
                        width: 36), // Reservar o espaço do Avatar (28 + 8)

                // ── BOLHA DA MENSAGEM ──
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Container(
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(
                              isMyMessage || !isFirstInGroup ? 16 : 4),
                          topRight: Radius.circular(
                              !isMyMessage || !isFirstInGroup ? 16 : 4),
                          bottomLeft: const Radius.circular(16),
                          bottomRight: const Radius.circular(16),
                        ),
                        boxShadow: [
                          if (isFirstInGroup)
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Nome do remetente (apenas topo do grupo de outros)
                            if (!isMyMessage && isGroup && isFirstInGroup)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  message.sender?.fullName ?? 'Usuário',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme
                                        .primary, // Nome sempre na cor primária para destaque
                                  ),
                                ),
                              ),

                            // Header de Encaminhada
                            if (message.metadata['forwarded_from'] != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.shortcut_rounded,
                                        size: 14,
                                        color:
                                            textColor.withValues(alpha: 0.7)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Encaminhada de ${message.metadata['forwarded_from']}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: textColor.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Corpo da Mensagem (Passamos a cor de texto ideal!)
                            // *Nota*: O _buildContent agora herdará o estilo da bolha.
                            _buildContent(context, ref,
                                chatState.latestReadByOthers, textColor),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Layout diferenciado para mensagens de Bot/Sistema/Webhook.
  Widget _buildBotBubble(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = (constraints.maxWidth * 0.85).clamp(260.0, 640.0);
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            constraints: BoxConstraints(maxWidth: maxWidth.toDouble()),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.tertiary,
                  width: 4,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header do Bot
                  Row(
                    children: [
                      Icon(
                        Icons.smart_toy_rounded,
                        size: 18,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        message.sender?.fullName ?? 'Sistema',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        message.createdAt.timeFormatted,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Conteúdo da mensagem
                  if (message.content != null && message.content!.isNotEmpty)
                    Text(
                      message.content!,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Placeholder visual para mensagem apagada (soft delete) — estilo WhatsApp.
  Widget _buildDeletedBubble(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 48 : 12,
          right: isMe ? 12 : 48,
          top: isFirstInGroup ? 8 : 2,
          bottom: isLastInGroup ? 6 : 1,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:
                theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.block_rounded,
                size: 16,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Text(
                isMe ? 'Você apagou esta mensagem' : 'Mensagem apagada',
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref,
      DateTime? latestRead, Color textColor) {
    // Busca a mensagem citada: primeiro na página carregada, depois no que o
    // provider resolveu para citações antigas.
    MessageModel? quotedMsg = quoted;
    if (quotedMsg == null && message.replyTo != null) {
      for (final m in allMessages) {
        if (m.id == message.replyTo) {
          quotedMsg = m;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (quotedMsg != null) _buildQuoteCard(context, quotedMsg, textColor),

        // Passar a textColor para o _buildBody customizar seu texto!
        Theme(
          data: Theme.of(context).copyWith(
            textTheme: Theme.of(context).textTheme.apply(
                  bodyColor: textColor,
                  displayColor: textColor,
                ),
            iconTheme: IconThemeData(color: textColor),
          ),
          child: DefaultTextStyle(
            style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
            child: _buildBody(context, ref),
          ),
        ),

        // Footer in-bubble (Horário e Status)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (message.isEdited) ...[
                Text(
                  'editado',
                  style: TextStyle(
                    fontSize: 10,
                    color: textColor.withValues(alpha: 0.5),
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                message.createdAt.timeFormatted,
                style: TextStyle(
                  fontSize: 10,
                  color: textColor.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                Builder(
                  builder: (context) {
                    final bool isReadByOthers = latestRead != null &&
                        (message.createdAt.isBefore(latestRead) ||
                            message.createdAt.isAtSameMomentAs(latestRead));

                    final bool isRead =
                        message.status == MessageStatus.read || isReadByOthers;

                    // Entrega é um estado próprio ('delivered'): confirmado
                    // pelo destinatário ao receber. Um 'sent' continua com
                    // um único check até isso acontecer.
                    final bool isDelivered =
                        message.status == MessageStatus.delivered;

                    IconData icon;
                    Color color;

                    if (message.status == MessageStatus.sending) {
                      icon = Icons.access_time_rounded;
                      color = textColor.withValues(alpha: 0.4);
                    } else if (message.status == MessageStatus.error) {
                      icon = Icons.error_outline_rounded;
                      color = Theme.of(context).colorScheme.error;
                    } else if (isRead) {
                      icon = Icons.done_all_rounded;
                      // Azul vibrante padrão do WhatsApp/Telegram
                      color = const Color(0xFF00B4D8);
                    } else if (isDelivered) {
                      icon = Icons.done_all_rounded;
                      color = textColor.withValues(alpha: 0.5);
                    } else {
                      icon = Icons.check_rounded;
                      color = textColor.withValues(alpha: 0.5);
                    }

                    return Icon(icon, size: 14, color: color);
                  },
                ),
              ]
            ],
          ),
        ),

        if (reactions.isNotEmpty) _buildReactionsRow(context),

        // Em um Layout Corporativo, o botão da Thread se mescla à bolha
        // Agora, por regra de negócios, Threads são exclusivas para CANAIS.
        // Botão de Thread / Respostas retirado definitivamente de DMs/Grupos.
        // Apenas canais no 'ChannelMessageBubble' terão botão de Thread no novo fluxo.
        if (message.requiresAcknowledgement && !isMe)
          _buildAcknowledgeButton(context),
      ],
    );
  }

  bool isOnTapThreadProvided() => onTapThread != null;

  /// Exibe emojis agrupados com contagem abaixo da mensagem.
  Widget _buildReactionsRow(BuildContext context) {
    // Agrupa por emoji
    final grouped = <String, int>{};
    for (final r in reactions) {
      final emoji = r['emoji'] as String;
      grouped[emoji] = (grouped[emoji] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 4),
      child: Wrap(
        spacing: 4,
        children: grouped.entries.map((e) {
          return GestureDetector(
            onTap: () => onToggleReaction?.call(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isMe
                    ? Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer
                        .withValues(alpha: 0.15)
                    : Theme.of(context)
                        .colorScheme
                        .onSecondaryContainer
                        .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${e.key} ${e.value}',
                style: TextStyle(
                  fontSize: 13,
                  color: isMe
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildQuoteCard(
      BuildContext context, MessageModel quoted, Color textColor) {
    String previewText;
    if (quoted.isDeleted) {
      previewText = 'Mensagem apagada';
    } else {
      switch (quoted.contentType) {
        case ContentType.image:
          previewText = '📷 Foto';
          break;
        case ContentType.audio:
          previewText = '🎙️ Áudio';
          break;
        case ContentType.file:
          previewText =
              '📎 ${quoted.metadata['original_filename'] ?? 'Documento'}';
          break;
        case ContentType.text:
          previewText = quoted.content ?? '';
          break;
        case ContentType.video:
          previewText = '📹 Vídeo';
          break;
        case ContentType.meeting:
          previewText = '📹 Reunião';
          break;
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: textColor.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
      ),
      child: Text(
        previewText,
        style: TextStyle(
          fontSize: 13,
          color: textColor.withValues(alpha: 0.8),
          fontStyle: quoted.isDeleted ? FontStyle.italic : FontStyle.normal,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildAcknowledgeButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 8, top: 2),
      child: message.acknowledgedByMe
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    color: AppConstants.success, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Ciência confirmada',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppConstants.success.withValues(alpha: 0.9),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          : ElevatedButton.icon(
              onPressed: onAcknowledge,
              icon: const Icon(Icons.verified_user_outlined, size: 16),
              label: const Text('Estou Ciente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.corMarca,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref) {
    if (message.isViewOnce && !isMe) {
      return ViewOnceBubble(
        message: message,
        videoBuilder: (_) => _VideoPlayerWidget(message: message, isMe: isMe),
      );
    }
    if (message.isViewOnce && isMe) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_off_outlined, size: 16),
            SizedBox(width: 8),
            Text('Mensagem de visualização única enviada',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ),
      );
    }

    switch (message.contentType) {
      case ContentType.image:
        return _buildImageBody(context);
      case ContentType.audio:
        return _AudioPlayerWidget(message: message, isMe: isMe);
      case ContentType.video:
        return _VideoPlayerWidget(message: message, isMe: isMe);
      case ContentType.file:
        return _buildFileBody(context);
      case ContentType.text:
        // Anúncio oficial em grupo: mesmo card dos canais.
        if (message.metadata['type'] == MessageExtras.typeAnnouncement) {
          return _buildAnnouncementBody(context);
        }
        // Enquete, evento, localização e contato chegam como texto com
        // `metadata.type` — o card certo sai do widget compartilhado.
        if (StructuredMessageCard.handles(message.metadata)) {
          return _buildStructuredBody(context);
        }
        return _buildTextBody(context);
      case ContentType.meeting:
        return _buildMeetingBody(context);
    }
  }

  /// Anúncio oficial em grupo — mesmo card usado nos canais.
  Widget _buildAnnouncementBody(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: DefaultTextStyle(
        style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
        child: AnnouncementCard(
          message: MessageRef.chat(message.id),
          spec: AnnouncementSpec.fromMetadata(message.metadata),
          content: message.content,
          senderName: message.sender?.fullName ?? 'Anúncio',
          isMine: isMe,
        ),
      ),
    );
  }

  /// Cards de conteúdo estruturado ficam sobre um fundo neutro: dentro da bolha
  /// colorida do remetente o contraste do card não se sustenta.
  Widget _buildStructuredBody(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
        child: Theme(
          data: theme,
          child: StructuredMessageCard(
            message: MessageRef.chat(message.id),
            metadata: message.metadata,
            content: message.content,
          ),
        ),
      ),
    );
  }

  // ── Tipos de conteúdo ────────────────────────────────────

  Widget _buildMeetingBody(BuildContext context) {
    // Pegar cor baseada no fato de ser "minha" ou não
    final isMyMessage = isMe;
    final theme = Theme.of(context);

    final roomName = message.content ?? 'Reunião';
    final roomId = message.metadata['room_id'] as String?;
    final meetingStatus = message.metadata['status'] as String?;
    final isEnded = meetingStatus == 'ended';

    // As cores do Card se adaptam por conta do Container pai (cor de bolha),
    // mas adicionaremos um destaque interno para o card
    return Container(
      width: 260,
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: isMyMessage
            ? theme.colorScheme.onPrimary.withValues(alpha: 0.15)
            : theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMyMessage
              ? theme.colorScheme.onPrimary.withValues(alpha: 0.3)
              : theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de topo com ícone
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isEnded
                  ? Colors.grey.withValues(alpha: 0.2)
                  : isMyMessage
                      ? theme.colorScheme.onPrimary.withValues(alpha: 0.1)
                      : theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.video_camera_front_rounded,
                  color: isMyMessage
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    roomName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isEnded
                          ? Colors.grey
                          : isMyMessage
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Corpo com o botão de ingressar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEnded
                      ? 'Esta reunião foi encerrada.'
                      : 'Clique no botão abaixo para ingressar nesta sala de reunião com vídeo e áudio.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isEnded
                        ? Colors.grey
                        : isMyMessage
                            ? theme.colorScheme.onPrimary
                                .withValues(alpha: 0.85)
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: (roomId == null || isEnded)
                      ? null
                      : () async {
                          debugPrint(
                              'MeetingCard: Tentando entrar na sala $roomId');
                          final currentUser = supabase.auth.currentUser;
                          if (currentUser == null) {
                            debugPrint('MeetingCard: Usuario nao autenticado');
                            return;
                          }

                          // Busca nome do usuario atual no provider ou DB (fallback pra "Voce")
                          String joinName = 'Participante';
                          try {
                            final response = await supabase
                                .from('users')
                                .select('full_name')
                                .eq('id', currentUser.id)
                                .maybeSingle();
                            if (response != null &&
                                response['full_name'] != null) {
                              joinName = response['full_name'] as String;
                            }
                          } catch (_) {}

                          debugPrint(
                              'MeetingCard: Chamando joinMeetingRoom com userName=$joinName');
                          try {
                            await CallService.instance.joinMeetingRoom(
                                roomId: roomId, userName: joinName);
                            debugPrint(
                                'MeetingCard: joinMeetingRoom retornou com sucesso');
                          } catch (e, stack) {
                            debugPrint(
                                'MeetingCard: ERRO ao entrar na sala: $e');
                            debugPrint('MeetingCard: Stack: $stack');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('Erro ao entrar na reuniao: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Ingressar na Sala',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isMyMessage
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.primary,
                    foregroundColor: isMyMessage
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onPrimary,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                if (isMyMessage && !isEnded && roomId != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final ended =
                          await CallService.instance.endMeetingRoom(roomId);
                      if (!ended) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content:
                                Text('Não foi possível encerrar a reunião.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.stop_circle_rounded, size: 18),
                    label: const Text('Encerrar Reunião'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBody(BuildContext context) {
    final content = message.content ?? '';
    final theme = Theme.of(context);

    // Converte @menções para padrão de link Markdown: [@Nome](mention:Nome)
    // Isso permite que o flutter_markdown o renderize como link (colorido/clicável)
    final mentionRegex = RegExp(r'@([\w\sÀ-ú]+?)(?=\s|$)');
    final processedContent = content.replaceAllMapped(mentionRegex, (match) {
      final name = match.group(1);
      return '[@$name](mention:$name)';
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: MarkdownBody(
        data: processedContent,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(fontSize: 16, height: 1.35),
          a: TextStyle(
            color: isMe ? Colors.white : theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.none,
          ),
          code: TextStyle(
            backgroundColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            color: theme.colorScheme.onSurface,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
          codeblockDecoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          blockquoteDecoration: BoxDecoration(
            border: Border(
                left: BorderSide(color: theme.colorScheme.primary, width: 4)),
            color: theme.colorScheme.primary.withValues(alpha: 0.05),
          ),
          blockquotePadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        onTapLink: (text, href, title) async {
          if (href != null && href.startsWith('mention:')) {
            // Futuro: abrir perfil do usuário ao clicar na menção
          } else if (href != null) {
            final uri = Uri.tryParse(href);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
      ),
    );
  }

  Widget _buildImageBody(BuildContext context) {
    final progress = (message.metadata['upload_progress'] as num?)?.toDouble();
    final heroTag = 'hero_image_${message.id}';

    return GestureDetector(
      onTap: () {
        final hasLocal =
            message.localFilePath != null && message.localFilePath!.isNotEmpty;
        final hasRemote =
            message.mediaUrl != null && message.mediaUrl!.isNotEmpty;
        if (!hasLocal && !hasRemote) return;

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
                  child: hasLocal
                      ? (kIsWeb
                          ? Image.network(message.localFilePath!,
                              fit: BoxFit.contain)
                          : Image.file(File(message.localFilePath!),
                              fit: BoxFit.contain))
                      : SignedNetworkImage(
                          storedUrl: message.mediaUrl!,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white)),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
          child: SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Imagem otimista (local) ou confirmada (rede) ──
                if ((message.isOptimistic ||
                        message.status == MessageStatus.error) &&
                    message.localFilePath != null)
                  (kIsWeb
                      ? Image.network(message.localFilePath!, fit: BoxFit.cover)
                      : Image.file(File(message.localFilePath!), fit: BoxFit.cover))
                else if (message.mediaUrl != null)
                  _buildNetworkImage(message.mediaUrl!),

                // ── Falha no envio: oferece tentar de novo ──
                if (message.status == MessageStatus.error &&
                    onRetryUpload != null)
                  Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.white, size: 28),
                          const SizedBox(height: 4),
                          TextButton.icon(
                            onPressed: onRetryUpload,
                            icon: const Icon(Icons.refresh,
                                color: Colors.white, size: 18),
                            label: const Text('Tentar de novo',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Overlay de progresso de upload (Refinado) ──
                if (message.isOptimistic)
                  Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 50,
                                height: 50,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.white24,
                                  color: Colors.white,
                                  strokeWidth: 3.5,
                                ),
                              ),
                              // O X substitui a porcentagem: cancelar é mais
                              // útil que saber o número exato.
                              if (onCancelUpload != null)
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.white, size: 22),
                                  tooltip: 'Cancelar envio',
                                  onPressed: onCancelUpload,
                                )
                              else if (progress != null)
                                Text(
                                  '${(progress * 100).toInt()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkImage(String url) {
    if (kIsWeb) {
      return SignedNetworkImage(
        storedUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: Colors.black12,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
      );
    }

    // Já resolvido nesta sessão: pinta direto. Sem este atalho o
    // `FutureBuilder` voltaria ao spinner por um frame a cada rebuild da
    // lista — que acontece a cada digitação, reação ou recibo de leitura.
    final cached = MediaCacheManager.cachedFileFor(url);
    if (cached != null) {
      return Image.file(cached, fit: BoxFit.cover);
    }

    return FutureBuilder<File?>(
      future: MediaCacheManager.getOrDownloadMedia(
        mediaUrl: url,
        messageId: message.id,
        chatId: message.chatId,
        mediaType: 'image',
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: Colors.black12,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return Image.file(snapshot.data!, fit: BoxFit.cover);
        }
        // Fallback
        return SignedNetworkImage(
          storedUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
        );
      },
    );
  }

  Widget _buildFileBody(BuildContext context) {
    final fileName = message.metadata['original_filename'] as String? ??
        message.content ??
        'Documento';
    final fileSize = message.metadata['file_size_display'] as String? ?? '';

    // Lógica Semântica de Workflow (Cores premium para OS e Faturamento)
    final nameUpper = fileName.toUpperCase();
    final isOS = nameUpper.contains('OS') || nameUpper.contains('ORDEM');
    final isInvoice = nameUpper.contains('FATURA') ||
        nameUpper.contains('BOLETO') ||
        nameUpper.contains('RECIBO');

    final baseColor = DefaultTextStyle.of(context).style.color ?? Colors.white;
    Color iconBgColor = baseColor.withValues(alpha: 0.15);
    Color iconColor = baseColor;

    if (isOS) {
      iconBgColor = const Color(0xFFE65100).withValues(alpha: 0.2); // Laranja
      iconColor = const Color(0xFFFF9800);
    } else if (isInvoice) {
      iconBgColor = const Color(0xFF2E7D32).withValues(alpha: 0.2); // Verde
      iconColor = const Color(0xFF4CAF50);
    }

    return GestureDetector(
      // Documento vive no bucket: assina antes de abrir/baixar no navegador ou aplicativo.
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
                debugPrint('Erro ao abrir documento em conversa direta: $e');
              }
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getFileIcon(fileName),
                color: iconColor,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isOS || isInvoice)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        borderRadius: BorderRadius.circular(4),
                        border:
                            Border.all(color: iconColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        isOS ? 'ORDEM DE SERVIÇO' : 'FINANCEIRO',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: iconColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Text(
                    fileName,
                    style: TextStyle(
                      color: isMe
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (fileSize.isNotEmpty)
                    Text(
                      fileSize,
                      style: TextStyle(
                        fontSize: 12,
                        color: isMe
                            ? Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer
                                .withValues(alpha: 0.6)
                            : Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer
                                .withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            if (message.mediaUrl != null)
              Icon(
                Icons.download_rounded,
                size: 20,
                color: isMe
                    ? Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer
                        .withValues(alpha: 0.6)
                    : Theme.of(context)
                        .colorScheme
                        .onSecondaryContainer
                        .withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.article_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'zip':
      case 'rar':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}

class _AudioPlayerWidget extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  const _AudioPlayerWidget({required this.message, required this.isMe});

  @override
  State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  final _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) setState(() => _duration = newDuration);
    });
    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) setState(() => _position = newPosition);
    });
    _setSource();
  }

  void _setSource() async {
    if (widget.message.localFilePath != null) {
      await _audioPlayer.setSourceDeviceFile(widget.message.localFilePath!);
    } else if (widget.message.mediaUrl != null) {
      // Áudio no bucket privado exige URL assinada.
      final url = await MediaUrlResolver.resolve(widget.message.mediaUrl!);
      await _audioPlayer.setSourceUrl(url);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = DefaultTextStyle.of(context).style.color ?? Colors.white;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
                _isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: baseColor,
                size: 36),
            onPressed: () async {
              if (_isPlaying) {
                await _audioPlayer.pause();
              } else {
                await _audioPlayer.resume();
              }
            },
          ),
          Slider(
            value: _position.inSeconds.toDouble(),
            min: 0.0,
            max: _duration.inSeconds.toDouble() > 0
                ? _duration.inSeconds.toDouble()
                : 1.0,
            onChanged: (val) {
              _audioPlayer.seek(Duration(seconds: val.toInt()));
            },
            activeColor: baseColor,
            inactiveColor: baseColor.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerWidget extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  const _VideoPlayerWidget({required this.message, required this.isMe});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (widget.message.localFilePath != null && !kIsWeb) {
      _controller =
          VideoPlayerController.file(File(widget.message.localFilePath!));
    } else if (widget.message.mediaUrl != null) {
      // O player recebe a URL direto (sem passar pelo MediaCacheManager na
      // web), então precisa da versão assinada.
      final signedUrl =
          await MediaUrlResolver.resolve(widget.message.mediaUrl!);
      if (kIsWeb) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(signedUrl));
      } else {
        final cachedFile = await MediaCacheManager.getOrDownloadMedia(
          mediaUrl: widget.message.mediaUrl!,
          messageId: widget.message.id,
          chatId: widget.message.chatId,
          mediaType: 'video',
        );
        if (cachedFile != null) {
          _controller = VideoPlayerController.file(cachedFile);
        } else {
          _controller = VideoPlayerController.networkUrl(Uri.parse(signedUrl));
        }
      }
    }

    if (_controller != null) {
      await _controller!.initialize();
      if (mounted) setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _controller == null) {
      return const SizedBox(
        width: 150,
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _controller!.value.isPlaying
              ? _controller!.pause()
              : _controller!.play();
        });
      },
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
        child: SizedBox(
          width: 200,
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller!),
                if (!_controller!.value.isPlaying)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 40),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
