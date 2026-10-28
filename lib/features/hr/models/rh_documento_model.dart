library;

import 'package:alinha_ja/core/status_role.dart';

enum DocumentoCategoria {
  contrato,
  identidade,
  certificacao,
  atestado,
  holerite,
  aso,
  outro
}

enum DocumentoStatus {
  pendenteAprovacao,
  valido,
  proximoVencimento,
  vencido,
  rejeitado
}

class RhDocumento {
  final String id;
  final String organizationId;
  final String funcionarioId;
  final String titulo;
  final String? descricao;
  final DocumentoCategoria categoria;
  final String storagePath;
  final DateTime? dataEmissao;
  final DateTime? dataVencimento;
  final DocumentoStatus status;
  final String? motivoRejeicao;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// RH-24: o RH exige que o funcionário declare ciência/concordância.
  final bool exigeAceite;

  /// Instante do aceite, carimbado pelo servidor. `null` = ainda pendente.
  final DateTime? aceitoEm;

  const RhDocumento({
    required this.id,
    required this.organizationId,
    required this.funcionarioId,
    required this.titulo,
    this.descricao,
    required this.categoria,
    required this.storagePath,
    this.dataEmissao,
    this.dataVencimento,
    required this.status,
    this.motivoRejeicao,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.exigeAceite = false,
    this.aceitoEm,
  });

  /// Aguardando o aceite do funcionário.
  bool get aceitePendente => exigeAceite && aceitoEm == null;

  factory RhDocumento.fromJson(Map<String, dynamic> json) {
    return RhDocumento(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      funcionarioId: json['funcionario_id'] as String,
      titulo: json['titulo'] as String,
      descricao: json['descricao'] as String?,
      categoria: _parseCategoria(json['categoria'] as String?),
      storagePath: json['storage_path'] as String,
      dataEmissao: json['data_emissao'] != null ? DateTime.parse(json['data_emissao'] as String) : null,
      dataVencimento: json['data_vencimento'] != null ? DateTime.parse(json['data_vencimento'] as String) : null,
      status: _parseStatus(json['status'] as String?),
      motivoRejeicao: json['motivo_rejeicao'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deletedAt: json['deleted_at'] != null ? DateTime.parse(json['deleted_at'] as String) : null,
      exigeAceite: json['exige_aceite'] == true,
      aceitoEm: json['aceito_em'] != null ? DateTime.parse(json['aceito_em'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'funcionario_id': funcionarioId,
      'titulo': titulo,
      'descricao': descricao,
      'categoria': _categoriaToString(categoria),
      'storage_path': storagePath,
      'data_emissao': dataEmissao?.toIso8601String(),
      'data_vencimento': dataVencimento?.toIso8601String(),
      'status': _statusToString(status),
      'motivo_rejeicao': motivoRejeicao,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'exige_aceite': exigeAceite,
      'aceito_em': aceitoEm?.toIso8601String(),
    };
  }

  static DocumentoCategoria _parseCategoria(String? cat) {
    switch (cat) {
      case 'contrato': return DocumentoCategoria.contrato;
      case 'identidade': return DocumentoCategoria.identidade;
      case 'certificacao': return DocumentoCategoria.certificacao;
      case 'atestado': return DocumentoCategoria.atestado;
      case 'holerite': return DocumentoCategoria.holerite;
      case 'aso': return DocumentoCategoria.aso;
      default: return DocumentoCategoria.outro;
    }
  }

  static String _categoriaToString(DocumentoCategoria cat) {
    switch (cat) {
      case DocumentoCategoria.contrato: return 'contrato';
      case DocumentoCategoria.identidade: return 'identidade';
      case DocumentoCategoria.certificacao: return 'certificacao';
      case DocumentoCategoria.atestado: return 'atestado';
      case DocumentoCategoria.holerite: return 'holerite';
      case DocumentoCategoria.aso: return 'aso';
      case DocumentoCategoria.outro: return 'outro';
    }
  }

  static DocumentoStatus _parseStatus(String? status) {
    switch (status) {
      case 'valido': return DocumentoStatus.valido;
      case 'proximo_vencimento': return DocumentoStatus.proximoVencimento;
      case 'vencido': return DocumentoStatus.vencido;
      case 'rejeitado': return DocumentoStatus.rejeitado;
      default: return DocumentoStatus.pendenteAprovacao;
    }
  }

  static String _statusToString(DocumentoStatus status) {
    switch (status) {
      case DocumentoStatus.valido: return 'valido';
      case DocumentoStatus.proximoVencimento: return 'proximo_vencimento';
      case DocumentoStatus.vencido: return 'vencido';
      case DocumentoStatus.rejeitado: return 'rejeitado';
      case DocumentoStatus.pendenteAprovacao: return 'pendente_aprovacao';
    }
  }
}

/// Papel semântico e label de exibição do status de documento, para que as
/// telas (RH e "meus documentos") leiam de uma fonte única — a cor sai dos
/// tokens do tema via [StatusRole].
extension DocumentoStatusX on DocumentoStatus {
  StatusRole get role => switch (this) {
        DocumentoStatus.valido => StatusRole.success,
        DocumentoStatus.pendenteAprovacao => StatusRole.warning,
        DocumentoStatus.proximoVencimento => StatusRole.pending,
        DocumentoStatus.vencido => StatusRole.danger,
        DocumentoStatus.rejeitado => StatusRole.danger,
      };

  String get label => switch (this) {
        DocumentoStatus.valido => 'Válido',
        DocumentoStatus.pendenteAprovacao => 'Pendente de Aprovação',
        DocumentoStatus.proximoVencimento => 'Próximo do Vencimento',
        DocumentoStatus.vencido => 'Vencido',
        DocumentoStatus.rejeitado => 'Rejeitado',
      };
}
