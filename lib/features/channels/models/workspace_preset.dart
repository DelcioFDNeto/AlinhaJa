import 'package:flutter/material.dart';
import 'package:alinha_ja/core/utils/icon_registry.dart';
import 'package:alinha_ja/features/workflow/models/workflow_supporting_models.dart';

/// Paleta padrão oferecida nos seletores de cor de workspace e de etapa.
class WorkspacePalette {
  WorkspacePalette._();

  static const List<String> colors = [
    '#3B82F6', // azul
    '#0EA5E9', // ciano
    '#22C55E', // verde
    '#10B981', // esmeralda
    '#F59E0B', // âmbar
    '#F97316', // laranja
    '#EF4444', // vermelho
    '#EC4899', // rosa
    '#8B5CF6', // roxo
    '#6366F1', // índigo
    '#14B8A6', // teal
    '#6B7280', // cinza
    '#2E7D32', // verde escuro
    '#E65100', // laranja escuro
    '#1565C0', // azul escuro
    '#7B1FA2', // roxo escuro
    '#C62828', // vermelho escuro
    '#0369A1', // azul petróleo
  ];

  static Color toColor(String hex, {Color fallback = const Color(0xFF6B7280)}) {
    final parsed = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed | 0xFF000000);
  }

  static String fromColor(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

/// Categorias de workspace usadas nos filtros da aba de canais.
class WorkspaceCategories {
  WorkspaceCategories._();

  static const Map<String, String> labels = {
    'financeiro': 'Financeiro',
    'faturamento': 'Faturamento',
    'operacional': 'Operacional',
    'informativo': 'Informativo',
    'rh': 'RH',
    'comercial': 'Comercial',
    'ti': 'TI',
  };

  static const Map<String, String> icons = {
    'financeiro': 'payments_outlined',
    'faturamento': 'receipt_long_outlined',
    'operacional': 'build_circle_outlined',
    'informativo': 'campaign_outlined',
    'rh': 'people_outline',
    'comercial': 'storefront',
    'ti': 'code',
  };

  static String label(String key) => labels[key] ?? _titleCase(key);

  static String _titleCase(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

/// Rascunho mutável de uma etapa do Kanban.
///
/// É o formato usado pelo builder de etapas na criação de workspace, na edição
/// e no editor de presets. [id] só é preenchido quando a etapa já existe em
/// `workflow_status_config` — é o que permite ao backend distinguir renomear de
/// criar.
class WorkflowStageDraft {
  /// `null` para etapas ainda não persistidas.
  String? id;
  String status;
  String color;
  String icon;
  bool isFinal;
  bool isInitial;
  bool isCancelled;

  /// Chave estável para o `ReorderableListView`, independente de [id].
  final String localKey;

  WorkflowStageDraft({
    this.id,
    required this.status,
    this.color = '#6B7280',
    this.icon = 'circle',
    this.isFinal = false,
    this.isInitial = false,
    this.isCancelled = false,
    String? localKey,
  }) : localKey = localKey ??
            'stage_${DateTime.now().microsecondsSinceEpoch}_${status.hashCode}';

  factory WorkflowStageDraft.fromJson(Map<String, dynamic> json) {
    return WorkflowStageDraft(
      id: json['id']?.toString(),
      status: json['status']?.toString() ?? '',
      color: json['color']?.toString() ?? '#6B7280',
      icon: json['icon']?.toString() ?? 'circle',
      isFinal: json['is_final'] == true || json['is_final'] == 'true',
      isInitial: json['is_initial'] == true || json['is_initial'] == 'true',
      isCancelled: json['is_cancelled'] == true || json['is_cancelled'] == 'true',
    );
  }

  factory WorkflowStageDraft.fromConfig(WorkflowStatusConfig config) {
    return WorkflowStageDraft(
      id: config.id.startsWith('fallback_') || config.id.startsWith('temp_')
          ? null
          : config.id,
      status: config.status,
      color: config.color,
      icon: config.icon,
      isFinal: config.isFinal,
      isInitial: config.isInitial,
      isCancelled: config.isCancelled,
    );
  }

  WorkflowStageDraft copy() => WorkflowStageDraft(
        id: id,
        status: status,
        color: color,
        icon: icon,
        isFinal: isFinal,
        isInitial: isInitial,
        isCancelled: isCancelled,
        localKey: localKey,
      );

  /// Cópia desvinculada de qualquer canal — usada ao virar preset.
  WorkflowStageDraft detached() => WorkflowStageDraft(
        status: status,
        color: color,
        icon: icon,
        isFinal: isFinal,
        isInitial: isInitial,
        isCancelled: isCancelled,
      );

  Color get colorValue => WorkspacePalette.toColor(color);

  IconData get iconData => IconRegistry.resolve(icon);

  Map<String, dynamic> toJson(int order) => {
        if (id != null) 'id': id,
        'status': status.trim(),
        'status_order': order,
        'color': color,
        'icon': icon,
        'is_final': isFinal,
        'is_initial': isInitial,
        'is_cancelled': isCancelled,
      };
}

/// Serializa uma lista de rascunhos aplicando a ordem pela posição na lista.
List<Map<String, dynamic>> stagesToJson(List<WorkflowStageDraft> stages) {
  return List.generate(
    stages.length,
    (i) => stages[i].toJson(i + 1),
  );
}

/// Modelo de um preset de workspace (`public.workspace_presets`).
class WorkspacePreset {
  final String id;
  final String name;
  final String? description;
  final String category;
  final String icon;
  final String color;
  final String cardType;
  final bool workflowEnabled;
  final String assignmentMode;
  final String postingPermission;
  final List<WorkflowStageDraft> stages;

  /// Presets de sistema são somente leitura — a UI oferece "Duplicar".
  final bool isSystem;

  /// `false` = preset privado, visível apenas para o dono.
  final bool isShared;
  final String? createdBy;
  final String? createdByName;
  final int usageCount;
  final DateTime? updatedAt;

  const WorkspacePreset({
    required this.id,
    required this.name,
    this.description,
    this.category = 'operacional',
    this.icon = 'workspaces_rounded',
    this.color = '#616161',
    this.cardType = 'generic',
    this.workflowEnabled = true,
    this.assignmentMode = 'operator_pool',
    this.postingPermission = 'everyone',
    this.stages = const [],
    this.isSystem = false,
    this.isShared = true,
    this.createdBy,
    this.createdByName,
    this.usageCount = 0,
    this.updatedAt,
  });

  factory WorkspacePreset.fromJson(Map<String, dynamic> json) {
    final rawStages = json['status_config'];
    return WorkspacePreset(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Preset',
      description: json['description']?.toString(),
      category: json['category']?.toString() ?? 'operacional',
      icon: json['icon']?.toString() ?? 'workspaces_rounded',
      color: json['color']?.toString() ?? '#616161',
      cardType: json['card_type']?.toString() ?? 'generic',
      workflowEnabled: json['workflow_enabled'] != false,
      assignmentMode: json['assignment_mode']?.toString() ?? 'operator_pool',
      postingPermission: json['posting_permission']?.toString() ?? 'everyone',
      stages: rawStages is List
          ? rawStages
              .whereType<Map>()
              .map((e) =>
                  WorkflowStageDraft.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      isSystem: json['is_system'] == true,
      isShared: json['is_shared'] != false,
      createdBy: json['created_by']?.toString(),
      createdByName: json['users'] is Map
          ? (json['users'] as Map)['full_name']?.toString()
          : json['created_by_name']?.toString(),
      usageCount: int.tryParse(json['usage_count']?.toString() ?? '0') ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Color get colorValue => WorkspacePalette.toColor(color);

  IconData get iconData => IconRegistry.resolve(icon);

  String get categoryLabel => WorkspaceCategories.label(category);

  /// Etapas recém-instanciadas e sem vínculo com canal, prontas para o builder.
  List<WorkflowStageDraft> freshStages() =>
      stages.map((s) => s.detached()).toList();

  /// Editável apenas quando não é preset de sistema.
  bool canEdit(String? userId, {bool isGlobalAdmin = false}) {
    if (isSystem) return false;
    return isGlobalAdmin || (createdBy != null && createdBy == userId);
  }
}
