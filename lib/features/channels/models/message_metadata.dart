import 'package:alinha_ja/core/models/message_extras.dart';

/// Schema tipado para metadata de mensagens do canal.
/// Garante acesso type-safe e validação sobre o campo JSONB genérico.
class MessageMetadata {
  final String?
      type; // 'announcement', 'poll', 'date_event', 'meeting', null (text normal)
  final List<String> options; // Poll options
  final String? eventDate; // ISO 8601 date string para date_event
  final String? roomId; // Agora room ID for meetings
  final String? mediaMimeType; // MIME type para media (image, file)
  final int? mediaSizeBytes; // Tamanho do arquivo em bytes
  final Map<String, dynamic>? reactions; // Emoji reactions { '👍': 3, '❤️': 1 }
  final String? editedAt; // ISO 8601 timestamp when message was edited
  final double?
      uploadProgress; // Indicador de progresso (0.0 a 1.0) para uploads de mídia otimistas

  /// JSONB original, preservado inteiro.
  ///
  /// Os campos tipados acima cobrem o que a bolha do canal precisa; tipos mais
  /// novos (localização, contato) leem daqui pelo `MessageExtrasReader`, e
  /// encaminhar uma mensagem não perde mais as chaves desconhecidas.
  final Map<String, dynamic> raw;

  const MessageMetadata({
    this.type,
    this.options = const [],
    this.eventDate,
    this.roomId,
    this.mediaMimeType,
    this.mediaSizeBytes,
    this.reactions,
    this.editedAt,
    this.uploadProgress,
    this.raw = const {},
  });

  /// Factory para metadados de mídia (imagem, arquivo)
  factory MessageMetadata.media({
    required String mimeType,
    required int sizeBytes,
  }) {
    return MessageMetadata(
      mediaMimeType: mimeType,
      mediaSizeBytes: sizeBytes,
    );
  }

  /// Constrói a partir do Map<String, dynamic> cru do banco.
  factory MessageMetadata.fromMap(Map<String, dynamic> map) {
    return MessageMetadata(
      type: map['type']?.toString(),
      options: (map['options'] is List)
          ? (map['options'] as List).map((e) => e.toString()).toList()
          : const [],
      eventDate: map['event_date']?.toString(),
      roomId: map['room_id']?.toString(),
      mediaMimeType: map['media_mime_type']?.toString(),
      mediaSizeBytes: map['media_size_bytes'] is int
          ? map['media_size_bytes'] as int
          : int.tryParse(map['media_size_bytes']?.toString() ?? ''),
      reactions: map['reactions'] is Map
          ? Map<String, dynamic>.from(map['reactions'] as Map)
          : null,
      editedAt: map['edited_at']?.toString(),
      uploadProgress: map['upload_progress'] is num
          ? (map['upload_progress'] as num).toDouble()
          : (map['upload_progress'] != null
              ? double.tryParse(map['upload_progress'].toString())
              : null),
      raw: Map<String, dynamic>.from(map),
    );
  }

  /// Converte de volta para o Map do Supabase (remove nulls).
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{...raw};
    if (type != null) map['type'] = type;
    if (options.isNotEmpty) map['options'] = options;
    if (eventDate != null) map['event_date'] = eventDate;
    if (roomId != null) map['room_id'] = roomId;
    if (mediaMimeType != null) map['media_mime_type'] = mediaMimeType;
    if (mediaSizeBytes != null) map['media_size_bytes'] = mediaSizeBytes;
    if (reactions != null && reactions!.isNotEmpty) {
      map['reactions'] = reactions;
    }
    if (editedAt != null) map['edited_at'] = editedAt;
    if (uploadProgress != null) map['upload_progress'] = uploadProgress;
    return map;
  }

  // ── Getters de conveniência ──
  bool get isAnnouncement => type == 'announcement';
  bool get isPoll => type == 'poll' || options.isNotEmpty;
  bool get isDateEvent => type == 'date_event' || eventDate != null;
  bool get isMeeting => type == 'meeting' || roomId != null;
  bool get isLocation => type == 'location' || raw.isLocation;
  bool get isContact => type == 'contact' || raw.isContact;
  bool get isWhiteboard => type == 'whiteboard' || raw.isWhiteboard;

  /// Conteúdo estruturado desenhado por `StructuredMessageCard`.
  bool get isStructuredCard =>
      isPoll || isDateEvent || isLocation || isContact || isWhiteboard;
  bool get isMedia => mediaMimeType != null;
  bool get isEmpty =>
      type == null &&
      options.isEmpty &&
      eventDate == null &&
      roomId == null &&
      mediaMimeType == null &&
      reactions == null &&
      editedAt == null;
  bool get hasReactions => reactions != null && reactions!.isNotEmpty;
  bool get isEdited => editedAt != null;

  /// Parse seguro da data do evento.
  DateTime? get parsedEventDate =>
      eventDate != null ? DateTime.tryParse(eventDate!) : null;

  /// Formatação legível do tamanho do arquivo.
  String get formattedSize {
    if (mediaSizeBytes == null) return '';
    if (mediaSizeBytes! < 1024) return '$mediaSizeBytes B';
    if (mediaSizeBytes! < 1024 * 1024) {
      return '${(mediaSizeBytes! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(mediaSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
