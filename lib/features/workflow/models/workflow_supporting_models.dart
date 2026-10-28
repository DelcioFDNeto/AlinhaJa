class WorkflowStatusConfig {
  /// Nomes historicamente usados para a etapa de cancelamento, antes da coluna
  /// `is_cancelled` existir. Mantido como fallback para canais antigos.
  static const Set<String> legacyCancelledNames = {
    'cancelado',
    'cancelada',
    'cancelled',
    'canceled',
  };

  final String id;
  final String channelId;
  final String status;
  final int statusOrder;
  final String color;
  final String icon;
  final bool isFinal;

  /// Etapa onde os cards nascem.
  final bool isInitial;

  /// Etapa de cancelamento: fica fora do funil e do cálculo de SLA.
  final bool isCancelled;

  WorkflowStatusConfig({
    required this.id,
    required this.channelId,
    required this.status,
    required this.statusOrder,
    this.color = '#6B7280',
    this.icon = 'circle',
    this.isFinal = false,
    this.isInitial = false,
    bool? isCancelled,
  }) : isCancelled =
            isCancelled ?? legacyCancelledNames.contains(status.toLowerCase().trim());

  factory WorkflowStatusConfig.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString() ?? '';
    final rawCancelled = json['is_cancelled'];
    return WorkflowStatusConfig(
      id: json['id']?.toString() ?? '',
      channelId: json['channel_id']?.toString() ?? '',
      status: status,
      statusOrder: int.tryParse(json['status_order']?.toString() ?? '0') ?? 0,
      color: json['color']?.toString() ?? '#6B7280',
      icon: json['icon']?.toString() ?? 'circle',
      isFinal: json['is_final'] == true || json['is_final'] == 'true',
      isInitial: json['is_initial'] == true || json['is_initial'] == 'true',
      // A coluna pode não existir em bancos que ainda não rodaram a migration
      // 20260813100000 — nesse caso cai na heurística por nome.
      isCancelled: rawCancelled == null
          ? null
          : (rawCancelled == true || rawCancelled == 'true'),
    );
  }

  int get colorValue {
    final hex = color.replaceAll('#', '');
    return int.parse('FF$hex', radix: 16);
  }
}

class WorkflowCardComment {
  final String id;
  final String cardId;
  final String userId;
  final String content;
  final List<Map<String, dynamic>> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? userName;
  final String? userAvatar;

  WorkflowCardComment({
    required this.id,
    required this.cardId,
    required this.userId,
    required this.content,
    this.attachments = const [],
    required this.createdAt,
    required this.updatedAt,
    this.userName,
    this.userAvatar,
  });

  factory WorkflowCardComment.fromJson(Map<String, dynamic> json) {
    return WorkflowCardComment(
      id: json['id']?.toString() ?? '',
      cardId: json['card_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      attachments: json['attachments'] != null
          ? List<Map<String, dynamic>>.from(json['attachments'])
          : [],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      userName: json['user_name']?.toString(),
      userAvatar: json['user_avatar']?.toString(),
    );
  }
}

class WorkflowCardHistory {
  final String id;
  final String cardId;
  final String? userId;
  final String action;
  final String? fieldChanged;
  final String? oldValue;
  final String? newValue;
  final String? observations;
  final DateTime createdAt;
  final String? userName;

  WorkflowCardHistory({
    required this.id,
    required this.cardId,
    this.userId,
    required this.action,
    this.fieldChanged,
    this.oldValue,
    this.newValue,
    this.observations,
    required this.createdAt,
    this.userName,
  });

  factory WorkflowCardHistory.fromJson(Map<String, dynamic> json) {
    return WorkflowCardHistory(
      id: json['id']?.toString() ?? '',
      cardId: json['card_id']?.toString() ?? '',
      userId: json['user_id']?.toString(),
      action: json['action']?.toString() ?? '',
      fieldChanged: json['field_changed']?.toString(),
      oldValue: json['old_value']?.toString(),
      newValue: json['new_value']?.toString(),
      observations: json['observations']?.toString(),
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
              .toLocal()
          : DateTime.now(),
      userName: json['users']?['full_name']?.toString() ??
          json['user_name']?.toString(),
    );
  }
}
