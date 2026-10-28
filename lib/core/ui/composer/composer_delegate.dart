import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:alinha_ja/core/ui/composer/composer_action.dart';
import 'package:alinha_ja/core/ui/composer/composer_media.dart';
import 'package:alinha_ja/core/widgets/media_preview_screen.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';

/// Prévia da mensagem que está sendo respondida.
///
/// O composer não conhece `MessageModel` nem `ChannelMessageModel`: cada lado
/// traduz sua mensagem para este par título/prévia.
class ComposerReply {
  final String title;
  final String preview;
  final void Function() onCancel;

  const ComposerReply({
    required this.title,
    required this.preview,
    required this.onCancel,
  });
}

/// Botão de liga/desliga próprio de uma conversa, desenhado na barra de input.
///
/// Existe para casos como o "anúncio oficial" dos canais, que muda o modo de
/// envio sem ser um anexo.
class ComposerToggle {
  final IconData icon;
  final IconData activeIcon;
  final String tooltip;
  final bool active;
  final Color activeColor;
  final void Function() onPressed;

  const ComposerToggle({
    required this.icon,
    required this.activeIcon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
    this.activeColor = const Color(0xFFFF9500),
  });
}

/// Menção coletiva sugerida no overlay de `@` (ex.: `@canal`, `@aqui`).
class ComposerBroadcastMention {
  /// Token inserido no texto, sem o `@`.
  final String token;
  final String label;
  final String description;
  final IconData icon;

  const ComposerBroadcastMention({
    required this.token,
    required this.label,
    required this.description,
    this.icon = Icons.campaign_outlined,
  });
}

/// Ponte entre o composer (UI) e o backend de cada conversa.
///
/// Chat 1:1/grupo, canais e threads gravam em tabelas e providers diferentes;
/// tudo que o composer precisa saber está nesta interface. Implementações vivem
/// junto da feature dona do provider.
abstract class ComposerDelegate {
  const ComposerDelegate();

  /// Nome do destino, usado no cabeçalho do preview de mídia
  /// ("Enviar para Financeiro").
  String get destinationName;

  /// O que o painel de anexos oferece nesta conversa.
  Set<ComposerActionId> get actions => kMediaComposerActions;

  /// Membros sugeridos ao digitar `@` e listados no seletor de contato.
  List<UserModel> get mentionableMembers => const [];

  /// Menções coletivas (`@canal`, `@aqui`) oferecidas junto das pessoas.
  ///
  /// Vazio em DMs, onde citar "todo mundo" não significa nada. Em canal, é o
  /// que permite alcançar quem está em "somente menções".
  List<ComposerBroadcastMention> get broadcastMentions => const [];

  /// Resposta em curso; `null` quando não há.
  ComposerReply? get reply => null;

  /// `false` trava o composer e mostra o aviso de somente-leitura.
  bool get canSend => true;

  /// Texto do aviso quando [canSend] é `false`.
  String get lockedMessage => 'Apenas administradores podem enviar mensagens';

  /// Gravação de áudio pelo botão de microfone.
  bool get supportsAudio => true;

  /// Libera o botão de "visualização única" no preview de mídia.
  bool get allowViewOnce => false;

  /// Placeholder do campo de texto.
  String get hintText => 'Digite sua mensagem...';

  /// Botões de modo desta conversa (ex.: anúncio oficial).
  List<ComposerToggle> get toggles => const [];

  /// Tinge o campo de texto quando algum modo especial está ligado.
  Color? get accentColor => null;

  /// Notificação de digitação (indicador de "digitando...").
  void onTyping(String text) {}

  /// Texto simples.
  Future<void> sendText(String text);

  /// Fotos e vídeos já confirmados no preview. A legenda vale para o lote.
  Future<void> sendMedia(
    List<XFile> files, {
    String? caption,
    bool isViewOnce = false,
  });

  /// Documentos já confirmados no preview. Documento não tem corpo para
  /// carregar legenda; cada conversa decide o que fazer com [caption].
  Future<void> sendDocuments(List<XFile> files, {String? caption});

  /// Áudio gravado no microfone do composer.
  Future<void> sendAudio(String path) async {}

  /// Mensagem estruturada (enquete, evento, localização, contato, anúncio): o
  /// texto vai no conteúdo e o formato do card vem de [metadata] — ver
  /// [MessageExtras].
  Future<void> sendStructured(String content, Map<String, dynamic> metadata);

  /// Cria um quadro branco vinculado a esta conversa e devolve o id.
  ///
  /// Retorna `null` quando a conversa não suporta quadro (thread, por exemplo,
  /// onde o quadro pertenceria à conversa-mãe e não ao tópico).
  Future<String?> createWhiteboard(String title) async => null;

  /// Sobe um arquivo avulso e devolve a URL pública.
  ///
  /// Usado pelo anexo do anúncio, que precisa da URL antes de gravar a
  /// mensagem — diferente de [sendDocuments], que cria uma mensagem por
  /// arquivo. Retorna `null` quando a conversa não suporta upload.
  Future<String?> uploadAttachment(XFile file) async => null;

  /// Despacha o resultado do preview separando foto/vídeo de documento.
  ///
  /// Um lote misto (arrastar e soltar, por exemplo) vira dois envios, cada um
  /// pelo caminho certo.
  Future<void> sendFromPreview(MediaPreviewResult result) async {
    final visual = result.files.where(ComposerMedia.isVisualMedia).toList();
    final documents =
        result.files.where((f) => !ComposerMedia.isVisualMedia(f)).toList();

    if (visual.isNotEmpty) {
      await sendMedia(
        visual,
        caption: result.caption,
        isViewOnce: result.isViewOnce,
      );
    }
    if (documents.isNotEmpty) {
      await sendDocuments(
        documents,
        caption: visual.isEmpty ? result.caption : null,
      );
    }
  }
}
