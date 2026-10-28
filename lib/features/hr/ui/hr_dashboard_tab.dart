import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/core/web_download_helper.dart';
import 'package:alinha_ja/features/hr/models/employee_model.dart';
import 'package:alinha_ja/features/hr/models/pipeline_etapa_model.dart';
import 'package:alinha_ja/features/hr/providers/hr_analytics_provider.dart';
import 'package:alinha_ja/features/hr/providers/talent_bank_provider.dart';
import 'package:alinha_ja/features/hr/services/hr_analytics_service.dart';
import 'package:alinha_ja/features/hr/services/hr_dashboard_csv.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_stat_pill.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-11/RH-15 / Fase 6 — aba Visão Geral da Central de Recrutamento.
/// Dashboard de recrutamento (funil, conversão, tempo no pipeline,
/// distribuição por fonte/nível/área, top talentos) + gestão de
/// pessoas (headcount, turnover, movimentação, aniversariantes),
/// com export CSV do relatório.
class HrDashboardTab extends ConsumerWidget {
  const HrDashboardTab({super.key, this.onVerCandidato});

  /// Abre a ficha de um candidato (top talentos).
  final void Function(String candidatoId)? onVerCandidato;

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = HrDashboardCsv.build(
        geradoEm: DateTime.now(),
        pipeline: await ref.read(pipelineConfigProvider.future),
        statusCounts: await ref.read(talentStatusCountsProvider.future),
        fonte: await ref.read(distribuicaoFonteProvider.future),
        nivel: await ref.read(distribuicaoNivelProvider.future),
        area: await ref.read(distribuicaoAreaProvider.future),
        tempoPipeline: await ref.read(tempoPipelineProvider.future),
        movimentacao: await ref.read(movimentacaoMesProvider.future),
        headcount: await ref.read(headcountStatusProvider.future),
        tempoCasa: await ref.read(tempoCasaProvider.future),
      );
      final now = DateTime.now();
      final nome = 'dashboard-rh-${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}.csv';
      if (kIsWeb) {
        final uri =
            Uri.dataFromString(csv, mimeType: 'text/csv', encoding: utf8);
        triggerFileDownload(uri.toString(), nome);
        messenger.showSnackBar(
            SnackBar(content: Text('Relatório exportado: $nome')));
      } else {
        await Clipboard.setData(ClipboardData(text: csv));
        messenger.showSnackBar(const SnackBar(
            content: Text(
                'Relatório CSV copiado — cole em uma planilha para usar.')));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Não foi possível exportar: ${friendlyError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(talentStatusCountsProvider);
        ref.invalidate(distribuicaoFonteProvider);
        ref.invalidate(distribuicaoNivelProvider);
        ref.invalidate(distribuicaoAreaProvider);
        ref.invalidate(tempoPipelineProvider);
        ref.invalidate(movimentacaoMesProvider);
        ref.invalidate(headcountStatusProvider);
        ref.invalidate(tempoCasaProvider);
        ref.invalidate(aniversariantesProvider);
        ref.invalidate(aniversariantesCasaProvider);
        ref.invalidate(topTalentosProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => _exportCsv(context, ref),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Exportar CSV'),
            ),
          ),
          const SizedBox(height: 12),
          const _KpiRow(),
          const SizedBox(height: 20),
          const _Section(
              title: 'Funil de recrutamento', child: _FunnelChart()),
          const SizedBox(height: 20),
          const _Section(
              title: 'Candidatos por fonte', child: _FonteChart()),
          const SizedBox(height: 20),
          const _Section(
              title: 'Candidatos por nível', child: _NivelChart()),
          const SizedBox(height: 20),
          const _Section(
              title: 'Candidatos por área', child: _AreaChart()),
          const SizedBox(height: 20),
          const _Section(
              title: 'Gestão de pessoas', child: _GestaoPessoas()),
          const SizedBox(height: 20),
          const _Section(
              title: 'Movimentação de pessoal (12 meses)',
              child: _MovimentacaoChart()),
          const SizedBox(height: 20),
          const _Section(
              title: 'Aniversariantes do mês', child: _Aniversariantes()),
          const SizedBox(height: 20),
          _Section(
              title: 'Top talentos',
              child: _TopTalentos(onTap: onVerCandidato)),
        ],
      ),
    );
  }
}

