import 'dart:convert';
import 'package:alinha_ja/features/hr/models/email_template.dart';

class AutomationRule {
  final String? id;
  final String? organizationId;
  final String evento;
  final Map<String, dynamic> condicao;
  final String acao;
  final String? templateId;
  final bool ativo;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  
  // Relação carregada no JOIN
  final EmailTemplate? template;

  AutomationRule({
    this.id,
    this.organizationId,
    this.evento = 'mudanca_etapa',
    required this.condicao,
    this.acao = 'enviar_email',
    this.templateId,
    this.ativo = true,
    this.createdAt,
    this.updatedAt,
    this.template,
  });

  factory AutomationRule.fromMap(Map<String, dynamic> map) {
    dynamic condicaoData = map['condicao'];
    Map<String, dynamic> condicaoMap = {};
    if (condicaoData is String) {
      condicaoMap = jsonDecode(condicaoData) as Map<String, dynamic>;
    } else if (condicaoData is Map) {
      condicaoMap = Map<String, dynamic>.from(condicaoData);
    }

    return AutomationRule(
      id: map['id'] as String?,
      organizationId: map['organization_id'] as String?,
      evento: map['evento'] as String? ?? 'mudanca_etapa',
      condicao: condicaoMap,
      acao: map['acao'] as String? ?? 'enviar_email',
      templateId: map['template_id'] as String?,
      ativo: map['ativo'] as bool? ?? true,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
      template: map['rh_email_template'] != null ? EmailTemplate.fromMap(map['rh_email_template']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      'evento': evento,
      'condicao': condicao, // jsonb no banco aceita Map diretamente via supabase-dart
      'acao': acao,
      if (templateId != null) 'template_id': templateId,
      'ativo': ativo,
    };
  }
}
