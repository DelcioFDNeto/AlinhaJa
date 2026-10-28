import 'package:alinha_ja/features/profile/models/user_model.dart';

enum ContentType { text, image, audio, video, file, meeting }

enum MessageStatus { sending, sent, delivered, read, error }

/// Representa uma mensagem no chat, incluindo mensagens otimistas locais.
///
/// `localFilePath` — preenchido apenas em mensagens otimistas (antes do upload).
/// `mediaUrl` — URL pública no Supabase Storage (preenchida após o upload).
/// `metadata` — campo JSONB extensível para futuros recursos (transcrição de IA, etc).
class MessageModel {
  final String id;
  final String chatId;
  final String senderId;
  final String? content;
  final ContentType contentType;
  final String? mediaUrl;
  final String? mediaMimeType;
  final int? mediaSizeBytes;
  final String? replyTo;
  final String? threadId;
  final bool isBot;
  final int threadReplyCount;
  final Map<String, dynamic> metadata;
  final MessageStatus status;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final DateTime? editedAt;

  // ── Campos de Assinatura Digital (Recursos de RH/Avisos) ──
  final bool acknowledgedByMe; // Se o usuário logado já assinou

  // ── Campos LOCAIS (não persistidos no banco) ──
  /// Caminho local do arquivo antes do upload (para FileImage na UI otimista)
  final String? localFilePath;

  /// Referência ao remetente (join feito no app)
  final UserModel? sender;

  const MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.content,
    this.contentType = ContentType.text,
    this.mediaUrl,
    this.mediaMimeType,
    this.mediaSizeBytes,
    this.replyTo,
    this.threadId,
    this.isBot = false,
    this.threadReplyCount = 0,
    this.metadata = const {},
    this.status = MessageStatus.sent,
    required this.createdAt,
    this.deletedAt,
    this.editedAt,
    this.acknowledgedByMe = false,
    this.localFilePath,
    this.sender,
  });

  bool get isOptimistic => status == MessageStatus.sending;
  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;
  bool get isThreadParent => threadReplyCount > 0;

  /// Helper para verificar se a mensagem exige assinatura
  bool get requiresAcknowledgement =>
      metadata['requires_acknowledgement'] == true;

  /// Helper para verificar se a mensagem é temporária (Visualização Única)
  bool get isViewOnce => metadata['is_view_once'] == true;

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final chatId = json['chat_id'] as String?;
    final senderId = json['sender_id']?.toString().isEmpty ?? true
        ? 'system'
        : json['sender_id'].toString();

    // Guard: campos obrigatórios não podem ser nulos
    if (id == null || chatId == null) {
      throw FormatException(
          'Mensagem com campos obrigatórios nulos (id=$id, chatId=$chatId)');
    }

    return MessageModel(
      id: id,
      chatId: chatId,
      senderId: senderId,
      content: json['content'] as String?,
      contentType: _parseContentType(json['content_type'] as String? ?? 'text'),
      mediaUrl: json['media_url'] as String?,
      mediaMimeType: json['media_mime_type'] as String?,
      mediaSizeBytes: json['media_size_bytes'] as int?,
      replyTo: json['reply_to'] as String?,
      threadId: json['thread_id'] as String?,
      isBot: json['is_bot'] as bool? ?? false,
      threadReplyCount: json['thread_reply_count'] as int? ?? 0,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      status: _parseMessageStatus(json['status'] as String?),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      editedAt: json['edited_at'] != null
          ? DateTime.parse(json['edited_at'] as String)
          : null,
      acknowledgedByMe: json['acknowledged_by_me'] as bool? ?? false,
      sender: json['sender'] != null
          ? UserModel.fromJson(json['sender'] as Map<String, dynamic>)
          : null,
    );
  }

  static MessageStatus _parseMessageStatus(String? status) {
    switch (status) {
      case 'sending':
        return MessageStatus.sending;
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'error':
        return MessageStatus.error;
      default:
        return MessageStatus.sent; // default database value
    }
  }

  static ContentType _parseContentType(String value) {
    switch (value) {
      case 'image':
        return ContentType.image;
      case 'audio':
        return ContentType.audio;
      case 'video':
        return ContentType.video;
      case 'file':
        return ContentType.file;
      case 'meeting':
        return ContentType.meeting;
      default:
        return ContentType.text;
    }
  }

  String get contentTypeString {
    switch (contentType) {
      case ContentType.image:
        return 'image';
      case ContentType.audio:
        return 'audio';
      case ContentType.video:
        return 'video';
      case ContentType.file:
        return 'file';
      case ContentType.meeting:
        return 'meeting';
      case ContentType.text:
        return 'text';
    }
  }

  MessageModel copyWith({
    String? content,
    String? mediaUrl,
    MessageStatus? status,
    String? localFilePath,
    Map<String, dynamic>? metadata,
    bool? acknowledgedByMe,
    DateTime? deletedAt,
    DateTime? editedAt,
    bool setDeleted = false,
  }) =>
      MessageModel(
        id: id,
        chatId: chatId,
        senderId: senderId,
        content: content ?? this.content,
        contentType: contentType,
        mediaUrl: mediaUrl ?? this.mediaUrl,
        mediaMimeType: mediaMimeType,
        mediaSizeBytes: mediaSizeBytes,
        replyTo: replyTo,
        threadId: threadId,
        isBot: isBot,
        threadReplyCount: threadReplyCount,
        metadata: metadata ?? this.metadata,
        status: status ?? this.status,
        createdAt: createdAt,
        deletedAt: setDeleted
            ? (deletedAt ?? DateTime.now().toUtc())
            : (deletedAt ?? this.deletedAt),
        editedAt: editedAt ?? this.editedAt,
        acknowledgedByMe: acknowledgedByMe ?? this.acknowledgedByMe,
        localFilePath: localFilePath ?? this.localFilePath,
        sender: sender,
      );
}
