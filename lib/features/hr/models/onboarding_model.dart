/// Models do RH-5 — Onboarding e Período de Experiência.
/// Espelham onboarding_template/_item, onboarding_execucao/_item,
/// periodo_experiencia e rh_alerta.
library;

class OnboardingStatus {
  OnboardingStatus._();
  static const labels = {
    'em_andamento': 'Em andamento',
    'concluido': 'Concluído',
    'cancelado': 'Cancelado',
  };
  static String label(String s) => labels[s] ?? s;
}

class OnboardingItemStatus {
  OnboardingItemStatus._();
  static const labels = {
    'pendente': 'Pendente',
    'concluido': 'Concluído',
    'nao_aplicavel': 'Não se aplica',
  };
  static String label(String s) => labels[s] ?? s;
}

class OnboardingCategoria {
  OnboardingCategoria._();
  static const labels = {
    'documentacao': 'Documentação',
    'equipamento': 'Equipamento',
    'acesso': 'Acessos',
    'treinamento': 'Treinamento',
    'integracao': 'Integração',
    'outro': 'Outro',
  };
  static String label(String s) => labels[s] ?? s;
  static List<String> get keys => labels.keys.toList();
}

class OnboardingResponsavel {
  OnboardingResponsavel._();
  static const labels = {
    'rh': 'RH',
    'gestor': 'Gestor',
    'funcionario': 'Funcionário',
  };
  static String label(String s) => labels[s] ?? s;
  static List<String> get keys => labels.keys.toList();
}

class ExperienciaFase {
  ExperienciaFase._();
  static const labels = {
    'primeiro_periodo': '1º período (até 45 dias)',
    'segundo_periodo': '2º período (prorrogado)',
    'concluido': 'Concluído',
  };
  static String label(String s) => labels[s] ?? s;
}

class ExperienciaResultado {
  ExperienciaResultado._();
  static const labels = {
    'em_andamento': 'Em andamento',
    'efetivado': 'Efetivado',
    'desligado': 'Desligado',
  };
  static String label(String s) => labels[s] ?? s;
}

/// Template de onboarding (cabeçalho).
class OnboardingTemplate {
  final String id;
  final String nome;
  final String? descricao;
  final bool ativo;
  final bool padrao;
  final int itensCount;

  const OnboardingTemplate({
    required this.id,
    required this.nome,
    this.descricao,
    this.ativo = true,
    this.padrao = false,
    this.itensCount = 0,
  });

  factory OnboardingTemplate.fromJson(Map<String, dynamic> json) =>
      OnboardingTemplate(
        id: json['id'] as String,
        nome: (json['nome'] as String?) ?? '',
        descricao: json['descricao'] as String?,
        ativo: (json['ativo'] as bool?) ?? true,
        padrao: (json['padrao'] as bool?) ?? false,
        itensCount: (json['itens_count'] as int?) ??
            (json['onboarding_template_item'] is List
                ? (json['onboarding_template_item'] as List).length
                : 0),
      );
}

/// Item de um template.
class OnboardingTemplateItem {
  final String? id;
  final int ordem;
  final String titulo;
  final String? descricao;
  final String categoria;
  final bool obrigatorio;
  final int? prazoDias;
  final String responsavel;

  const OnboardingTemplateItem({
    this.id,
    this.ordem = 0,
    required this.titulo,
    this.descricao,
    this.categoria = 'outro',
    this.obrigatorio = true,
    this.prazoDias,
    this.responsavel = 'rh',
  });

  factory OnboardingTemplateItem.fromJson(Map<String, dynamic> json) =>
      OnboardingTemplateItem(
        id: json['id'] as String?,
        ordem: (json['ordem'] as int?) ?? 0,
        titulo: (json['titulo'] as String?) ?? '',
        descricao: json['descricao'] as String?,
        categoria: (json['categoria'] as String?) ?? 'outro',
        obrigatorio: (json['obrigatorio'] as bool?) ?? true,
        prazoDias: json['prazo_dias'] as int?,
        responsavel: (json['responsavel'] as String?) ?? 'rh',
      );

  Map<String, dynamic> toInsert(String templateId, String orgId) => {
        'template_id': templateId,
        'organization_id': orgId,
        'ordem': ordem,
        'titulo': titulo,
        'descricao': descricao,
        'categoria': categoria,
        'obrigatorio': obrigatorio,
        'prazo_dias': prazoDias,
        'responsavel': responsavel,
      };
}

/// Execução de onboarding de um funcionário.
class OnboardingExecucao {
  final String id;
  final String funcionarioId;
  final String? templateNome;
  final String status;
  final int progresso;
  final DateTime? dataInicio;
  final DateTime? dataPrevista;
  final DateTime? dataConclusao;

