import 'package:alinha_ja/features/channels/models/message_metadata.dart';

class ChannelMessageModel {
  final String id;
  final String channelId;
  final String senderId;
  final String? content;
  final String contentType;
  final String? mediaUrl;
  final String? localFilePath;
  final MessageMetadata metadata;
  final bool isBot;
  final bool isSystem;
  final List<String> readBy;
  final String? parentMessageId;
  final String? replyTo;
  final int replyCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// Carimbo da coluna `channel_messages.edited_at`, mantido pelo trigger
  /// `fn_channel_messages_guard_immutable` sempre que o conteúdo muda.
  final DateTime? editedAt;

  // UI Helpers
  final bool isOptimistic;
  final bool isError;

  ChannelMessageModel({
    required this.id,
    required this.channelId,
    required this.senderId,
    this.content,
    this.contentType = 'text',
    this.mediaUrl,
    this.localFilePath,
    this.metadata = const MessageMetadata(),
    this.isBot = false,
    this.isSystem = false,
    this.readBy = const [],
    this.parentMessageId,
    this.replyTo,
    this.replyCount = 0,
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.editedAt,
    this.isOptimistic = false,
    this.isError = false,
  });

  factory ChannelMessageModel.fromJson(Map<String, dynamic> json) {
    return ChannelMessageModel(
      id: json['id']?.toString() ?? '',
      channelId: json['channel_id']?.toString() ?? '',
      senderId: (json['sender_id']?.toString().isEmpty ?? true)
          ? 'system'
          : json['sender_id'].toString(),
      content: json['content']?.toString(),
      contentType: json['content_type']?.toString() ?? 'text',
      mediaUrl: json['media_url']?.toString(),
      localFilePath: json['local_file_path']?.toString(),
      metadata: json['metadata'] is Map
          ? MessageMetadata.fromMap(Map<String, dynamic>.from(json['metadata']))
          : const MessageMetadata(),
      isBot: json['is_bot'] == true || json['is_bot'] == 'true',
      isSystem: json['is_system'] == true || json['is_system'] == 'true',
      readBy: json['read_by'] is List
          ? (json['read_by'] as List).map((id) => id.toString()).toList()
          : const [],
      parentMessageId: json['parent_message_id']?.toString() ??
          json['thread_id']?.toString(),
      replyTo: json['reply_to']?.toString(),
      replyCount: int.tryParse(
              (json['reply_count'] ?? json['thread_reply_count'] ?? '0')
                  .toString()) ??
          0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      deletedAt: json['deleted_at'] != null
          ? DateTime.tryParse(json['deleted_at'].toString())
          : null,
      editedAt: json['edited_at'] != null
          ? DateTime.tryParse(json['edited_at'].toString())
          : null,
    );
  }

  bool get isDeleted => deletedAt != null;

  /// A coluna `edited_at` é a fonte de verdade; `metadata.isEdited` cobre
  /// mensagens antigas, gravadas antes de a coluna existir.
  bool get isEdited => editedAt != null || metadata.isEdited;
  bool get isThreadReply => parentMessageId != null;
  bool get isAnnouncement => metadata.isAnnouncement;

  ChannelMessageModel copyWith({
    String? id,
    String? channelId,
    String? senderId,
    String? content,
    String? contentType,
    String? mediaUrl,
    String? localFilePath,
    MessageMetadata? metadata,
    bool? isBot,
    bool? isSystem,
    List<String>? readBy,
    String? parentMessageId,
    String? replyTo,
    int? replyCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    DateTime? editedAt,
    bool? isOptimistic,
    bool? isError,
  }) {
    return ChannelMessageModel(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      contentType: contentType ?? this.contentType,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      localFilePath: localFilePath ?? this.localFilePath,
      metadata: metadata ?? this.metadata,
      isBot: isBot ?? this.isBot,
      isSystem: isSystem ?? this.isSystem,
      readBy: readBy ?? this.readBy,
      parentMessageId: parentMessageId ?? this.parentMessageId,
      replyTo: replyTo ?? this.replyTo,
      replyCount: replyCount ?? this.replyCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      editedAt: editedAt ?? this.editedAt,
      isOptimistic: isOptimistic ?? this.isOptimistic,
      isError: isError ?? this.isError,
    );
  }
}
