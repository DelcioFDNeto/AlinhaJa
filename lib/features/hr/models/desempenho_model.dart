/// RH-27 — rótulos das origens de feedback do 360.
class Origem360 {
  Origem360._();
  static const labels = {
    'auto': 'Autoavaliação',
    'gestor': 'Gestor',
    'par': 'Par',
    'subordinado': 'Subordinado',
  };
  static String label(String s) => labels[s] ?? s;
}

/// RH-27 — ciclo de avaliação (`rh_ciclo_avaliacao`).
class CicloAvaliacao {
  final String id;
  final String nome;
  final String? descricao;
  final DateTime periodoInicio;
  final DateTime periodoFim;
  final DateTime? prazoResposta;
  final String status; // rascunho | aberto | encerrado
  final bool usaAuto;
  final bool usaGestor;
  final bool usaPares;
  final bool usaSubordinado;
  final int minParesAnonimato;

  const CicloAvaliacao({
    required this.id,
    required this.nome,
    this.descricao,
    required this.periodoInicio,
    required this.periodoFim,
    this.prazoResposta,
    required this.status,
    this.usaAuto = true,
    this.usaGestor = true,
    this.usaPares = true,
    this.usaSubordinado = false,
    this.minParesAnonimato = 3,
  });

  bool get aberto => status == 'aberto';
  bool get encerrado => status == 'encerrado';
  bool get rascunho => status == 'rascunho';

  /// Origens habilitadas neste ciclo, na ordem de exibição.
  List<String> get origens => [
        if (usaAuto) 'auto',
        if (usaGestor) 'gestor',
        if (usaPares) 'par',
        if (usaSubordinado) 'subordinado',
      ];

  factory CicloAvaliacao.fromMap(Map<String, dynamic> m) => CicloAvaliacao(
        id: m['id'] as String,
        nome: (m['nome'] as String?) ?? '',
        descricao: m['descricao'] as String?,
        periodoInicio: DateTime.parse(m['periodo_inicio'] as String),
        periodoFim: DateTime.parse(m['periodo_fim'] as String),
        prazoResposta: m['prazo_resposta'] != null
            ? DateTime.parse(m['prazo_resposta'] as String)
            : null,
        status: (m['status'] as String?) ?? 'rascunho',
        usaAuto: m['usa_auto'] != false,
        usaGestor: m['usa_gestor'] != false,
        usaPares: m['usa_pares'] != false,
        usaSubordinado: m['usa_subordinado'] == true,
        minParesAnonimato: ((m['min_pares_anonimato'] ?? 3) as num).toInt(),
      );
}

/// RH-27 — meta de um funcionário no ciclo (`rh_meta`).
class MetaModel {
  final String id;
  final String cicloId;
  final String funcionarioId;
  final String? funcionarioNome;
  final String titulo;
  final String? descricao;
  final String? metrica;
  final String? alvo;
  final String? resultado;
  final int peso;
  final int progresso;
  final String status;
  final DateTime? prazo;

  const MetaModel({
    required this.id,
    required this.cicloId,
    required this.funcionarioId,
    this.funcionarioNome,
    required this.titulo,
    this.descricao,
    this.metrica,
    this.alvo,
    this.resultado,
    this.peso = 1,
    this.progresso = 0,
    this.status = 'em_andamento',
    this.prazo,
  });

  bool get atingida => status == 'atingida';
  bool get cancelada => status == 'cancelada';

  bool get atrasada =>
      status == 'em_andamento' &&
      prazo != null &&
      prazo!.isBefore(DateTime.now());

  factory MetaModel.fromMap(Map<String, dynamic> m) => MetaModel(
        id: m['id'] as String,
        cicloId: m['ciclo_id'] as String,
        funcionarioId: m['funcionario_id'] as String,
        funcionarioNome: m['funcionario']?['nome'] as String?,
        titulo: (m['titulo'] as String?) ?? '',
        descricao: m['descricao'] as String?,
        metrica: m['metrica'] as String?,
        alvo: m['alvo'] as String?,
        resultado: m['resultado'] as String?,
        peso: ((m['peso'] ?? 1) as num).toInt(),
        progresso: ((m['progresso'] ?? 0) as num).toInt(),
        status: (m['status'] as String?) ?? 'em_andamento',
        prazo: m['prazo'] != null ? DateTime.parse(m['prazo'] as String) : null,
      );
}

/// RH-27 — convite de 360 na visão de quem avalia
/// (`rh_minhas_avaliacoes_360`).
class Convite360 {
  final String id;
  final String cicloId;
  final String cicloNome;
  final String cicloStatus;
  final DateTime? prazoResposta;
  final String avaliadoId;
  final String avaliadoNome;
  final String origem;
  final String status;
  final int? nota;
  final DateTime? respondidaEm;

  const Convite360({
    required this.id,
    required this.cicloId,
    required this.cicloNome,
    required this.cicloStatus,
    this.prazoResposta,
    required this.avaliadoId,
    required this.avaliadoNome,
    required this.origem,
    required this.status,
    this.nota,
    this.respondidaEm,
  });

  bool get pendente => status == 'pendente';
  bool get podeResponder => pendente && cicloStatus == 'aberto';
  bool get autoavaliacao => origem == 'auto';

