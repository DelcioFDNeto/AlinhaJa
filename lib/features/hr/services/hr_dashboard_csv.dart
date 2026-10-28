/// RH-15 / Fase 6 — export CSV do dashboard de RH.
/// Gera um relatório em seções a partir dos dados já carregados
/// pelos providers (nenhuma consulta extra). Separador `;` e BOM
/// UTF-8 para abrir direto no Excel pt-BR.
library;

import 'package:alinha_ja/features/hr/models/employee_model.dart';
import 'package:alinha_ja/features/hr/models/pipeline_etapa_model.dart';
import 'package:alinha_ja/features/hr/services/hr_analytics_service.dart';

class HrDashboardCsv {
  HrDashboardCsv._();

  static String _cell(Object? v) {
    final s = (v ?? '').toString();
    return s.contains(RegExp(r'[;"\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  static String _row(List<Object?> cells) => cells.map(_cell).join(';');

  /// Monta o CSV completo do dashboard. Mapas/listas vazios geram
  /// seções vazias (o arquivo sai mesmo assim).
  static String build({
    required DateTime geradoEm,
    required PipelineConfig pipeline,
    required Map<String, int> statusCounts,
    required Map<String, int> fonte,
    required Map<String, int> nivel,
    required Map<String, int> area,
    required TempoPipeline? tempoPipeline,
    required List<MovimentacaoMes> movimentacao,
    required Map<String, int> headcount,
    required TempoCasa? tempoCasa,
  }) {
    // BOM UTF-8 explícito — sem ele o Excel pt-BR lê mojibake.
    final b = StringBuffer(String.fromCharCode(0xFEFF));
    void section(String titulo, List<List<Object?>> rows) {
      b.writeln(_row([titulo]));
      for (final r in rows) {
        b.writeln(_row(r));
      }
      b.writeln();
    }

    final dt = geradoEm;
    final stamp = '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    b.writeln(_row(['Dashboard de RH', 'Gerado em', stamp]));
    b.writeln();

    final total = statusCounts.values.fold<int>(0, (a, v) => a + v);
    final contratado = statusCounts[pipeline.contratado.slug] ?? 0;
    final descartado = statusCounts[pipeline.descartado.slug] ?? 0;
    section('Resumo de recrutamento', [
      ['Candidatos', total],
      ['Em processo', total - contratado - descartado],
      ['Contratados', contratado],
      ['Descartados', descartado],
      ['Conversão (%)', total > 0 ? ((contratado * 100) / total).round() : 0],
      if (tempoPipeline?.diasAteContratacao != null)
        ['Tempo médio até contratação (dias)', tempoPipeline!.diasAteContratacao],
      if (tempoPipeline?.diasEmProcesso != null)
        ['Tempo médio em processo (dias)', tempoPipeline!.diasEmProcesso],
      if (tempoPipeline != null) ...[
        ['Contratações (30 dias)', tempoPipeline.contratacoes30d],
        ['Contratações (90 dias)', tempoPipeline.contratacoes90d],
      ],
    ]);

    section('Funil por etapa', [
      ['Etapa', 'Candidatos'],
      for (final e in pipeline.etapas) [e.nome, statusCounts[e.slug] ?? 0],
    ]);

    List<List<Object?>> dist(Map<String, int> data,
        [Map<String, String> labels = const {}]) {
      final entries = data.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [
        ['Categoria', 'Candidatos'],
        for (final e in entries) [labels[e.key] ?? e.key, e.value],
      ];
    }

    section('Candidatos por fonte', dist(fonte, const {
      'portal': 'Portal',
      'indicacao': 'Indicação',
      'upload_manual': 'Cadastro manual',
      'outros': 'Outros',
    }));
    section('Candidatos por nível', dist(nivel, const {
      'estagio': 'Estágio',
      'junior': 'Júnior',
      'pleno': 'Pleno',
      'senior': 'Sênior',
      'lideranca': 'Liderança',
      'nao_informado': 'Não informado',
    }));
    section('Candidatos por área', dist(area));

    final ativos = headcount['ativo'] ?? 0;
    final desligados12m =
        movimentacao.fold<int>(0, (a, m) => a + m.desligamentos);
    section('Gestão de pessoas', [
      for (final e in headcount.entries)
        ['Funcionários — ${EmployeeStatus.label(e.key)}', e.value],
      [
        'Turnover 12m (%)',
        ativos > 0 ? ((desligados12m * 100) / ativos).round() : 0
      ],
      if (tempoCasa?.mediaMeses != null)
        ['Tempo médio de casa (meses)', tempoCasa!.mediaMeses],
    ]);

    section('Movimentação de pessoal (12 meses)', [
      ['Mês', 'Admissões', 'Desligamentos'],
      for (final m in movimentacao)
        [
          '${m.mes.month.toString().padLeft(2, '0')}/${m.mes.year}',
          m.admissoes,
          m.desligamentos,
        ],
    ]);

    return b.toString();
  }
}
