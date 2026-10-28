import 'package:flutter/material.dart';

import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/absence_model.dart';

/// RH-26 — calendário mensal de ausências.
///
/// Serve as duas visões: no RH mostra a equipe inteira, na tela do
/// funcionário só as dele (quem filtra é a RLS). O layout se adapta —
/// em telas estreitas as células ficam quadradas e compactas; com
/// largura, crescem e cabem mais marcadores por dia.
class AbsenceCalendar extends StatelessWidget {
  const AbsenceCalendar({
    super.key,
    required this.mes,
    required this.entradas,
    required this.onMesAlterado,
    this.onDiaSelecionado,
  });

  /// Qualquer data dentro do mês exibido.
  final DateTime mes;
  final List<AbsenceCalendarEntry> entradas;
  final ValueChanged<DateTime> onMesAlterado;
  final void Function(DateTime dia, List<AbsenceCalendarEntry> doDia)?
      onDiaSelecionado;

  static const _diasSemana = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

  /// Nomes fixos: o app não inicializa o locale pt_BR do intl, então
  /// `DateFormat(..., 'pt_BR')` estouraria em runtime (mesma decisão de
  /// hr_ponto_screen.dart).
  static const meses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primeiro = DateTime(mes.year, mes.month, 1);
    final totalDias = DateTime(mes.year, mes.month + 1, 0).day;
    // weekday: 1=segunda … 7=domingo. A grade começa no domingo.
    final vazioInicial = primeiro.weekday % 7;
    final celulas = vazioInicial + totalDias;
    final linhas = (celulas / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BarraMes(mes: mes, onMesAlterado: onMesAlterado),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final d in _diasSemana)
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            final larguraCelula = constraints.maxWidth / 7;
            // Em telas largas a célula fica mais alta que quadrada, o que
            // dá espaço para os marcadores sem esticar demais.
            final alturaCelula =
                larguraCelula < 56 ? larguraCelula : larguraCelula * 0.82;
            return Column(
              children: [
                for (var linha = 0; linha < linhas; linha++)
                  Row(
                    children: [
                      for (var col = 0; col < 7; col++)
                        Expanded(
                          child: SizedBox(
                            height: alturaCelula.clamp(40.0, 88.0),
                            child: _celula(
                              context,
                              linha * 7 + col - vazioInicial + 1,
                              totalDias,
                              compacta: larguraCelula < 56,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        const _Legenda(),
      ],
    );
  }

  Widget _celula(BuildContext context, int dia, int totalDias,
      {required bool compacta}) {
    if (dia < 1 || dia > totalDias) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final data = DateTime(mes.year, mes.month, dia);
    final doDia = entradas.where((e) => e.cobre(data)).toList();
    final hoje = DateTime.now();
    final isHoje =
        hoje.year == data.year && hoje.month == data.month && hoje.day == dia;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: doDia.isEmpty
            ? Colors.transparent
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: doDia.isEmpty || onDiaSelecionado == null
              ? null
              : () => onDiaSelecionado!(data, doDia),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isHoje
                  ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$dia',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isHoje ? FontWeight.w800 : FontWeight.w500,
                    color: isHoje ? theme.colorScheme.primary : null,
                  ),
                ),
                const Spacer(),
                if (doDia.isNotEmpty)
                  compacta
                      // Sem espaço para nomes: só um ponto por tipo.
                      ? Row(
                          children: [
                            for (final e in doDia.take(3))
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(right: 3),
                                decoration: BoxDecoration(
                                  color: _cor(tokens, e),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            if (doDia.length > 3)
                              Text('+${doDia.length - 3}',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: theme.colorScheme.outline)),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final e in doDia.take(2))
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: _cor(tokens, e).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  e.funcionarioNome.split(' ').first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 9.5, color: _cor(tokens, e)),
                                ),
                              ),
                            if (doDia.length > 2)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text('+${doDia.length - 2}',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: theme.colorScheme.outline)),
                              ),
                          ],
                        ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _cor(AlinhaStatusTokens tokens, AbsenceCalendarEntry e) {
    if (e.status == 'pendente') return tokens.color(StatusRole.warning);
    return switch (e.tipo) {
      'ferias' => tokens.color(StatusRole.info),
      'licenca_medica' => tokens.color(StatusRole.danger),
      'folga' => tokens.color(StatusRole.success),
      _ => tokens.color(StatusRole.neutral),
    };
  }
}

class _BarraMes extends StatelessWidget {
  const _BarraMes({required this.mes, required this.onMesAlterado});

  final DateTime mes;
  final ValueChanged<DateTime> onMesAlterado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mês anterior',
          onPressed: () => onMesAlterado(DateTime(mes.year, mes.month - 1, 1)),
        ),
        Expanded(
          child: Text(
            '${AbsenceCalendar.meses[mes.month - 1]} de ${mes.year}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Próximo mês',
          onPressed: () => onMesAlterado(DateTime(mes.year, mes.month + 1, 1)),
        ),
      ],
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda();

  @override
  Widget build(BuildContext context) {
    final tokens = context.statusTokens;
    final itens = <(String, Color)>[
      ('Férias', tokens.color(StatusRole.info)),
      ('Atestado', tokens.color(StatusRole.danger)),
      ('Folga', tokens.color(StatusRole.success)),
      ('Aguardando aprovação', tokens.color(StatusRole.warning)),
    ];

    // Wrap: a legenda quebra sozinha em telas estreitas.
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (rotulo, cor) in itens)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(rotulo,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.outline)),
            ],
          ),
      ],
    );
  }
}
