import 'package:image_picker/image_picker.dart';

import 'package:alinha_ja/core/ui/composer/composer_action.dart';
import 'package:alinha_ja/core/ui/composer/composer_delegate.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/chat/providers/chat_provider.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/features/whiteboard/providers/whiteboard_provider.dart' as wb;

/// Liga o composer ao chat 1:1, aos grupos e às threads de chat.
class ChatComposerDelegate extends ComposerDelegate {
  final ChatNotifier notifier;
  final String chatName;
  final List<UserModel> members;
  final MessageModel? replyingTo;

  /// Chamado depois que a resposta foi consumida por um envio.
  final void Function()? onReplyConsumed;

  final void Function()? onCancelReply;
  final void Function(String text)? onTypingChanged;
  final bool locked;

  /// Libera a ação de anúncio oficial — `comunicacao_anuncios/create` no RBAC.
  /// Só faz sentido em grupo: anúncio para uma pessoa só é mensagem comum.
  final bool canAnnounce;

  const ChatComposerDelegate({
    required this.notifier,
    required this.chatName,
    this.members = const [],
    this.replyingTo,
    this.onReplyConsumed,
    this.onCancelReply,
    this.onTypingChanged,
    this.locked = false,
    this.canAnnounce = false,
  });

  @override
  String get destinationName => chatName;

  @override
  bool get canSend => !locked;

  @override
  bool get allowViewOnce => true;

  @override
  List<UserModel> get mentionableMembers => members;

  /// O chat aceita tudo: mídia e conteúdo estruturado. Compartilhar contato depende
  /// de haver membros carregados — em thread a lista não vem.
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
    if (target == null || onCancelReply == null) return null;

    return ComposerReply(
      title: 'Respondendo a ${target.sender?.fullName ?? "mensagem"}',
      preview: target.content ?? _placeholderFor(target.contentType),
      onCancel: onCancelReply!,
    );
  }

  static String _placeholderFor(ContentType type) => switch (type) {
        ContentType.image => 'Imagem',
        ContentType.video => 'Vídeo',
        ContentType.audio => 'Áudio',
        ContentType.file => 'Documento',
        ContentType.meeting => 'Reunião',
        ContentType.text => 'Mensagem',
      };

  @override
  void onTyping(String text) => onTypingChanged?.call(text);

  String? _consumeReply() {
    final id = replyingTo?.id;
    if (id != null) onReplyConsumed?.call();
    return id;
  }

  @override
  Future<void> sendText(String text) async {
    final replyTo = _consumeReply();
    await notifier.sendText(
      text,
      replyTo: replyTo,
    );
  }

  @override
  Future<void> sendStructured(
    String content,
    Map<String, dynamic> metadata,
  ) async {
    final replyTo = _consumeReply();
    await notifier.sendText(content, replyTo: replyTo, metadata: metadata);
  }

  @override
  Future<void> sendMedia(
    List<XFile> files, {
    String? caption,
    bool isViewOnce = false,
  }) async {
    final replyTo = _consumeReply();

    // Legenda e resposta acompanham só o primeiro arquivo do lote, para não
    // repetir o mesmo texto em cada item.
    for (var i = 0; i < files.length; i++) {
      await notifier.sendMediaFile(
        files[i],
        isViewOnce: isViewOnce,
        replyTo: i == 0 ? replyTo : null,
        caption: i == 0 ? caption : null,
      );
    }
  }

  @override
  Future<void> sendDocuments(List<XFile> files, {String? caption}) async {
    final replyTo = _consumeReply();
    for (var i = 0; i < files.length; i++) {
      await notifier.pickAndSendDocument(
        externalFile: files[i],
        replyTo: i == 0 ? replyTo : null,
      );
    }

    // A legenda do lote vira uma mensagem de texto logo em seguida.
    if (caption != null && caption.trim().isNotEmpty) {
      await notifier.sendText(caption);
    }
  }

  @override
  Future<String?> uploadAttachment(XFile file) =>
      notifier.uploadAttachment(file);

  @override
  Future<String?> createWhiteboard(String title) =>
      wb.createWhiteboard(title: title, chatId: notifier.chatId);

  @override
  Future<void> sendAudio(String path) async {
    final replyTo = _consumeReply();
    await notifier.sendAudio(path, replyTo: replyTo);
  }
}
