import 'package:alinha_ja/features/workflow/models/workflow_enums.dart';

class WorkflowCard {
  final String id;
  final String channelId;
  final WorkflowCardType cardType;
  final String title;
  final String? description;

  // Campos específicos - Conta Pagar
  final String? supplier;
  final String? expenseDescription;
  final double? amount;
  final DateTime? dueDate;
  final String? costCenter;

  // Campos específicos - Liberação de Pedido (legado: fat_moto)
  final String? clientName;
  final String? orderNumber;
  final String? fichaNumber;
  final String? consultant;

  // Campos específicos - Documentação/Cadastro (legado: emplacamento)
  final String? clientCpfCnpj;
  final String? vehicleModel;
  final String? chassisNumber;
  final String? plate;
  final String? branch;

  // Campos específicos - Faturamento OS
  final String? osNumber;
  final String? budgetNumber;
  final String? billingType;
  final String? itemsDetails;

  // Campos comuns
  final String? observations;
  final List<Map<String, dynamic>> attachments;
  final WorkflowPriority priority;
  final String status;
  final String? assignedTo;
  final String? assignedToName;
  final String? requestedBy;
  final String? requestedByName;
  final bool isPinned;
  final bool isArchived;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkflowCard({
    required this.id,
    required this.channelId,
    required this.cardType,
    required this.title,
    this.description,
    this.supplier,
    this.expenseDescription,
    this.amount,
    this.dueDate,
    this.costCenter,
    this.clientName,
    this.orderNumber,
    this.fichaNumber,
    this.consultant,
    this.clientCpfCnpj,
    this.vehicleModel,
    this.chassisNumber,
    this.plate,
    this.branch,
    this.osNumber,
    this.budgetNumber,
    this.billingType,
    this.itemsDetails,
    this.observations,
    this.attachments = const [],
    this.priority = WorkflowPriority.medium,
    required this.status,
    this.assignedTo,
    this.assignedToName,
    this.requestedBy,
    this.requestedByName,
    this.isPinned = false,
    this.isArchived = false,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkflowCard.fromJson(Map<String, dynamic> json) {
    return WorkflowCard(
      id: json['id']?.toString() ?? '',
      channelId: json['channel_id']?.toString() ?? '',
      cardType: WorkflowCardType.fromString(
          json['card_type']?.toString() ?? 'generic'),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      supplier: json['supplier']?.toString(),
      expenseDescription: json['expense_description']?.toString(),
      amount: json['amount'] != null ? _parseNumeric(json['amount']) : null,
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'].toString())
          : null,
      costCenter: json['cost_center']?.toString(),
      clientName: json['client_name']?.toString(),
      orderNumber: json['order_number']?.toString(),
      fichaNumber: json['ficha_number']?.toString(),
      consultant: json['consultant']?.toString(),
      clientCpfCnpj: json['client_cpf_cnpj']?.toString(),
      vehicleModel: json['vehicle_model']?.toString(),
      chassisNumber: json['chassis_number']?.toString(),
      plate: json['plate']?.toString(),
      branch: json['branch']?.toString(),
      osNumber: json['os_number']?.toString(),
      budgetNumber: json['budget_number']?.toString(),
      billingType: json['billing_type']?.toString(),
      itemsDetails: json['items_details']?.toString(),
      observations: json['observations']?.toString(),
      attachments: json['attachments'] != null
          ? List<Map<String, dynamic>>.from(json['attachments'])
          : [],
      priority:
          WorkflowPriority.fromString(json['priority']?.toString() ?? 'medium'),
      status: json['status']?.toString() ?? 'novo',
      assignedTo: json['assigned_to']?.toString(),
      assignedToName: (json['assigned_user'] is Map)
          ? json['assigned_user']['full_name']?.toString()
          : null,
      requestedBy: json['requested_by']?.toString(),
      requestedByName: (json['requester_user'] is Map)
          ? json['requester_user']['full_name']?.toString()
          : null,
      isPinned: json['is_pinned'] == true || json['is_pinned'] == 'true',
      isArchived: json['is_archived'] == true || json['is_archived'] == 'true',
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'])
          : {},
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'channel_id': channelId,
      'card_type': cardType.value,
      'title': title,
      'description': description,
      'supplier': supplier,
      'expense_description': expenseDescription,
      'amount': amount,
      'due_date': dueDate?.toIso8601String().split('T')[0],
      'cost_center': costCenter,
      'client_name': clientName,
      'order_number': orderNumber,
      'ficha_number': fichaNumber,
      'consultant': consultant,
      'client_cpf_cnpj': clientCpfCnpj,
      'vehicle_model': vehicleModel,
      'chassis_number': chassisNumber,
      'plate': plate,
      'branch': branch,
      'os_number': osNumber,
      'budget_number': budgetNumber,
      'billing_type': billingType,
      'items_details': itemsDetails,
      'observations': observations,
      'attachments': attachments,
      'priority': priority.value,
      'status': status,
      'assigned_to': assignedTo,
      'requested_by': requestedBy,
      'is_pinned': isPinned,
      'is_archived': isArchived,
      'metadata': metadata,
    };

    if (id.isNotEmpty) {
      map['id'] = id;
      map['created_at'] = createdAt.toIso8601String();
      map['updated_at'] = updatedAt.toIso8601String();
    }

    // S3: Remove null values to avoid conflicts with Supabase defaults/constraints
    map.removeWhere((key, value) => value == null);

    return map;
  }

  WorkflowCard copyWith({
    String? id,
    String? channelId,
    WorkflowCardType? cardType,
    String? title,
    String? description,
    String? supplier,
    String? expenseDescription,
    double? amount,
    DateTime? dueDate,
    String? costCenter,
    String? clientName,
    String? orderNumber,
    String? fichaNumber,
    String? consultant,
    String? clientCpfCnpj,
    String? vehicleModel,
    String? chassisNumber,
    String? plate,
    String? branch,
    String? osNumber,
    String? budgetNumber,
    String? billingType,
    String? itemsDetails,
    String? observations,
    List<Map<String, dynamic>>? attachments,
    WorkflowPriority? priority,
    String? status,
    String? assignedTo,
    String? assignedToName,
    String? requestedBy,
    String? requestedByName,
    bool? isPinned,
    bool? isArchived,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkflowCard(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      cardType: cardType ?? this.cardType,
      title: title ?? this.title,
      description: description ?? this.description,
      supplier: supplier ?? this.supplier,
      expenseDescription: expenseDescription ?? this.expenseDescription,
      amount: amount ?? this.amount,
      dueDate: dueDate ?? this.dueDate,
      costCenter: costCenter ?? this.costCenter,
      clientName: clientName ?? this.clientName,
      orderNumber: orderNumber ?? this.orderNumber,
      fichaNumber: fichaNumber ?? this.fichaNumber,
      consultant: consultant ?? this.consultant,
      clientCpfCnpj: clientCpfCnpj ?? this.clientCpfCnpj,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      chassisNumber: chassisNumber ?? this.chassisNumber,
      plate: plate ?? this.plate,
      branch: branch ?? this.branch,
      osNumber: osNumber ?? this.osNumber,
      budgetNumber: budgetNumber ?? this.budgetNumber,
      billingType: billingType ?? this.billingType,
      itemsDetails: itemsDetails ?? this.itemsDetails,
      observations: observations ?? this.observations,
      attachments: attachments ?? this.attachments,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToName: assignedToName ?? this.assignedToName,
      requestedBy: requestedBy ?? this.requestedBy,
      requestedByName: requestedByName ?? this.requestedByName,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static double _parseNumeric(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String get displayAmount {
    if (amount == null) return 'R\$ 0,00';
    return 'R\$ ${amount!.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String get displayDueDate {
    if (dueDate == null) return '-';
    return '${dueDate!.day.toString().padLeft(2, '0')}/${dueDate!.month.toString().padLeft(2, '0')}/${dueDate!.year}';
  }
}
