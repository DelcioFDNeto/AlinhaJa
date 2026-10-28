import 'package:alinha_ja/features/profile/models/user_model.dart';

class TicketMessageModel {
  final String id;
  final String ticketId;
  final String senderId;
  final String content;
  final List<String> attachments;
  final bool isInternal;
  final DateTime createdAt;

  // Relations
  final UserModel? sender;

  TicketMessageModel({
    required this.id,
    required this.ticketId,
    required this.senderId,
    required this.content,
    this.attachments = const [],
    this.isInternal = false,
    required this.createdAt,
    this.sender,
  });

  factory TicketMessageModel.fromJson(Map<String, dynamic> json) {
    UserModel? parsedSender;
    if (json['sender'] != null && json['sender'] is Map<String, dynamic>) {
      parsedSender = UserModel.fromJson(json['sender']);
    }

    return TicketMessageModel(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      attachments:
          (json['attachments'] as List?)?.map((e) => e.toString()).toList() ??
              [],
      isInternal: json['is_internal'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at']),
      sender: parsedSender,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ticket_id': ticketId,
      'sender_id': senderId,
      'content': content,
      'attachments': attachments,
      'is_internal': isInternal,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
