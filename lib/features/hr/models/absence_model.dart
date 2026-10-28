/// RH-26 — saldo de um período aquisitivo de férias.
/// Espelha a view `rh_ferias_saldo`.
class FeriasSaldo {
  final String periodoId;
  final String funcionarioId;
  final String funcionarioNome;
  final DateTime inicio;
  final DateTime fim;
  final DateTime limiteGozo;
  final String status;
  final int diasDireito;
  final int diasAbonados;
  final int diasGozados;

  /// Dias em solicitações pendentes — já comprometidos, ainda não gozados.
  final int diasReservados;
  final int diasDisponiveis;

  /// Passou do limite concessivo (12 meses após o fim do aquisitivo).
  final bool vencido;

  const FeriasSaldo({
    required this.periodoId,
    required this.funcionarioId,
    required this.funcionarioNome,
    required this.inicio,
    required this.fim,
    required this.limiteGozo,
    required this.status,
    required this.diasDireito,
    required this.diasAbonados,
    required this.diasGozados,
    required this.diasReservados,
    required this.diasDisponiveis,
    required this.vencido,
  });

  bool get aberto => status == 'aberto';

  /// Perto de vencer: menos de 90 dias para o limite de gozo.
  bool get venceEmBreve =>
      !vencido &&
      limiteGozo.difference(DateTime.now()).inDays <= 90 &&
      diasDisponiveis > 0;

  factory FeriasSaldo.fromJson(Map<String, dynamic> json) => FeriasSaldo(
        periodoId: json['periodo_id'] as String,
        funcionarioId: json['funcionario_id'] as String,
        funcionarioNome: (json['funcionario_nome'] as String?) ?? '',
        inicio: DateTime.parse(json['inicio'] as String),
        fim: DateTime.parse(json['fim'] as String),
        limiteGozo: DateTime.parse(json['limite_gozo'] as String),
        status: (json['status'] as String?) ?? 'aberto',
        diasDireito: ((json['dias_direito'] ?? 0) as num).toInt(),
        diasAbonados: ((json['dias_abonados'] ?? 0) as num).toInt(),
        diasGozados: ((json['dias_gozados'] ?? 0) as num).toInt(),
        diasReservados: ((json['dias_reservados'] ?? 0) as num).toInt(),
        diasDisponiveis: ((json['dias_disponiveis'] ?? 0) as num).toInt(),
        vencido: json['vencido'] == true,
      );
}

/// RH-26 — ausência na visão de calendário (`rh_ausencia_calendario`).
class AbsenceCalendarEntry {
  final String id;
  final String funcionarioId;
  final String funcionarioNome;
  final String tipo;
  final String status;
  final DateTime dataInicio;
  final DateTime dataFim;
  final int dias;

  const AbsenceCalendarEntry({
    required this.id,
    required this.funcionarioId,
    required this.funcionarioNome,
    required this.tipo,
    required this.status,
    required this.dataInicio,
    required this.dataFim,
    required this.dias,
  });

  /// A ausência cobre [dia]? Comparação por data, ignorando hora.
  bool cobre(DateTime dia) {
    final d = DateTime(dia.year, dia.month, dia.day);
    final i = DateTime(dataInicio.year, dataInicio.month, dataInicio.day);
    final f = DateTime(dataFim.year, dataFim.month, dataFim.day);
    return !d.isBefore(i) && !d.isAfter(f);
  }

  factory AbsenceCalendarEntry.fromJson(Map<String, dynamic> json) =>
      AbsenceCalendarEntry(
        id: json['id'] as String,
        funcionarioId: json['funcionario_id'] as String,
        funcionarioNome: (json['funcionario_nome'] as String?) ?? '',
        tipo: (json['tipo'] as String?) ?? 'outro',
        status: (json['status'] as String?) ?? 'pendente',
        dataInicio: DateTime.parse(json['data_inicio'] as String),
        dataFim: DateTime.parse(json['data_fim'] as String),
        dias: ((json['dias'] ?? 0) as num).toInt(),
      );
}

class AbsenceModel {
  final String id;
  final String organizationId;
  final String funcionarioId;
  final String tipo;
  final DateTime dataInicio;
  final DateTime dataFim;
  final String? justificativa;
  final String? anexoUrl;
  final String status;
  final String? aprovadorId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? funcionarioNome;

  const AbsenceModel({
    required this.id,
    required this.organizationId,
    required this.funcionarioId,
    required this.tipo,
    required this.dataInicio,
    required this.dataFim,
    this.justificativa,
    this.anexoUrl,
    this.status = 'pendente',
    this.aprovadorId,
    this.createdAt,
    this.updatedAt,
    this.funcionarioNome,
  });

  factory AbsenceModel.fromJson(Map<String, dynamic> json) => AbsenceModel(
        id: json['id'] as String,
        organizationId: json['organization_id'] as String,
        funcionarioId: json['funcionario_id'] as String,
        tipo: json['tipo'] as String,
        dataInicio: DateTime.parse(json['data_inicio'] as String),
        dataFim: DateTime.parse(json['data_fim'] as String),
        justificativa: json['justificativa'] as String?,
        anexoUrl: json['anexo_url'] as String?,
        status: (json['status'] as String?) ?? 'pendente',
        aprovadorId: json['aprovador_id'] as String?,
        createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
        updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
        funcionarioNome: json['funcionario_nome'] as String?,
      );
}
