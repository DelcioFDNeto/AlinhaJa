import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:alinha_ja/core/ui/composer/composer_action.dart';
import 'package:alinha_ja/core/ui/composer/composer_delegate.dart';
import 'package:alinha_ja/features/channels/models/channel_message_model.dart';
import 'package:alinha_ja/features/channels/providers/active_channel_provider.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/features/whiteboard/providers/whiteboard_provider.dart' as wb;

/// Liga o composer aos canais e às threads de canal.
///
/// Diferente do chat, a resposta em curso mora no provider — por isso não há
/// callback de "resposta consumida": quem envia já limpa.
class ChannelComposerDelegate extends ComposerDelegate {
  final ActiveChannelNotifier notifier;
  final String channelName;
  final List<UserModel> members;
  final ChannelMessageModel? replyingTo;
  final bool locked;

  /// Libera a ação de anúncio oficial no painel.
  ///
  /// Vem de `comunicacao_anuncios/create` no RBAC — publicar comunicado deixou
  /// de ser sinônimo de administrar o canal: o RH pode anunciar sem gerir a
  /// lista de membros.
  final bool canAnnounce;

  const ChannelComposerDelegate({
    required this.notifier,
    required this.channelName,
    this.members = const [],
    this.replyingTo,
    this.locked = false,
    this.canAnnounce = false,
  });

  @override
  String get destinationName => channelName;

  @override
  bool get canSend => !locked;

  @override
  List<UserModel> get mentionableMembers => members;

  /// `@canal` e `@aqui` alcançam quem colocou o canal em "somente menções".
  /// Fora de um tópico, para uma resposta em thread não virar broadcast.
  @override
  List<ComposerBroadcastMention> get broadcastMentions =>
      notifier.parentMessageId != null
          ? const []
          : const [
              ComposerBroadcastMention(
                token: 'canal',
                label: 'canal',
                description: 'Notifica todos os membros do canal',
                icon: Icons.campaign_outlined,
              ),
              ComposerBroadcastMention(
                token: 'aqui',
                label: 'aqui',
                description: 'Chama a atenção de quem acompanha o canal',
                icon: Icons.bolt_outlined,
              ),
            ];

  /// Canal não grava áudio: o provider não tem
  /// `sendAudio`.
  @override
  bool get supportsAudio => false;

  @override
  Set<ComposerActionId> get actions => {
        ...kMediaComposerActions,
        ComposerActionId.poll,
        ComposerActionId.event,
        ComposerActionId.location,
        if (members.isNotEmpty) ComposerActionId.contact,
        ComposerActionId.whiteboard,
        if (canAnnounce) ComposerActionId.announcement,
      };

  @override
  ComposerReply? get reply {
    final target = replyingTo;
    if (target == null) return null;

    return ComposerReply(
      title: 'Respondendo à mensagem',
      preview: target.content?.isNotEmpty == true
          ? target.content!
          : (target.contentType == 'image' ? 'Imagem' : 'Anexo'),
      onCancel: notifier.clearReply,
    );
  }

  @override
  Future<void> sendText(String text) => notifier.sendMessage(text);

  @override
  Future<void> sendStructured(
    String content,
    Map<String, dynamic> metadata,
  ) =>
      notifier.sendMessage(content, metadata: metadata);

  @override
  Future<String?> uploadAttachment(XFile file) =>
      notifier.uploadAttachment(file);

  @override
  Future<String?> createWhiteboard(String title) =>
      wb.createWhiteboard(title: title, channelId: notifier.channelId);

  @override
  Future<void> sendMedia(
    List<XFile> files, {
    String? caption,
    bool isViewOnce = false,
  }) async {
    for (var i = 0; i < files.length; i++) {
      await notifier.sendImage(files[i], caption: i == 0 ? caption : null);
    }
  }

  @override
  Future<void> sendDocuments(List<XFile> files, {String? caption}) async {
    for (final file in files) {
      await notifier.sendDocument(file);
    }
    if (caption != null && caption.trim().isNotEmpty) {
      await notifier.sendMessage(caption);
    }
  }
}
