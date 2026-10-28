/// Models do Módulo RH — Banco de Talentos.
/// Espelham as tabelas `candidato*` do Supabase (migration 20260708160000).
library;

import 'package:alinha_ja/core/status_role.dart';

/// Status do funil de contratação (enum `candidato_status` no banco).
/// A ordem importa: o banco bloqueia transições retroativas.
class CandidateStatus {
  CandidateStatus._();

  static const novo = 'novo';
  static const emAnalise = 'em_analise';
  static const entrevista = 'entrevista';
  static const aprovado = 'aprovado';
  static const contratado = 'contratado';
  static const descartado = 'descartado';

  /// Ordem do funil (sem o terminal descartado).
  static const funil = [novo, emAnalise, entrevista, aprovado, contratado];

  static const labels = {
    novo: 'Novo',
    emAnalise: 'Em análise',
    entrevista: 'Entrevista',
    aprovado: 'Aprovado',
    contratado: 'Contratado',
    descartado: 'Descartado',
  };

  static String label(String status) => labels[status] ?? status;

  /// Papel semântico por status — a cor é resolvida no tema (white-label).
  static const roles = {
    novo: StatusRole.info,
    emAnalise: StatusRole.warning,
    entrevista: StatusRole.highlight,
    aprovado: StatusRole.progress,
    contratado: StatusRole.success,
    descartado: StatusRole.neutral,
  };

  static StatusRole role(String status) => roles[status] ?? StatusRole.neutral;

  /// Próximos status permitidos a partir de [atual] (espelha o trigger
  /// fn_candidato_status_guard do banco).
  static List<String> transicoesDe(String atual) {
    if (atual == contratado) return const [];
    if (atual == descartado) return const [novo];
    final i = funil.indexOf(atual);
    return [...funil.sublist(i + 1), descartado];
  }
}

/// Fonte de entrada do candidato (enum `candidato_fonte`).
class CandidateSource {
  CandidateSource._();

  static const labels = {
    'portal': 'Portal de carreiras',
    'upload_manual': 'Upload manual',
    'indicacao': 'Indicação',
  };

  static String label(String fonte) => labels[fonte] ?? fonte;
}

class CandidateModel {
  final String id;
  final String nome;
  final String email;
  final String? telefone;
  final String? cidade;
  final String? estado;
  final String? areaInteresse;
  final String? cargoPretendido;
  final String? nivel;
  final String? disponibilidade;
  final double? pretensaoSalarial;
  final String? fotoUrl;
  final String status;
  final String fonte;
  final String extracao;
  final int? scoreCompletude;
  final String? resumoExecutivo;
  final DateTime createdAt;

  /// Vaga vinculada (RH-10) — null em candidatura espontânea.
  final String? vagaId;

  /// Título da vaga quando a query traz o join `vaga:vaga_id(titulo)`.
  final String? vagaTitulo;

  /// Responsável pelo candidato (RH-13) — FK users, null se sem dono.
  final String? responsavelId;

  /// Nome do responsável quando a query traz o join `responsavel(full_name)`.
  final String? responsavelNome;

  /// Momento da última mudança de etapa (RH-13) — base do SLA "parado há X".
  final DateTime? statusChangedAt;

  const CandidateModel({
    required this.id,
    required this.nome,
    required this.email,
    this.telefone,
    this.cidade,
    this.estado,
    this.areaInteresse,
    this.cargoPretendido,
    this.nivel,
    this.disponibilidade,
    this.pretensaoSalarial,
    this.fotoUrl,
    required this.status,
    required this.fonte,
    required this.extracao,
    this.scoreCompletude,
    this.resumoExecutivo,
    required this.createdAt,
    this.vagaId,
    this.vagaTitulo,
    this.responsavelId,
    this.responsavelNome,
    this.statusChangedAt,
  });

