/// Models da Onda 2 — Vagas (RH-10) e Catálogo Áreas/Cargos (RH-9).
/// Espelham `vaga_resumo` (view), `rh_area` e `rh_cargo`.
library;

import 'package:alinha_ja/core/status_role.dart';

/// Status da vaga (enum `vaga_status` no banco).
class VagaStatus {
  VagaStatus._();

  static const rascunho = 'rascunho';
  static const aberta = 'aberta';
  static const pausada = 'pausada';
  static const fechada = 'fechada';

  static const labels = {
    rascunho: 'Rascunho',
    aberta: 'Aberta',
    pausada: 'Pausada',
    fechada: 'Fechada',
  };

  static String label(String s) => labels[s] ?? s;

  /// Papel semântico por status — cor resolvida no tema (white-label).
  static const roles = {
    rascunho: StatusRole.neutral,
    aberta: StatusRole.success,
    pausada: StatusRole.warning,
    fechada: StatusRole.neutral,
  };

  static StatusRole role(String s) => roles[s] ?? StatusRole.neutral;

  /// Transições oferecidas na UI a partir do status atual.
  static List<String> transicoesDe(String atual) {
    switch (atual) {
      case rascunho:
        return const [aberta];
      case aberta:
        return const [pausada, fechada];
      case pausada:
        return const [aberta, fechada];
      case fechada:
        return const [aberta]; // reabrir
      default:
        return const [];
    }
  }
}

/// Linha da view `vaga_resumo` (vaga + nomes do catálogo + contadores).
class VagaModel {
  final String id;
  final String titulo;
  final String? areaId;
  final String? cargoId;
  final String? areaNome;
  final String? cargoNome;
  final String? nivel;
  final String? tipoContrato;
  final String? localidade;
  final bool remoto;
  final String? faixaSalarial;
  final String? descricao;
  final String? requisitos;
  final String status;
  final int? vagasQtd;
  final DateTime? publicadaEm;
  final DateTime? expiraEm;
  final int candidatosTotal;
  final int candidatosEmProcesso;

  const VagaModel({
    required this.id,
    required this.titulo,
    this.areaId,
    this.cargoId,
    this.areaNome,
    this.cargoNome,
    this.nivel,
    this.tipoContrato,
    this.localidade,
    this.remoto = false,
    this.faixaSalarial,
    this.descricao,
    this.requisitos,
    required this.status,
    this.vagasQtd,
    this.publicadaEm,
    this.expiraEm,
    this.candidatosTotal = 0,
    this.candidatosEmProcesso = 0,
  });

  factory VagaModel.fromJson(Map<String, dynamic> json) => VagaModel(
        id: json['id'] as String,
        titulo: (json['titulo'] as String?) ?? '',
        areaId: json['area_id'] as String?,
        cargoId: json['cargo_id'] as String?,
        areaNome: json['area_nome'] as String?,
        cargoNome: json['cargo_nome'] as String?,
        nivel: json['nivel'] as String?,
        tipoContrato: json['tipo_contrato'] as String?,
        localidade: json['localidade'] as String?,
        remoto: (json['remoto'] as bool?) ?? false,
        faixaSalarial: json['faixa_salarial'] as String?,
        descricao: json['descricao'] as String?,
        requisitos: json['requisitos'] as String?,
        status: (json['status'] as String?) ?? VagaStatus.rascunho,
        vagasQtd: (json['vagas_qtd'] as num?)?.toInt(),
        publicadaEm: json['publicada_em'] != null
            ? DateTime.tryParse(json['publicada_em'] as String)
            : null,
        expiraEm: json['expira_em'] != null
            ? DateTime.tryParse(json['expira_em'] as String)
            : null,
        candidatosTotal: ((json['candidatos_total'] ?? 0) as num).toInt(),
        candidatosEmProcesso:
            ((json['candidatos_em_processo'] ?? 0) as num).toInt(),
      );

  bool get expirada =>
      expiraEm != null &&
      expiraEm!.isBefore(DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day));
}

/// Item do catálogo (rh_area / rh_cargo — RH-9).
class CatalogItem {
  final String id;
  final String nome;
  final bool ativo;

  /// Só em cargos: área a que pertence e nível sugerido.
  final String? areaId;
  final String? nivelSugerido;

  const CatalogItem({
    required this.id,
    required this.nome,
    this.ativo = true,
    this.areaId,
    this.nivelSugerido,
  });

  factory CatalogItem.fromJson(Map<String, dynamic> json) => CatalogItem(
        id: json['id'] as String,
        nome: (json['nome'] as String?) ?? '',
        ativo: (json['ativo'] as bool?) ?? true,
        areaId: json['area_id'] as String?,
        nivelSugerido: json['nivel_sugerido'] as String?,
      );
}