  factory Convite360.fromMap(Map<String, dynamic> m) => Convite360(
        id: m['id'] as String,
        cicloId: m['ciclo_id'] as String,
        cicloNome: (m['ciclo_nome'] as String?) ?? '',
        cicloStatus: (m['ciclo_status'] as String?) ?? 'rascunho',
        prazoResposta: m['prazo_resposta'] != null
            ? DateTime.parse(m['prazo_resposta'] as String)
            : null,
        avaliadoId: m['avaliado_id'] as String,
        avaliadoNome: (m['avaliado_nome'] as String?) ?? '',
        origem: (m['origem'] as String?) ?? 'par',
        status: (m['status'] as String?) ?? 'pendente',
        nota: (m['nota'] as num?)?.toInt(),
        respondidaEm: m['respondida_em'] != null
            ? DateTime.parse(m['respondida_em'] as String)
            : null,
      );
}

/// RH-27 — consolidado por avaliado (`rh_desempenho_consolidado`, RH).
class DesempenhoConsolidado {
  final String cicloId;
  final String avaliadoId;
  final String avaliadoNome;
  final int convites;
  final int respondidas;
  final double? notaGeral;
  final double? notaAuto;
  final double? notaGestor;
  final double? notaPares;
  final double? notaSubordinados;
  final double? progressoMetas;

  const DesempenhoConsolidado({
    required this.cicloId,
    required this.avaliadoId,
    required this.avaliadoNome,
    this.convites = 0,
    this.respondidas = 0,
    this.notaGeral,
    this.notaAuto,
    this.notaGestor,
    this.notaPares,
    this.notaSubordinados,
    this.progressoMetas,
  });

  double get taxaResposta => convites == 0 ? 0 : respondidas / convites;

  factory DesempenhoConsolidado.fromMap(Map<String, dynamic> m) =>
      DesempenhoConsolidado(
        cicloId: m['ciclo_id'] as String,
        avaliadoId: m['avaliado_id'] as String,
        avaliadoNome: (m['avaliado_nome'] as String?) ?? '',
        convites: ((m['convites'] ?? 0) as num).toInt(),
        respondidas: ((m['respondidas'] ?? 0) as num).toInt(),
        notaGeral: (m['nota_geral'] as num?)?.toDouble(),
        notaAuto: (m['nota_auto'] as num?)?.toDouble(),
        notaGestor: (m['nota_gestor'] as num?)?.toDouble(),
        notaPares: (m['nota_pares'] as num?)?.toDouble(),
        notaSubordinados: (m['nota_subordinados'] as num?)?.toDouble(),
        progressoMetas: (m['progresso_metas'] as num?)?.toDouble(),
      );
}

/// RH-27 — resultado que o próprio avaliado enxerga, já anonimizado
/// (`rh_meu_resultado_360`).
class MeuResultado360 {
  final int respondidas;
  final double? notaGeral;
  final double? notaAuto;
  final double? notaGestor;

  /// `null` enquanto o mínimo de pares não for atingido.
  final double? notaPares;
  final int paresRespondidas;

  /// Já há respostas de pares suficientes para revelar a média.
  final bool paresAnonimatoOk;
  final double? progressoMetas;

  const MeuResultado360({
    this.respondidas = 0,
    this.notaGeral,
    this.notaAuto,
    this.notaGestor,
    this.notaPares,
    this.paresRespondidas = 0,
    this.paresAnonimatoOk = false,
    this.progressoMetas,
  });

  factory MeuResultado360.fromMap(Map<String, dynamic> m) => MeuResultado360(
        respondidas: ((m['respondidas'] ?? 0) as num).toInt(),
        notaGeral: (m['nota_geral'] as num?)?.toDouble(),
        notaAuto: (m['nota_auto'] as num?)?.toDouble(),
        notaGestor: (m['nota_gestor'] as num?)?.toDouble(),
        notaPares: (m['nota_pares'] as num?)?.toDouble(),
        paresRespondidas: ((m['pares_respondidas'] ?? 0) as num).toInt(),
        paresAnonimatoOk: m['pares_anonimato_ok'] == true,
        progressoMetas: (m['progresso_metas'] as num?)?.toDouble(),
      );
}

/// Fase 8 — Avaliação de desempenho (rh_avaliacao_desempenho).
class AvaliacaoDesempenhoModel {
  final String id;
  final String organizationId;
  final String funcionarioId;
  final String? funcionarioNome;
  final String? avaliadorId;
  final String tipo; // 1:1, Experiência 45d, Anual, etc
  final DateTime dataAvaliacao;
  final double? pontuacaoGeral; // 0–100
  final String? feedbackTexto;
  final DateTime createdAt;

  const AvaliacaoDesempenhoModel({
    required this.id,
    required this.organizationId,
    required this.funcionarioId,
    this.funcionarioNome,
    this.avaliadorId,
    required this.tipo,
    required this.dataAvaliacao,
    this.pontuacaoGeral,
    this.feedbackTexto,
    required this.createdAt,
  });

  factory AvaliacaoDesempenhoModel.fromMap(Map<String, dynamic> map) =>
      AvaliacaoDesempenhoModel(
        id: map['id'] as String,
        organizationId: map['organization_id'] as String,
        funcionarioId: map['funcionario_id'] as String,
        funcionarioNome: map['funcionario']?['nome'] as String?,
        avaliadorId: map['avaliador_id'] as String?,
        tipo: map['tipo'] as String? ?? '',
        dataAvaliacao: DateTime.parse(map['data_avaliacao'] as String),
        pontuacaoGeral: (map['pontuacao_geral'] as num?)?.toDouble(),
        feedbackTexto: map['feedback_texto'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