  factory CandidateModel.fromJson(Map<String, dynamic> json) => CandidateModel(
        id: json['id'] as String,
        nome: (json['nome'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        telefone: json['telefone'] as String?,
        cidade: json['cidade'] as String?,
        estado: json['estado'] as String?,
        areaInteresse: json['area_interesse'] as String?,
        cargoPretendido: json['cargo_pretendido'] as String?,
        nivel: json['nivel'] as String?,
        disponibilidade: json['disponibilidade'] as String?,
        pretensaoSalarial: (json['pretensao_salarial'] as num?)?.toDouble(),
        fotoUrl: json['foto_url'] as String?,
        status: (json['status'] as String?) ?? CandidateStatus.novo,
        fonte: (json['fonte'] as String?) ?? 'upload_manual',
        extracao: (json['extracao'] as String?) ?? 'pendente',
        scoreCompletude: json['score_completude'] as int?,
        resumoExecutivo: json['resumo_executivo'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        vagaId: json['vaga_id'] as String?,
        // Presente só quando a query pede o join (ficha do candidato).
        vagaTitulo: (json['vaga'] as Map<String, dynamic>?)?['titulo']
            as String?,
        responsavelId: json['responsavel_id'] as String?,
        responsavelNome: (json['responsavel'] as Map<String, dynamic>?)?[
            'full_name'] as String?,
        statusChangedAt: json['status_changed_at'] != null
            ? DateTime.tryParse(json['status_changed_at'] as String)
            : null,
      );

  String get initials => nome.isNotEmpty ? nome[0].toUpperCase() : '?';

  String get localidade => [cidade, estado]
      .where((e) => e != null && e.isNotEmpty)
      .join(' — ');

  /// Dias na etapa atual (SLA). Null se não houver carimbo.
  int? get diasNaEtapa => statusChangedAt == null
      ? null
      : DateTime.now().difference(statusChangedAt!).inDays;
}

class CandidateEducation {
  final String? instituicao;
  final String? curso;
  final String? grau;
  final int? anoInicio;
  final int? anoFim;

  const CandidateEducation(
      {this.instituicao, this.curso, this.grau, this.anoInicio, this.anoFim});

  factory CandidateEducation.fromJson(Map<String, dynamic> json) =>
      CandidateEducation(
        instituicao: json['instituicao'] as String?,
        curso: json['curso'] as String?,
        grau: json['grau'] as String?,
        anoInicio: json['ano_inicio'] as int?,
        anoFim: json['ano_fim'] as int?,
      );
}

class CandidateExperience {
  final String? empresa;
  final String? cargo;
  final String? descricao;
  final DateTime? dataInicio;
  final DateTime? dataFim;

  const CandidateExperience(
      {this.empresa, this.cargo, this.descricao, this.dataInicio, this.dataFim});

  factory CandidateExperience.fromJson(Map<String, dynamic> json) =>
      CandidateExperience(
        empresa: json['empresa'] as String?,
        cargo: json['cargo'] as String?,
        descricao: json['descricao'] as String?,
        dataInicio: json['data_inicio'] != null
            ? DateTime.tryParse(json['data_inicio'] as String)
            : null,
        dataFim: json['data_fim'] != null
            ? DateTime.tryParse(json['data_fim'] as String)
            : null,
      );
}

class CandidateSkill {
  final String nome;
  final String origem;

  const CandidateSkill({required this.nome, required this.origem});

  factory CandidateSkill.fromJson(Map<String, dynamic> json) => CandidateSkill(
        nome: (json['nome'] as String?) ?? '',
        origem: (json['origem'] as String?) ?? 'manual',
      );
}

class CandidateResume {
  final String id;
  final String arquivoUrl;
  final String tipoArquivo;
  final int tamanhoBytes;
  final DateTime createdAt;

  const CandidateResume({
    required this.id,
    required this.arquivoUrl,
    required this.tipoArquivo,
    required this.tamanhoBytes,
    required this.createdAt,
  });

  factory CandidateResume.fromJson(Map<String, dynamic> json) =>
      CandidateResume(
        id: json['id'] as String,
        arquivoUrl: (json['arquivo_url'] as String?) ?? '',
        tipoArquivo: (json['tipo_arquivo'] as String?) ?? 'pdf',
        tamanhoBytes: (json['tamanho_bytes'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class CandidateHistoryEntry {
  final String acao;
  final Map<String, dynamic> detalhes;
  final String? usuarioNome;
  final DateTime createdAt;

  const CandidateHistoryEntry({
    required this.acao,
    required this.detalhes,
    this.usuarioNome,
    required this.createdAt,
  });

  factory CandidateHistoryEntry.fromJson(Map<String, dynamic> json) =>
      CandidateHistoryEntry(
        acao: (json['acao'] as String?) ?? '',
        detalhes: (json['detalhes'] as Map<String, dynamic>?) ?? const {},
        usuarioNome:
            json['users'] is Map ? json['users']['full_name'] as String? : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  String get descricao {
    switch (acao) {
      case 'mudanca_status':
        final de = CandidateStatus.label((detalhes['de'] as String?) ?? '');
        final para = CandidateStatus.label((detalhes['para'] as String?) ?? '');
        return 'Status alterado de "$de" para "$para"';
      case 'comentario':
        return (detalhes['texto'] as String?) ?? 'Comentário';
      case 'cadastro':
        return 'Candidato cadastrado';
      default:
        return acao;
    }
  }
}

class CandidateEmailLog {
  final String id;
  final String tipo;
  final String? assunto;
  final String status;
  final String? erroDetalhe;
  final DateTime enviadoEm;

  const CandidateEmailLog({
    required this.id,
    required this.tipo,
    this.assunto,
    required this.status,
    this.erroDetalhe,
    required this.enviadoEm,
  });

  factory CandidateEmailLog.fromJson(Map<String, dynamic> json) {
    return CandidateEmailLog(
      id: json['id'] as String,
      tipo: json['tipo'] as String? ?? 'email',
      assunto: json['assunto'] as String?,
      status: json['status'] as String? ?? 'enviado',
      erroDetalhe: json['erro_detalhe'] as String?,
      enviadoEm: DateTime.parse(json['enviado_em'] as String),
    );
  }
}

/// Detalhe completo do candidato (ficha — RH-1.2).
class CandidateDetail {
  final CandidateModel candidato;
  final List<CandidateResume> curriculos;
  final List<CandidateEducation> formacoes;
  final List<CandidateExperience> experiencias;
  final List<CandidateSkill> habilidades;
  final List<CandidateHistoryEntry> historico;
  final List<CandidateEmailLog> emails;

  const CandidateDetail({
    required this.candidato,
    required this.curriculos,
    required this.formacoes,
    required this.experiencias,
    required this.habilidades,
    required this.historico,
    this.emails = const [],
  });
}
