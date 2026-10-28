import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/hr/models/candidate_model.dart';

/// RH-11 / Fase 6 — leitura das views agregadas do dashboard.
/// Todas com `security_invoker`: a RLS por org já filtra os dados.
class HrAnalyticsService {
  const HrAnalyticsService();

  /// Distribuição de candidatos por fonte (portal, indicação, upload…).
  Future<Map<String, int>> fetchDistribuicaoFonte() async {
    final data = await supabase
        .from('rh_dash_candidato_fonte')
        .select('fonte, total');
    return {
      for (final row in data as List)
        row['fonte'] as String: (row['total'] as num).toInt(),
    };
  }

  /// Distribuição de candidatos por nível.
  Future<Map<String, int>> fetchDistribuicaoNivel() async {
    final data = await supabase
        .from('rh_dash_candidato_nivel')
        .select('nivel, total');
    return {
      for (final row in data as List)
        row['nivel'] as String: (row['total'] as num).toInt(),
    };
  }

  /// Movimentação de pessoal por mês (admissões x desligamentos),
  /// ordenada do mês mais antigo ao mais recente.
  Future<List<MovimentacaoMes>> fetchMovimentacaoMes() async {
    final data = await supabase
        .from('rh_dash_movimentacao_mes')
        .select('mes, admissoes, desligamentos')
        .order('mes');
    return (data as List)
        .map((e) => MovimentacaoMes.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Top talentos por score de completude (candidatos vivos, em processo).
  Future<List<CandidateModel>> fetchTopTalentos({int limit = 5}) async {
    final data = await supabase
        .from('candidato')
        .select()
        .not('score_completude', 'is', null)
        .order('score_completude', ascending: false)
        .limit(limit);
    return (data as List)
        .map((e) => CandidateModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Distribuição de candidatos por área (catálogo RH-9 + texto livre).
  Future<Map<String, int>> fetchDistribuicaoArea() async {
    final data =
        await supabase.from('rh_dash_candidato_area').select('area, total');
    return {
      for (final row in data as List)
        row['area'] as String: (row['total'] as num).toInt(),
    };
  }

  /// Tempo médio no pipeline e contratações no período (1 linha por org).
  Future<TempoPipeline?> fetchTempoPipeline() async {
    final data = await supabase
        .from('rh_dash_tempo_pipeline')
        .select()
        .maybeSingle();
    return data == null ? null : TempoPipeline.fromJson(data);
  }

  /// Headcount por status (view funcionario_contagem_status — RH-4.1).
  Future<Map<String, int>> fetchHeadcountStatus() async {
    final data = await supabase
        .from('funcionario_contagem_status')
        .select('status, total');
    return {
      for (final row in data as List)
        row['status'] as String: (row['total'] as num).toInt(),
    };
  }

  /// Tempo médio de casa dos funcionários ativos (1 linha por org).
  Future<TempoCasa?> fetchTempoCasa() async {
    final data =
        await supabase.from('rh_dash_tempo_casa').select().maybeSingle();
    return data == null ? null : TempoCasa.fromJson(data);
  }

  /// Aniversariantes (nascimento) do mês corrente — RPC restrita ao RH,
  /// expõe apenas o dia (sem ano/idade).
  Future<List<Aniversariante>> fetchAniversariantes() async {
    final data = await supabase.rpc('rh_dash_aniversariantes');
    return [
      for (final row in data as List)
        Aniversariante.fromJson(row as Map<String, dynamic>),
    ];
  }

  /// Aniversários de empresa (tempo de casa) do mês corrente.
  Future<List<Aniversariante>> fetchAniversariantesCasa() async {
    final data = await supabase
        .from('rh_dash_aniversariantes_casa')
        .select('funcionario_id, nome, foto_url, dia, anos')
        .order('dia');
    return [
      for (final row in data as List)
        Aniversariante.fromJson(row as Map<String, dynamic>),
    ];
  }
}

/// Linha da view `rh_dash_tempo_pipeline`.
class TempoPipeline {
  final int? diasAteContratacao;
  final int? diasEmProcesso;
  final int contratacoes30d;
  final int contratacoes90d;

  const TempoPipeline({
    this.diasAteContratacao,
    this.diasEmProcesso,
    required this.contratacoes30d,
    required this.contratacoes90d,
  });

  factory TempoPipeline.fromJson(Map<String, dynamic> json) => TempoPipeline(
        diasAteContratacao: (json['dias_ate_contratacao'] as num?)?.toInt(),
        diasEmProcesso: (json['dias_em_processo'] as num?)?.toInt(),
        contratacoes30d: ((json['contratacoes_30d'] ?? 0) as num).toInt(),
        contratacoes90d: ((json['contratacoes_90d'] ?? 0) as num).toInt(),
      );
}

/// Linha da view `rh_dash_tempo_casa`.
class TempoCasa {
  final int comVinculo;
  final int? mediaMeses;

  const TempoCasa({required this.comVinculo, this.mediaMeses});

  factory TempoCasa.fromJson(Map<String, dynamic> json) => TempoCasa(
        comVinculo: ((json['com_vinculo'] ?? 0) as num).toInt(),
        mediaMeses: (json['media_meses'] as num?)?.toInt(),
      );
}

/// Aniversariante do mês — nascimento (anos == null) ou de empresa.
class Aniversariante {
  final String funcionarioId;
  final String nome;
  final String? fotoUrl;
  final int dia;

  /// Anos de casa (apenas aniversário de empresa; nascimento não expõe idade).
  final int? anos;

  const Aniversariante({
    required this.funcionarioId,
    required this.nome,
    this.fotoUrl,
    required this.dia,
    this.anos,
  });

  factory Aniversariante.fromJson(Map<String, dynamic> json) => Aniversariante(
        funcionarioId: (json['funcionario_id'] as String?) ?? '',
        nome: (json['nome'] as String?) ?? '',
        fotoUrl: json['foto_url'] as String?,
        dia: ((json['dia'] ?? 0) as num).toInt(),
        anos: (json['anos'] as num?)?.toInt(),
      );

  String get initials {
    final parts = nome.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}

/// Linha da view `rh_dash_movimentacao_mes`.
class MovimentacaoMes {
  final DateTime mes;
  final int admissoes;
  final int desligamentos;

  const MovimentacaoMes({
    required this.mes,
    required this.admissoes,
    required this.desligamentos,
  });

  factory MovimentacaoMes.fromJson(Map<String, dynamic> json) => MovimentacaoMes(
        mes: DateTime.parse(json['mes'] as String),
        admissoes: ((json['admissoes'] ?? 0) as num).toInt(),
        desligamentos: ((json['desligamentos'] ?? 0) as num).toInt(),
      );
}
