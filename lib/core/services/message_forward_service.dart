import 'package:alinha_ja/core/supabase_client.dart';

/// Destino de um encaminhamento: uma conversa (DM/grupo) ou um canal.
class ForwardTarget {
  final String id;
  final String name;
  final bool isChannel;

  const ForwardTarget({
    required this.id,
    required this.name,
    required this.isChannel,
  });
}

/// Encaminhamento de mensagens entre conversas e canais.
///
/// As duas pontas gravam em tabelas diferentes (`messages` x
/// `channel_messages`), então o serviço concentra a montagem do payload para
/// que DM, grupo e canal encaminhem exatamente do mesmo jeito.
class MessageForwardService {
  /// Chaves de metadata que fazem sentido viajar junto com o conteúdo.
  ///
  /// Todo o resto pertence à mensagem original e não pode ser copiado:
  /// `mentions` (IDs de membros de outra conversa), `reactions`, 
  /// `upload_progress`, confirmações de leitura.
  static const _portableKeys = {
    'media_mime_type',
    'media_size_bytes',
    'file_name',
    'duration',
    'width',
    'height',
  };

  /// Monta a metadata da cópia encaminhada.
  ///
  /// `forwarded_from` preserva o autor original: encaminhar algo que já foi
  /// encaminhado continua creditando quem escreveu, não o intermediário.
  static Map<String, dynamic> buildMetadata(
    Map<String, dynamic> original,
    String originalSenderName,
  ) {
    final clean = <String, dynamic>{
      for (final entry in original.entries)
        if (_portableKeys.contains(entry.key)) entry.key: entry.value,
    };
    final firstAuthor = original['forwarded_from']?.toString();
    clean['forwarded_from'] =
        (firstAuthor != null && firstAuthor.isNotEmpty)
            ? firstAuthor
            : originalSenderName;
    return clean;
  }

  /// Encaminha uma mensagem para [target].
  ///
  /// Lança em caso de falha (inclusive RLS, quando o usuário não tem permissão
  /// de publicar no canal escolhido) para a UI conseguir avisar.
  static Future<void> forward({
    required ForwardTarget target,
    required String originalSenderName,
    String? content,
    String contentType = 'text',
    String? mediaUrl,
    Map<String, dynamic> metadata = const {},
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Sessão expirada. Entre novamente para encaminhar.');
    }

    final cleanMetadata = buildMetadata(metadata, originalSenderName);

    final payload = <String, dynamic>{
      'sender_id': userId,
      'content': content,
      'content_type': contentType,
      'metadata': cleanMetadata,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (target.isChannel) 'channel_id': target.id else 'chat_id': target.id,
    };

    // `messages` guarda os dados de mídia em colunas próprias; em
    // `channel_messages` eles vivem só dentro da metadata.
    if (!target.isChannel) {
      final mimeType = cleanMetadata['media_mime_type'];
      final sizeBytes = cleanMetadata['media_size_bytes'];
      if (mimeType != null) payload['media_mime_type'] = mimeType;
      if (sizeBytes != null) payload['media_size_bytes'] = sizeBytes;
    }

    await supabase
        .from(target.isChannel ? 'channel_messages' : 'messages')
        .insert(payload);
  }
}
