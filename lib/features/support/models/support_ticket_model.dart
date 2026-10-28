import 'package:alinha_ja/features/profile/models/user_model.dart';

class SupportTicketModel {
  final String id;
  final String creatorId;
  final String? assignedTo;
  final String title;
  final String description;
  final String category;
  final String priority;
  final String status;
  final String? deviceInfo;
  final List<String> attachments;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Relations
  final UserModel? creator;
  final UserModel? assignee;

  SupportTicketModel({
    required this.id,
    required this.creatorId,
    this.assignedTo,
    required this.title,
    required this.description,
    required this.category,
    required this.priority,
    required this.status,
    this.deviceInfo,
    this.attachments = const [],
    this.resolvedAt,
    required this.createdAt,
    required this.updatedAt,
    this.creator,
    this.assignee,
  });

  factory SupportTicketModel.fromJson(Map<String, dynamic> json) {
    UserModel? parsedCreator;
    UserModel? parsedAssignee;

    if (json['creator'] != null && json['creator'] is Map<String, dynamic>) {
      parsedCreator = UserModel.fromJson(json['creator']);
    }
    if (json['assignee'] != null && json['assignee'] is Map<String, dynamic>) {
      parsedAssignee = UserModel.fromJson(json['assignee']);
    }

    return SupportTicketModel(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String,
      assignedTo: json['assigned_to'] as String?,
      title: json['title'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
      priority: json['priority'] as String,
      status: json['status'] as String,
      deviceInfo: json['device_info'] as String?,
      attachments:
          (json['attachments'] as List?)?.map((e) => e.toString()).toList() ??
              [],
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      creator: parsedCreator,
      assignee: parsedAssignee,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'creator_id': creatorId,
      'assigned_to': assignedTo,
      'title': title,
      'description': description,
      'category': category,
      'priority': priority,
      'status': status,
      'device_info': deviceInfo,
      'attachments': attachments,
      'resolved_at': resolvedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  SupportTicketModel copyWith({
    String? id,
    String? creatorId,
    String? assignedTo,
    String? title,
    String? description,
    String? category,
    String? priority,
    String? status,
    String? deviceInfo,
    List<String>? attachments,
    DateTime? resolvedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    UserModel? creator,
    UserModel? assignee,
  }) {
    return SupportTicketModel(
      id: id ?? this.id,
      creatorId: creatorId ?? this.creatorId,
      assignedTo: assignedTo ?? this.assignedTo,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      attachments: attachments ?? this.attachments,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      creator: creator ?? this.creator,
      assignee: assignee ?? this.assignee,
    );
  }
}