  const OnboardingExecucao({
    required this.id,
    required this.funcionarioId,
    this.templateNome,
    required this.status,
    this.progresso = 0,
    this.dataInicio,
    this.dataPrevista,
    this.dataConclusao,
  });

  factory OnboardingExecucao.fromJson(Map<String, dynamic> json) =>
      OnboardingExecucao(
        id: json['id'] as String,
        funcionarioId: json['funcionario_id'] as String,
        templateNome: json['template_nome'] as String?,
        status: (json['status'] as String?) ?? 'em_andamento',
        progresso: (json['progresso'] as int?) ?? 0,
        dataInicio: _date(json['data_inicio']),
        dataPrevista: _date(json['data_prevista']),
        dataConclusao: _date(json['data_conclusao']),
      );

  bool get emAndamento => status == 'em_andamento';
}

/// Item do checklist de uma execução.
class OnboardingItem {
  final String id;
  final int ordem;
  final String titulo;
  final String? descricao;
  final String categoria;
  final bool obrigatorio;
  final String responsavel;
  final DateTime? prazo;
  final String status;
  final String? observacao;

  const OnboardingItem({
    required this.id,
    this.ordem = 0,
    required this.titulo,
    this.descricao,
    this.categoria = 'outro',
    this.obrigatorio = true,
    this.responsavel = 'rh',
    this.prazo,
    required this.status,
    this.observacao,
  });

  factory OnboardingItem.fromJson(Map<String, dynamic> json) => OnboardingItem(
        id: json['id'] as String,
        ordem: (json['ordem'] as int?) ?? 0,
        titulo: (json['titulo'] as String?) ?? '',
        descricao: json['descricao'] as String?,
        categoria: (json['categoria'] as String?) ?? 'outro',
        obrigatorio: (json['obrigatorio'] as bool?) ?? true,
        responsavel: (json['responsavel'] as String?) ?? 'rh',
        prazo: _date(json['prazo']),
        status: (json['status'] as String?) ?? 'pendente',
        observacao: json['observacao'] as String?,
      );

  bool get concluido => status != 'pendente';
  bool get atrasado =>
      status == 'pendente' &&
      prazo != null &&
      prazo!.isBefore(DateTime.now().subtract(const Duration(days: 1)));
}

/// Período de experiência (45+45).
class PeriodoExperiencia {
  final String id;
  final String funcionarioId;
  final DateTime dataInicio;
  final DateTime fimPrimeiro;
  final DateTime fimSegundo;
  final String fase;
  final String resultado;
  final String? observacao;

  const PeriodoExperiencia({
    required this.id,
    required this.funcionarioId,
    required this.dataInicio,
    required this.fimPrimeiro,
    required this.fimSegundo,
    required this.fase,
    required this.resultado,
    this.observacao,
  });

  factory PeriodoExperiencia.fromJson(Map<String, dynamic> json) =>
      PeriodoExperiencia(
        id: json['id'] as String,
        funcionarioId: json['funcionario_id'] as String,
        dataInicio: _date(json['data_inicio'])!,
        fimPrimeiro: _date(json['fim_primeiro'])!,
        fimSegundo: _date(json['fim_segundo'])!,
        fase: (json['fase'] as String?) ?? 'primeiro_periodo',
        resultado: (json['resultado'] as String?) ?? 'em_andamento',
        observacao: json['observacao'] as String?,
      );

  bool get emAndamento => resultado == 'em_andamento';

  /// Data-limite relevante conforme a fase atual.
  DateTime get limiteAtual =>
      fase == 'segundo_periodo' ? fimSegundo : fimPrimeiro;

  int get diasRestantes =>
      limiteAtual.difference(DateTime.now()).inDays;
}

/// Alerta do feed do RH (rh_alerta).
class RhAlerta {
  final String id;
  final String? funcionarioId;
  final String tipo;
  final String titulo;
  final String? mensagem;
  final String severidade;
  final bool lido;
  final DateTime createdAt;

  const RhAlerta({
    required this.id,
    this.funcionarioId,
    required this.tipo,
    required this.titulo,
    this.mensagem,
    this.severidade = 'info',
    this.lido = false,
    required this.createdAt,
  });

  factory RhAlerta.fromJson(Map<String, dynamic> json) => RhAlerta(
        id: json['id'] as String,
        funcionarioId: json['funcionario_id'] as String?,
        tipo: (json['tipo'] as String?) ?? '',
        titulo: (json['titulo'] as String?) ?? '',
        mensagem: json['mensagem'] as String?,
        severidade: (json['severidade'] as String?) ?? 'info',
        lido: (json['lido'] as bool?) ?? false,
        createdAt:
            _date(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  bool get isAlerta => severidade == 'alerta';
}

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString());
