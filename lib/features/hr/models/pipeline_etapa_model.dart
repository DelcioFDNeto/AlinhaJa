/// RH-14 / Fase 5 — Etapas customizáveis do pipeline por organização.
/// Espelha a tabela `pipeline_etapa`; quando a org não tem etapas no
/// banco, `PipelineConfig.padrao()` reproduz o funil fixo original
/// (CandidateStatus), então nenhuma tela precisa tratar os dois casos.
library;

import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/features/hr/models/candidate_model.dart';

class PipelineEtapa {
  final String id;
  final String slug;
  final String nome;
  final int ordem;
  final String roleCor;

  /// 'entrada' | 'normal' | 'contratado' | 'descartado'.
  /// Os três reservados existem sempre (slug imutável no banco).
  final String tipo;

  const PipelineEtapa({
    required this.id,
    required this.slug,
    required this.nome,
    required this.ordem,
    required this.roleCor,
    required this.tipo,
  });

  factory PipelineEtapa.fromJson(Map<String, dynamic> json) => PipelineEtapa(
        id: (json['id'] as String?) ?? '',
        slug: (json['slug'] as String?) ?? '',
        nome: (json['nome'] as String?) ?? '',
        ordem: (json['ordem'] as num?)?.toInt() ?? 0,
        roleCor: (json['role_cor'] as String?) ?? 'info',
        tipo: (json['tipo'] as String?) ?? 'normal',
      );

  StatusRole get role => StatusRole.values.firstWhere(
        (r) => r.name == roleCor,
        orElse: () => StatusRole.neutral,
      );

  bool get isEntrada => tipo == 'entrada';
  bool get isNormal => tipo == 'normal';
  bool get isContratado => tipo == 'contratado';
  bool get isDescartado => tipo == 'descartado';
}

/// Funil da organização (ordenado por `ordem`), com os mesmos helpers
/// que as telas usavam em `CandidateStatus` — agora dirigidos por dados.
class PipelineConfig {
  /// Todas as etapas, ordenadas (descartado por último, ordem 99).
  final List<PipelineEtapa> etapas;

  /// true quando as etapas vieram do banco (org já semeada).
  final bool customizada;

  const PipelineConfig._(this.etapas, this.customizada);

  /// Fallback: reproduz o funil fixo original (ids vazios — só leitura).
  factory PipelineConfig.padrao() {
    const tipos = {
      CandidateStatus.novo: 'entrada',
      CandidateStatus.contratado: 'contratado',
      CandidateStatus.descartado: 'descartado',
    };
    final slugs = [...CandidateStatus.funil, CandidateStatus.descartado];
    return PipelineConfig._([
      for (var i = 0; i < slugs.length; i++)
        PipelineEtapa(
          id: '',
          slug: slugs[i],
          nome: CandidateStatus.label(slugs[i]),
          ordem: slugs[i] == CandidateStatus.descartado ? 99 : i + 1,
          roleCor: CandidateStatus.role(slugs[i]).name,
          tipo: tipos[slugs[i]] ?? 'normal',
        ),
    ], false);
  }

  /// Constrói a partir das linhas do banco; vazio cai no padrão.
  factory PipelineConfig.fromRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return PipelineConfig.padrao();
    final list = rows.map(PipelineEtapa.fromJson).toList()
      ..sort((a, b) => a.ordem.compareTo(b.ordem));
    return PipelineConfig._(list, true);
  }

  /// Etapas do funil (sem o descarte), na ordem — inclui contratado.
  List<PipelineEtapa> get funil =>
      etapas.where((e) => !e.isDescartado).toList();

  List<String> get funilSlugs => [for (final e in funil) e.slug];

  PipelineEtapa get entrada => etapas.firstWhere((e) => e.isEntrada,
      orElse: () => etapas.first);
  PipelineEtapa get contratado => etapas.firstWhere((e) => e.isContratado,
      orElse: () => funil.last);
  PipelineEtapa get descartado => etapas.firstWhere((e) => e.isDescartado,
      orElse: () => etapas.last);

  PipelineEtapa? bySlug(String slug) {
    for (final e in etapas) {
      if (e.slug == slug) return e;
    }
    return null;
  }

  /// Nome exibível da etapa; slugs desconhecidos caem nos labels fixos.
  String label(String slug) => bySlug(slug)?.nome ?? CandidateStatus.label(slug);

  StatusRole role(String slug) =>
      bySlug(slug)?.role ?? CandidateStatus.role(slug);

  /// Próximas etapas permitidas a partir de [atual] (espelha o guard
  /// data-driven fn_candidato_status_guard do banco).
  List<String> transicoesDe(String atual) {
    if (atual == contratado.slug) return const [];
    if (atual == descartado.slug) return [entrada.slug];
    final i = funilSlugs.indexOf(atual);
    // Etapa desconhecida (ex.: recém-excluída): oferece tudo e o banco valida.
    if (i < 0) return [...funilSlugs, descartado.slug];
    return [...funilSlugs.sublist(i + 1), descartado.slug];
  }

  /// Gate do botão "Contratar": última etapa antes de contratado
  /// (no funil padrão, "Aprovado").
  bool prontoParaContratar(String slug) {
    final i = funilSlugs.indexOf(slug);
    return i >= 0 && i == funilSlugs.length - 2;
  }

  /// Candidato ainda no processo (nem contratado, nem descartado).
  bool emProcesso(String slug) =>
      slug != contratado.slug && slug != descartado.slug;
}
