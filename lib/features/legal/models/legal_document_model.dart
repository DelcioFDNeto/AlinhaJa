import 'package:flutter/foundation.dart';

/// Modelos do que o **servidor** devolve sobre o titular.
///
/// O catálogo de documentos NÃO mora aqui: ele é único e vive em
/// `data/legal_documents.dart`. Já existiu uma segunda lista neste arquivo, e
/// manter as duas versões em sincronia à mão é justamente o que faz o reaceite
/// falhar sem barulho.

/// Registro de aceite retornado pela RPC / banco de dados.
@immutable
class PolicyAcceptanceRecord {
  final String policyType;
  final String policyVersion;
  final DateTime acceptedAt;

  const PolicyAcceptanceRecord({
    required this.policyType,
    required this.policyVersion,
    required this.acceptedAt,
  });

  factory PolicyAcceptanceRecord.fromJson(Map<String, dynamic> json) {
    return PolicyAcceptanceRecord(
      policyType: json['policy_type'] as String? ?? json['tipo'] as String? ?? '',
      policyVersion: json['policy_version'] as String? ?? json['versao'] as String? ?? '',
      acceptedAt: DateTime.tryParse(json['accepted_at'] as String? ?? json['aceito_em'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Pedido formal de titular retornado ou enviado ao servidor.
@immutable
class TitularRequestRecord {
  final String id;
  final String tipo;
  final String? descricao;
  final String status;
  final String? resposta;
  final DateTime? respondidoEm;
  final DateTime createdAt;

  const TitularRequestRecord({
    required this.id,
    required this.tipo,
    this.descricao,
    required this.status,
    this.resposta,
    this.respondidoEm,
    required this.createdAt,
  });

  factory TitularRequestRecord.fromJson(Map<String, dynamic> json) {
    return TitularRequestRecord(
      id: json['id'] as String? ?? '',
      tipo: json['tipo'] as String? ?? '',
      descricao: json['descricao'] as String?,
      status: json['status'] as String? ?? 'aberto',
      resposta: json['resposta'] as String?,
      respondidoEm: json['respondido_em'] != null ? DateTime.tryParse(json['respondido_em'] as String) : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
