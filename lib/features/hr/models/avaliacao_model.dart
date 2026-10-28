/// Models da Fase 3 — Avaliação Técnica (RH-12).
/// Espelham `questao`, `avaliacao` / view `avaliacao_resumo`.
library;

/// Questão do banco (múltipla escolha). `corretaIdx` só existe no lado
/// do RH — nunca é enviado ao candidato pela Edge Function.
class QuestaoModel {
  final String id;
  final String? cargoId;
  final String? areaId;
  final String? nivel;
  final String enunciado;
  final List<String> opcoes;
  final int corretaIdx;
  final String origem; // manual | ia
  final bool ativa;

  const QuestaoModel({
    required this.id,
    this.cargoId,
    this.areaId,
    this.nivel,
    required this.enunciado,
    required this.opcoes,
    required this.corretaIdx,
    this.origem = 'manual',
    this.ativa = true,
  });

  bool get isIa => origem == 'ia';

  factory QuestaoModel.fromJson(Map<String, dynamic> json) => QuestaoModel(
        id: json['id'] as String,
        cargoId: json['cargo_id'] as String?,
        areaId: json['area_id'] as String?,
        nivel: json['nivel'] as String?,
        enunciado: (json['enunciado'] as String?) ?? '',
        opcoes: ((json['opcoes'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        corretaIdx: ((json['correta_idx'] ?? 0) as num).toInt(),
        origem: (json['origem'] as String?) ?? 'manual',
        ativa: (json['ativa'] as bool?) ?? true,
      );
}

/// Linha da view `avaliacao_resumo` (prova respondida por um candidato).
class AvaliacaoResumo {
  final String id;
  final String candidatoId;
  final String candidatoNome;
  final String? vagaTitulo;
  final String? nivel;
  final int totalQuestoes;
  final int? acertos;
  final int? nota;
  final String status; // iniciada | finalizada | expirada
  final DateTime? finalizadaEm;

  const AvaliacaoResumo({
    required this.id,
    required this.candidatoId,
    required this.candidatoNome,
    this.vagaTitulo,
    this.nivel,
    this.totalQuestoes = 0,
    this.acertos,
    this.nota,
    this.status = 'iniciada',
    this.finalizadaEm,
  });

  factory AvaliacaoResumo.fromJson(Map<String, dynamic> json) => AvaliacaoResumo(
        id: json['id'] as String,
        candidatoId: json['candidato_id'] as String,
        candidatoNome: (json['candidato_nome'] as String?) ?? '',
        vagaTitulo: json['vaga_titulo'] as String?,
        nivel: json['nivel'] as String?,
        totalQuestoes: ((json['total_questoes'] ?? 0) as num).toInt(),
        acertos: (json['acertos'] as num?)?.toInt(),
        nota: (json['nota'] as num?)?.toInt(),
        status: (json['status'] as String?) ?? 'iniciada',
        finalizadaEm: json['finalizada_em'] != null
            ? DateTime.tryParse(json['finalizada_em'] as String)
            : null,
      );
}

/// RH-23 — configuração da prova por organização.
/// [minutos] zero significa prova sem limite de tempo.
class AvaliacaoConfig {
  final int qtd;
  final int minutos;

  const AvaliacaoConfig({required this.qtd, required this.minutos});

  bool get temTempo => minutos > 0;

  AvaliacaoConfig copyWith({int? qtd, int? minutos}) => AvaliacaoConfig(
        qtd: qtd ?? this.qtd,
        minutos: minutos ?? this.minutos,
      );
}