/// KPIs derivados da contagem por status (reuso de candidato_contagem_status).
class _KpiRow extends ConsumerWidget {
  const _KpiRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.statusTokens;
    final counts =
        ref.watch(talentStatusCountsProvider).valueOrNull ?? const {};
    final pipe =
        ref.watch(pipelineConfigProvider).valueOrNull ?? PipelineConfig.padrao();
    final tempo = ref.watch(tempoPipelineProvider).valueOrNull;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final contratado = counts[pipe.contratado.slug] ?? 0;
    final descartado = counts[pipe.descartado.slug] ?? 0;
    final emProcesso = total - contratado - descartado;
    final conv = total > 0 ? ((contratado * 100) / total).round() : 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          HrStatPill(
              icon: Icons.groups,
              label: 'Candidatos',
              value: '$total',
              color: tokens.highlight),
          HrStatPill(
              icon: Icons.hourglass_bottom,
              label: 'Em processo',
              value: '$emProcesso',
              color: tokens.warning),
          HrStatPill(
              icon: Icons.verified,
              label: 'Contratados',
              value: '$contratado',
              color: tokens.success),
          HrStatPill(
              icon: Icons.trending_up,
              label: 'Conversão',
              value: '$conv%',
              color: tokens.progress),
          if (tempo?.diasAteContratacao != null)
            HrStatPill(
                icon: Icons.timer,
                label: 'Tempo até contratar',
                value: '${tempo!.diasAteContratacao}d',
                color: tokens.info),
          if (tempo != null)
            HrStatPill(
                icon: Icons.event_available,
                label: 'Contratações 30d',
                value: '${tempo.contratacoes30d}',
                color: tokens.success),
        ],
      ),
    );
  }
}

/// Funil por etapa como barras horizontais proporcionais (labels legíveis).
class _FunnelChart extends ConsumerWidget {
  const _FunnelChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.statusTokens;
    final counts =
        ref.watch(talentStatusCountsProvider).valueOrNull ?? const {};
    final pipe =
        ref.watch(pipelineConfigProvider).valueOrNull ?? PipelineConfig.padrao();
    final etapas = pipe.funil;
    final maxVal = etapas
        .map((e) => counts[e.slug] ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (maxVal == 0) return const _EmptyChart('Sem candidatos no funil ainda.');

    return Column(
      children: [
        for (final e in etapas)
          _HBar(
            label: e.nome,
            value: counts[e.slug] ?? 0,
            max: maxVal,
            color: tokens.color(e.role),
          ),
      ],
    );
  }
}

/// Distribuição por fonte — pizza (fl_chart).
class _FonteChart extends ConsumerWidget {
  const _FonteChart();

