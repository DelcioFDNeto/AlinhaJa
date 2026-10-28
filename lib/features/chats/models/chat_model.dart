import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';

enum ChatType { direct, group, channel }

class ChatModel {
  final String id;
  final ChatType type;
  final String? name;
  final String? description;
  final String? avatarUrl;
  final String? createdBy;
  final Map<String, dynamic> metadata; // Para integração OS AlinhaJá
  final DateTime createdAt;
  final bool isPinned;

  // ── Campos computados (populados pelo app) ──
  final MessageModel? lastMessage;
  final int unreadCount;
  final UserModel? otherUser; // Em DMs: o outro participante

  /// Maior `last_read_at` entre os DEMAIS membros do chat. Usado para o
  /// check azul de leitura na lista, com a mesma regra da bolha da conversa.
  final DateTime? otherReadAt;

  const ChatModel({
    required this.id,
    required this.type,
    this.name,
    this.description,
    this.avatarUrl,
    this.createdBy,
    this.metadata = const {},
    required this.createdAt,
    this.isPinned = false,
    this.lastMessage,
    this.unreadCount = 0,
    this.otherUser,
    this.otherReadAt,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    // Guard contra dados nulos vindos de RPCs com LEFT JOINs
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('Chat com id nulo ignorado');
    }

    return ChatModel(
      id: id,
      type: _parseChatType(json['type'] as String? ?? 'direct'),
      name: json['name'] as String?,
      description: json['description'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdBy: json['created_by'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isPinned: json['is_pinned'] as bool? ?? false,
    );
  }

  static ChatType _parseChatType(String value) {
    switch (value) {
      case 'group':
        return ChatType.group;
      case 'channel':
        return ChatType.channel;
      default:
        return ChatType.direct;
    }
  }

  /// Nome para exibição — usa o nome do outro usuário em DMs.
  String get displayName {
    if (type == ChatType.direct && otherUser != null) {
      return otherUser!.fullName;
    }
    return name ?? 'Chat';
  }

  ChatModel copyWith({
    MessageModel? lastMessage,
    int? unreadCount,
    UserModel? otherUser,
    DateTime? otherReadAt,
  }) =>
      ChatModel(
        id: id,
        type: type,
        name: name,
        description: description,
        avatarUrl: avatarUrl,
        createdBy: createdBy,
        metadata: metadata,
        createdAt: createdAt,
        isPinned: isPinned,
        lastMessage: lastMessage ?? this.lastMessage,
        unreadCount: unreadCount ?? this.unreadCount,
        otherUser: otherUser ?? this.otherUser,
        otherReadAt: otherReadAt ?? this.otherReadAt,
      );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type == ChatType.direct
          ? 'direct'
          : (type == ChatType.group ? 'group' : 'channel'),
      'name': name,
      'description': description,
      'avatar_url': avatarUrl,
      'created_by': createdBy,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'is_pinned': isPinned,
    };
  }
}
