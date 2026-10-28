import 'package:flutter/material.dart';
import 'package:alinha_ja/features/channels/models/channel_message_model.dart';

/// Cartão de citação exibido no topo de uma mensagem que responde a outra.
///
/// [quoted] nulo significa que a mensagem original não pôde ser carregada
/// (apagada, por exemplo) — nesse caso mostramos um estado neutro em vez de
/// esconder a citação, para o leitor entender que aquilo é uma resposta.
class ChannelReplyQuote extends StatelessWidget {
  final ChannelMessageModel? quoted;
  final String? senderName;
  final Color accentColor;
  final Color textColor;
  final VoidCallback? onTap;

  const ChannelReplyQuote({
    super.key,
    required this.quoted,
    required this.accentColor,
    required this.textColor,
    this.senderName,
    this.onTap,
  });

  String get _preview {
    final msg = quoted;
    if (msg == null) return 'Mensagem indisponível';
    if (msg.isDeleted) return 'Mensagem apagada';

    final content = msg.content?.trim();
    if (content != null && content.isNotEmpty) return content;

    switch (msg.contentType) {
      case 'image':
        return '📷 Imagem';
      case 'video':
        return '🎥 Vídeo';
      case 'audio':
        return '🎤 Áudio';
      case 'file':
        return '📎 Arquivo';
      default:
        return 'Mensagem';
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: textColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: accentColor, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              senderName ?? 'Mensagem',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                color: textColor.withValues(alpha: 0.75),
                fontStyle: quoted == null ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