  static const _labels = {
    'portal': 'Portal',
    'indicacao': 'Indicação',
    'upload_manual': 'Cadastro manual',
    'outros': 'Outros',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final async = ref.watch(distribuicaoFonteProvider);

    return async.when(
      loading: () => const _ChartLoading(),
      error: (e, _) => _EmptyChart('Erro ao carregar.\n${friendlyError(e)}'),
      data: (data) {
        final entries = data.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        if (entries.isEmpty) {
          return const _EmptyChart(
            'Nenhuma origem de candidato registrada',
            icone: Icons.pie_chart_outline,
            dica: 'A origem (indicação, site, rede social) é escolhida no '
                'cadastro do candidato. Publique uma vaga ou cadastre '
                'candidatos no Banco de Talentos para este gráfico ganhar '
                'conteúdo.',
          );
        }
        final total = entries.fold<int>(0, (a, b) => a + b.value);
        final palette = [
          tokens.highlight,
          tokens.info,
          tokens.progress,
          tokens.warning,
          tokens.success,
          tokens.neutral,
        ];

        return Row(
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 34,
                  sections: [
                    for (var i = 0; i < entries.length; i++)
                      PieChartSectionData(
                        value: entries[i].value.toDouble(),
                        color: palette[i % palette.length],
                        title:
                            '${((entries[i].value * 100) / total).round()}%',
                        radius: 32,
                        titleStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < entries.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                                color: palette[i % palette.length],
                                borderRadius: BorderRadius.circular(3)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                _labels[entries[i].key] ?? entries[i].key,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text('${entries[i].value}',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Distribuição por nível — barras horizontais.
class _NivelChart extends ConsumerWidget {
  const _NivelChart();

  static const _labels = {
    'estagio': 'Estágio',
    'junior': 'Júnior',
    'pleno': 'Pleno',
    'senior': 'Sênior',
    'lideranca': 'Liderança',
    'nao_informado': 'Não informado',
  };
  static const _ordem = [
    'estagio',
    'junior',
    'pleno',
    'senior',
    'lideranca',
    'nao_informado'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.statusTokens;
    final async = ref.watch(distribuicaoNivelProvider);

    return async.when(
      loading: () => const _ChartLoading(),
      error: (e, _) => _EmptyChart('Erro ao carregar.\n${friendlyError(e)}'),
      data: (data) {
        final entries = [
          for (final k in _ordem)
            if ((data[k] ?? 0) > 0) MapEntry(k, data[k]!),
          for (final e in data.entries)
            if (!_ordem.contains(e.key) && e.value > 0) e,
        ];
        if (entries.isEmpty) {
          return const _EmptyChart(
            'Nenhum nível informado',
            icone: Icons.stairs_outlined,
            dica: 'O nível (júnior, pleno, sênior) vem do cargo. Cadastre os '
                'cargos no catálogo e ligue a ficha de cada pessoa ao cargo '
                'dela.',
          );
        }
        final maxVal =
            entries.map((e) => e.value).fold<int>(0, (a, b) => a > b ? a : b);
        return Column(
          children: [
            for (final e in entries)
              _HBar(
                label: _labels[e.key] ?? e.key,
                value: e.value,
                max: maxVal,
                color: tokens.info,
              ),
          ],
        );
      },
    );
  }
}

/// Distribuição por área (catálogo RH-9) — barras horizontais.
class _AreaChart extends ConsumerWidget {
  const _AreaChart();

  static const _maxLinhas = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.statusTokens;
    final async = ref.watch(distribuicaoAreaProvider);

    return async.when(
      loading: () => const _ChartLoading(),
      error: (e, _) => _EmptyChart('Erro ao carregar.\n${friendlyError(e)}'),
      data: (data) {
        final entries = data.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        if (entries.isEmpty) {
          return const _EmptyChart(
            'Nenhuma área informada',
            icone: Icons.category_outlined,
            dica: 'Cadastre as áreas no catálogo de RH e informe a área na '
                'ficha de cada funcionário — é dela que sai esta '
                'distribuição.',
          );
        }
        final visiveis = entries.take(_maxLinhas).toList();
        final resto = entries
            .skip(_maxLinhas)
            .fold<int>(0, (a, e) => a + e.value);
        final maxVal = visiveis.first.value;
        return Column(
          children: [
            for (final e in visiveis)
              _HBar(
                label: e.key,
                value: e.value,
                max: maxVal,
                color: tokens.progress,
              ),
            if (resto > 0)
              _HBar(
                label: 'Outras',
                value: resto,
                max: maxVal,
                color: tokens.neutral,
              ),
          ],
        );
      },
    );
  }
}

/// Headcount por status, turnover 12m e tempo médio de casa.
class _GestaoPessoas extends ConsumerWidget {
  const _GestaoPessoas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.statusTokens;
    final asyncHead = ref.watch(headcountStatusProvider);

    return asyncHead.when(
      loading: () => const _ChartLoading(),
      error: (e, _) => _EmptyChart('Erro ao carregar.\n${friendlyError(e)}'),
      data: (head) {
        final meses = ref.watch(movimentacaoMesProvider).valueOrNull ?? const [];
        final casa = ref.watch(tempoCasaProvider).valueOrNull;
        final ativos = head['ativo'] ?? 0;
        final desligados12m =
            meses.fold<int>(0, (a, m) => a + m.desligamentos);
        final turnover =
            ativos > 0 ? ((desligados12m * 100) / ativos).round() : 0;
        final headTotal = head.values.fold<int>(0, (a, b) => a + b);
        if (headTotal == 0) {
          return const _EmptyChart('Sem funcionários cadastrados ainda.');
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in const ['ativo', 'ferias', 'afastado'])
                if ((head[s] ?? 0) > 0)
                  HrStatPill(
                      icon: Icons.badge,
                      label: EmployeeStatus.label(s),
                      value: '${head[s]}',
                      color: tokens.color(EmployeeStatus.role(s))),
              HrStatPill(
                  icon: Icons.sync_alt,
                  label: 'Turnover 12m',
                  value: '$turnover%',
                  color: tokens.warning),
              if (casa?.mediaMeses != null)
                HrStatPill(
                    icon: Icons.home_work,
                    label: 'Tempo médio de casa',
                    value: _mesesLabel(casa!.mediaMeses!),
                    color: tokens.info),
            ],
          ),
        );
      },
    );
  }

  static String _mesesLabel(int meses) {
    if (meses < 12) return '$meses ${meses == 1 ? 'mês' : 'meses'}';
    final anos = meses ~/ 12;
    final resto = meses % 12;
    return resto == 0
        ? '$anos ${anos == 1 ? 'ano' : 'anos'}'
        : '${anos}a ${resto}m';
  }
}

/// Aniversariantes do mês — nascimento e aniversário de empresa.
class _Aniversariantes extends ConsumerWidget {
  const _Aniversariantes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nascimento = ref.watch(aniversariantesProvider);
    final empresa = ref.watch(aniversariantesCasaProvider);

    if (nascimento.isLoading || empresa.isLoading) {
      return const _ChartLoading();
    }
    final listaNasc = nascimento.valueOrNull ?? const <Aniversariante>[];
    final listaEmp = empresa.valueOrNull ?? const <Aniversariante>[];
    if (listaNasc.isEmpty && listaEmp.isEmpty) {
      return const _EmptyChart(
        'Nenhum aniversariante neste mês',
        icone: Icons.cake_outlined,
        dica: 'O bloco usa a data de nascimento e a data de admissão da '
            'ficha. Se o mês parece errado, confira se esses campos estão '
            'preenchidos nas fichas.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (listaNasc.isNotEmpty) ...[
          const _SubTitulo(icon: Icons.cake, label: 'Aniversários'),
          for (final a in listaNasc)
            _AniversarianteTile(a: a, detalhe: 'Dia ${a.dia}'),
        ],
        if (listaNasc.isNotEmpty && listaEmp.isNotEmpty)
          const SizedBox(height: 12),
        if (listaEmp.isNotEmpty) ...[
          const _SubTitulo(
              icon: Icons.workspace_premium, label: 'Tempo de casa'),
          for (final a in listaEmp)
            _AniversarianteTile(
                a: a,
                detalhe:
                    'Dia ${a.dia} — ${a.anos} ${a.anos == 1 ? 'ano' : 'anos'}'),
        ],
      ],
    );
  }
}

class _SubTitulo extends StatelessWidget {
  const _SubTitulo({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _AniversarianteTile extends StatelessWidget {
  const _AniversarianteTile({required this.a, required this.detalhe});

  final Aniversariante a;
  final String detalhe;

  @override
  Widget build(BuildContext context) {
    final tokens = context.statusTokens;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: tokens.highlight.withValues(alpha: 0.15),
        backgroundImage: a.fotoUrl != null ? CachedNetworkImageProvider(a.fotoUrl!, maxWidth: 320) : null,
        child: a.fotoUrl == null
            ? Text(a.initials,
                style: TextStyle(
                    fontSize: 11,
                    color: tokens.highlight,
                    fontWeight: FontWeight.w700))
            : null,
      ),
      title: Text(a.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(detalhe,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

/// Movimentação de pessoal — barras agrupadas admissões x desligamentos.
class _MovimentacaoChart extends ConsumerWidget {
  const _MovimentacaoChart();

  static const _mesAbrev = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
    'jul', 'ago', 'set', 'out', 'nov', 'dez',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final async = ref.watch(movimentacaoMesProvider);

    return async.when(
      loading: () => const _ChartLoading(),
      error: (e, _) => _EmptyChart('Erro ao carregar.\n${friendlyError(e)}'),
      data: (meses) {
        if (meses.isEmpty) {
          return const _EmptyChart(
              'Sem admissões ou desligamentos no período.');
        }
        final maxVal = meses
            .map((m) => m.admissoes > m.desligamentos
                ? m.admissoes
                : m.desligamentos)
            .fold<int>(0, (a, b) => a > b ? a : b);
        final maxY = (maxVal + 1).toDouble();

        return Column(
          children: [
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.4),
                        strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: (maxY / 4).ceilToDouble().clamp(1, 9999),
                        getTitlesWidget: (v, meta) => Text(
                            v % 1 == 0 ? v.toInt().toString() : '',
                            style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.outline)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= meses.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(_mesAbrev[meses[i].mes.month - 1],
                                style: TextStyle(
                                    fontSize: 9,
                                    color: theme.colorScheme.outline)),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < meses.length; i++)
                      BarChartGroupData(x: i, barsSpace: 2, barRods: [
                        BarChartRodData(
                            toY: meses[i].admissoes.toDouble(),
                            color: tokens.success,
                            width: 7,
                            borderRadius: BorderRadius.circular(2)),
                        BarChartRodData(
                            toY: meses[i].desligamentos.toDouble(),
                            color: tokens.danger,
                            width: 7,
                            borderRadius: BorderRadius.circular(2)),
                      ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: tokens.success, label: 'Admissões'),
                const SizedBox(width: 20),
                _LegendDot(color: tokens.danger, label: 'Desligamentos'),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TopTalentos extends ConsumerWidget {
  const _TopTalentos({this.onTap});

  final void Function(String candidatoId)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.statusTokens;
    final async = ref.watch(topTalentosProvider);

    return async.when(
      loading: () => const _ChartLoading(),
      error: (e, _) => _EmptyChart('Erro ao carregar.\n${friendlyError(e)}'),
      data: (talentos) {
        if (talentos.isEmpty) {
          return const _EmptyChart('Sem candidatos com score ainda.');
        }
        return Column(
          children: [
            for (final c in talentos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: onTap == null ? null : () => onTap!(c.id),
                leading: CircleAvatar(
                  backgroundColor: tokens.highlight.withValues(alpha: 0.15),
                  backgroundImage:
                      c.fotoUrl != null ? CachedNetworkImageProvider(c.fotoUrl!, maxWidth: 320) : null,
                  child: c.fotoUrl == null
                      ? Text(c.initials,
                          style: TextStyle(
                              color: tokens.highlight,
                              fontWeight: FontWeight.w700))
                      : null,
                ),
                title: Text(c.nome,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: (c.cargoPretendido ?? '').isNotEmpty
                    ? Text(c.cargoPretendido!,
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tokens.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${c.scoreCompletude ?? 0}%',
                      style: TextStyle(
                          color: tokens.success,
                          fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Barra horizontal proporcional (funil e níveis).
class _HBar extends StatelessWidget {
  const _HBar({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  final String label;
  final int value;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frac = max > 0 ? value / max : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(fontSize: 12.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 22,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: frac == 0 ? 0.02 : frac,
                  child: Container(
                    height: 22,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text('$value',
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _ChartLoading extends StatelessWidget {
  const _ChartLoading();

  @override
  Widget build(BuildContext context) => const SizedBox(
      height: 120, child: Center(child: CircularProgressIndicator()));
}

/// Gráfico sem dado.
///
/// "Sem dados" sozinho deixa a pessoa sem saber se o painel quebrou, se ela
/// não tem permissão ou se falta cadastro. Por isso o bloco carrega sempre
/// uma [dica] com o cadastro que alimenta aquele gráfico — exceto quando a
/// mensagem é de erro de carregamento, que é outra história.
class _EmptyChart extends StatelessWidget {
  const _EmptyChart(
    this.message, {
    this.dica,
    this.icone = Icons.insert_chart_outlined,
  });

  final String message;
  final String? dica;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return HrEmptyBlock(
      icone: icone,
      titulo: message,
      dica: dica,
      altura: dica == null ? 100 : 140,
    );
  }
}
