class HoleriteModel {
  final String id;
  final String organizationId;
  final String funcionarioId;
  final String? funcionarioNome;
  final int mesReferencia;
  final int anoReferencia;
  final String? arquivoPdfPath;
  final Map<String, dynamic>? dadosGerados;
  final DateTime dataDisponibilizacao;
  final DateTime? dataVisualizacao;
  final DateTime createdAt;

  const HoleriteModel({
    required this.id,
    required this.organizationId,
    required this.funcionarioId,
    this.funcionarioNome,
    required this.mesReferencia,
    required this.anoReferencia,
    this.arquivoPdfPath,
    this.dadosGerados,
    required this.dataDisponibilizacao,
    this.dataVisualizacao,
    required this.createdAt,
  });

  static const _meses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  /// "Março/2026" — competência exibível.
  String get competencia => '${_meses[mesReferencia - 1]}/$anoReferencia';

  factory HoleriteModel.fromMap(Map<String, dynamic> map) {
    return HoleriteModel(
      id: map['id'] as String,
      organizationId: map['organization_id'] as String,
      funcionarioId: map['funcionario_id'] as String,
      funcionarioNome: map['funcionario']?['nome'] as String?,
      mesReferencia: map['mes_referencia'] as int,
      anoReferencia: map['ano_referencia'] as int,
      arquivoPdfPath: map['arquivo_pdf_path'] as String?,
      dadosGerados: map['dados_gerados'] as Map<String, dynamic>?,
      dataDisponibilizacao: DateTime.parse(map['data_disponibilizacao']),
      dataVisualizacao: map['data_visualizacao'] != null
          ? DateTime.parse(map['data_visualizacao'])
          : null,
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
