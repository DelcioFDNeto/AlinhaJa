import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Item de uma seleção múltipla, no mínimo comum entre mensagens de conversa e
/// de canal — o suficiente para encaminhar, copiar e favoritar em lote.
class SelectedMessage {
  final String id;
  final String senderName;
  final String? content;
  final String contentType;
  final String? mediaUrl;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final bool isMine;

  const SelectedMessage({
    required this.id,
    required this.senderName,
    required this.contentType,
    required this.createdAt,
    required this.isMine,
    this.content,
    this.mediaUrl,
    this.metadata = const {},
  });

  /// Texto exibível de uma mensagem sem corpo textual.
  String get previewText {
    final body = content?.trim();
    if (body != null && body.isNotEmpty) return body;
    switch (contentType) {
      case 'image':
        return '📷 Imagem';
      case 'video':
        return '🎥 Vídeo';
      case 'audio':
        return '🎤 Áudio';
      case 'file':
        return '📎 Arquivo';
      default:
        return '';
    }
  }
}

/// Ações em lote sobre mensagens selecionadas.
class MessageBatchActions {
  /// Copia as mensagens para a área de transferência em ordem cronológica,
  /// no formato `[HH:mm] Autor: conteúdo` — o mesmo de exportar conversa.
  static Future<void> copyToClipboard(List<SelectedMessage> messages) async {
    if (messages.isEmpty) return;

    final ordered = [...messages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final formatter = DateFormat('HH:mm');

    final text = ordered
        .map((m) =>
            '[${formatter.format(m.createdAt.toLocal())}] ${m.senderName}: ${m.previewText}')
        .join('\n');

    await Clipboard.setData(ClipboardData(text: text));
  }
}
