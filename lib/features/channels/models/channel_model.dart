import 'package:flutter/material.dart';
import 'package:alinha_ja/core/utils/icon_registry.dart';

class ChannelModel {
  final String id;
  final String name;
  final String? description;
  final String? createdBy;
  final String type;
  final String postingPermission;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int unreadCount;
  final Map<String, dynamic>? metadata;

  ChannelModel({
    required this.id,
    required this.name,
    this.description,
    this.createdBy,
    this.type = 'comum',
    this.postingPermission = 'everyone',
    this.lastMessageAt,
    this.createdAt,
    this.updatedAt,
    this.unreadCount = 0,
    this.metadata,
  });

  String? get iconCode {
    final raw = metadata?['icon'];
    if (raw == null) return null;
    return raw.toString();
  }

  Color? get metadataColor {
    final colorHex = metadata?['color']?.toString();
    if (colorHex == null || colorHex.isEmpty) return null;
    final parsed = int.tryParse(colorHex.replaceFirst('#', ''), radix: 16);
    if (parsed == null) return null;
    return Color(parsed + 0xFF000000);
  }

  IconData get icon => IconRegistry.resolve(iconCode);

  factory ChannelModel.fromJson(Map<String, dynamic> json) {
    return ChannelModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Canal Desconhecido',
      description: json['description']?.toString(),
      createdBy: json['created_by']?.toString(),
      type: json['type']?.toString() ?? 'comum',
      postingPermission: json['posting_permission']?.toString() ?? 'everyone',
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.tryParse(json['last_message_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      unreadCount: int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}
