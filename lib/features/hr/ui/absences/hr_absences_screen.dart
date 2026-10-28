import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/absence_model.dart';
import 'package:alinha_ja/features/hr/models/employee_model.dart';
import 'package:alinha_ja/features/hr/providers/absences_provider.dart';
import 'package:alinha_ja/features/hr/providers/employee_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/absence_calendar.dart';
import 'package:alinha_ja/features/hr/ui/widgets/ferias_saldo_card.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_responsive.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-17 + RH-26 — gestão de ausências pelo RH.
/// Três visões: fila de solicitações, calendário da equipe e saldos de
/// férias por período aquisitivo.
class HrAbsencesScreen extends ConsumerStatefulWidget {
  const HrAbsencesScreen({super.key});

  @override
  ConsumerState<HrAbsencesScreen> createState() => _HrAbsencesScreenState();
}

class _HrAbsencesScreenState extends ConsumerState<HrAbsencesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ausências e Férias'),
        bottom: TabBar(
          controller: _tab,
          // Rolável: em telas estreitas os rótulos não se espremem.
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Solicitações'),
            Tab(text: 'Calendário'),
            Tab(text: 'Saldos de férias'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _SolicitacoesTab(),
          _CalendarioTab(),
          _SaldosTab(),
        ],
      ),
    );
  }
}

// ── Solicitações ─────────────────────────────────────────────

class _SolicitacoesTab extends ConsumerWidget {
  const _SolicitacoesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAbsences = ref.watch(hrAbsencesProvider);

    return asyncAbsences.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
      data: (list) {
        if (list.isEmpty) {
          return const HrEmptyState(
            icone: Icons.event_busy,
            titulo: 'Nenhuma solicitação de ausência',
            descricao:
                'Aqui chegam os pedidos de férias, folga, atestado e '
                'licença feitos pelo time. O RH aprova ou recusa, e a '
                'decisão volta para o colaborador.',
            passos: [
              'O colaborador abre o pedido pelo app, em "Minhas ausências".',
              'O pedido cai nesta lista com a situação "pendente".',
              'Aprove ou recuse — para férias, o sistema valida antes o '
                  'saldo do período aquisitivo.',
            ],
            nota: 'Para que a validação de férias funcione, abra o período '
                'aquisitivo de cada funcionário na aba Saldos.',
            estrutura: HrGhostList(
              colunas: ['Colaborador', 'Tipo', 'Período'],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(hrAbsencesProvider),
          child: HrContentColumn(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _SolicitacaoCard(ausencia: list[index]),
            ),
          ),
        );
      },
    );
  }
}

class _SolicitacaoCard extends ConsumerStatefulWidget {
  const _SolicitacaoCard({required this.ausencia});

  final AbsenceModel ausencia;

  @override
  ConsumerState<_SolicitacaoCard> createState() => _SolicitacaoCardState();
}

class _SolicitacaoCardState extends ConsumerState<_SolicitacaoCard> {
  bool _ocupado = false;

  static final _data = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.ausencia;
    final dias = a.dataFim.difference(a.dataInicio).inDays + 1;
    final canManage = ref.watch(rbacCanProvider((module: 'rh_ausencias', action: 'manage')));

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    a.funcionarioNome ?? 'Funcionário desconhecido',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                StatusBadge(
                    label: a.status.toUpperCase(), role: statusRole(a.status)),
              ],
            ),
            const SizedBox(height: 8),
            Text('${formatTipo(a.tipo)}: ${_data.format(a.dataInicio)} até '
                '${_data.format(a.dataFim)} ($dias ${dias == 1 ? 'dia' : 'dias'})'),
            if ((a.justificativa ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Justificativa: ${a.justificativa}',
                    style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
            if (a.status == 'pendente' && canManage) ...[
              const SizedBox(height: 16),
              if (a.tipo == 'ferias') _SaldoResumo(funcionarioId: a.funcionarioId),
              // Wrap alinhado à direita: no celular os botões descem em
              // vez de estourar a linha.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _ocupado ? null : () => _decidir(false),
                    style: TextButton.styleFrom(
                        foregroundColor: context.statusTokens.danger),
                    child: const Text('Rejeitar'),
                  ),
                  FilledButton(
                    onPressed: _ocupado ? null : () => _decidir(true),
                    child: _ocupado
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Aprovar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _decidir(bool aprovar) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _ocupado = true);
    try {
      final acoes = ref.read(absenceActionsProvider);
      if (aprovar) {
        await acoes.approve(widget.ausencia.id);
      } else {
        await acoes.reject(widget.ausencia.id);
      }
    } catch (e) {
      if (mounted) setState(() => _ocupado = false);
      // Saldo insuficiente chega aqui como erro da RPC.
      messenger.showSnackBar(SnackBar(
        content: Text(_mensagemErro(e)),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  String _mensagemErro(Object e) {
    final texto = e.toString();
    final idx = texto.indexOf('Saldo insuficiente');
    if (idx >= 0) return texto.substring(idx).split('\n').first;
    if (texto.contains('Nenhum período aquisitivo')) {
      return 'Nenhum período aquisitivo com saldo. Abra um período na aba '
          '"Saldos de férias" antes de aprovar.';
    }
    return friendlyError(e);
  }
}

/// Saldo do funcionário embutido no card, para o RH decidir com contexto.
class _SaldoResumo extends ConsumerWidget {
  const _SaldoResumo({required this.funcionarioId});

  final String funcionarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldos = ref.watch(hrFeriasSaldosProvider).valueOrNull;
    if (saldos == null) return const SizedBox.shrink();

    final doFuncionario =
        saldos.where((s) => s.funcionarioId == funcionarioId && s.aberto);
    final disponivel =
        doFuncionario.fold<int>(0, (soma, s) => soma + s.diasDisponiveis);
    final tokens = context.statusTokens;
    final cor = disponivel > 0 ? tokens.info : tokens.danger;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.beach_access, size: 16, color: cor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              disponivel > 0
                  ? 'Saldo de férias: $disponivel ${disponivel == 1 ? 'dia disponível' : 'dias disponíveis'}'
                  : 'Sem saldo de férias em período aberto',
              style: TextStyle(fontSize: 12.5, color: cor),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Calendário ───────────────────────────────────────────────

class _CalendarioTab extends ConsumerStatefulWidget {
  const _CalendarioTab();

  @override
  ConsumerState<_CalendarioTab> createState() => _CalendarioTabState();
}

class _CalendarioTabState extends ConsumerState<_CalendarioTab> {
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(absenceCalendarProvider(_mes));

    return HrContentColumn(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('Erro: ${friendlyError(e)}')),
            ),
            data: (entradas) => AbsenceCalendar(
              mes: _mes,
              entradas: entradas,
              onMesAlterado: (m) => setState(() => _mes = m),
              onDiaSelecionado: (dia, doDia) =>
                  _mostrarDia(context, dia, doDia),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDia(
      BuildContext context, DateTime dia, List<AbsenceCalendarEntry> doDia) {
    showHrFormSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${dia.day} de ${AbsenceCalendar.meses[dia.month - 1]}',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in doDia)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.funcionarioNome),
                        subtitle: Text(
                            '${formatTipo(e.tipo)} · ${e.dias} ${e.dias == 1 ? 'dia' : 'dias'}'),
                        trailing: StatusBadge(
                            label: e.status.toUpperCase(),
                            role: statusRole(e.status)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Saldos de férias ─────────────────────────────────────────

class _SaldosTab extends ConsumerWidget {
  const _SaldosTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hrFeriasSaldosProvider);
    final canManage = ref.watch(rbacCanProvider((module: 'rh_ausencias', action: 'manage')));

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
        data: (saldos) {
          if (saldos.isEmpty) {
            return HrEmptyState(
              icone: Icons.beach_access,
              titulo: 'Nenhum período aquisitivo aberto',
              descricao:
                  'O período aquisitivo é o intervalo de 12 meses que dá '
                  'direito a 30 dias de férias. Enquanto ele não existir, o '
                  'pedido de férias chega sem saldo para conferir e a '
                  'aprovação fica no escuro.',
              passos: const [
                'Toque em "Abrir período" e escolha o funcionário.',
                'Informe a data de início do período (normalmente a data '
                    'de admissão ou o aniversário dela).',
                'Repita para cada pessoa do time.',
                'A partir daí, cada férias aprovada desconta do saldo '
                    'automaticamente.',
              ],
              acaoLabel: canManage ? 'Abrir primeiro período' : null,
              acaoIcone: Icons.add,
              onAcao: canManage ? () => _abrirPeriodo(context, ref) : null,
              estrutura: const HrGhostList(
                colunas: ['Funcionário', 'Período', 'Saldo'],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(hrFeriasSaldosProvider),
            child: HrContentColumn(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 96),
                children: [
                  for (final s in saldos)
                    FeriasSaldoCard(
                      saldo: s,
                      mostrarNome: true,
                      onAbono: canManage ? () => _abono(context, ref, s) : null,
                    ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: !canManage
          ? null
          : FloatingActionButton.extended(
        onPressed: () => _abrirPeriodo(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Abrir período'),
      ),
    );
  }

  Future<void> _abrirPeriodo(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final funcionarioId = await showHrFormSheet<String>(
      context: context,
      builder: (_) => const _EscolherFuncionarioSheet(),
    );
    if (funcionarioId == null) return;
    try {
      await ref
          .read(absenceActionsProvider)
          .abrirPeriodoAquisitivo(funcionarioId);
      messenger.showSnackBar(
          const SnackBar(content: Text('Período aquisitivo aberto.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Não foi possível abrir: ${friendlyError(e)}')));
    }
  }

  Future<void> _abono(
      BuildContext context, WidgetRef ref, FeriasSaldo saldo) async {
    final messenger = ScaffoldMessenger.of(context);
    final dias = await showHrFormSheet<int>(
      context: context,
      builder: (_) => _AbonoSheet(saldo: saldo),
    );
    if (dias == null) return;
    try {
      await ref.read(absenceActionsProvider).setDiasAbonados(saldo.periodoId, dias);
      messenger.showSnackBar(
          SnackBar(content: Text('Abono de $dias dia(s) registrado.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }
}

/// Funcionários que casam com o termo buscado (server-side, 1ª página).
final _buscaFuncionariosProvider = FutureProvider.autoDispose
    .family<List<EmployeeModel>, String>((ref, termo) {
  return ref.watch(employeeServiceProvider).fetchEmployees(search: termo);
});

/// Busca simples de funcionário para abrir o período aquisitivo.
class _EscolherFuncionarioSheet extends ConsumerStatefulWidget {
  const _EscolherFuncionarioSheet();

  @override
  ConsumerState<_EscolherFuncionarioSheet> createState() =>
      _EscolherFuncionarioSheetState();
}

class _EscolherFuncionarioSheetState
    extends ConsumerState<_EscolherFuncionarioSheet> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    // Busca server-side: a lista de funcionários é paginada, então
    // filtrar só a primeira página esconderia gente.
    final async = ref.watch(_buscaFuncionariosProvider(_busca));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Abrir período aquisitivo',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'O período começa no dia seguinte ao último; se não houver, '
              'na data de admissão.',
              style: TextStyle(
                  fontSize: 12.5, color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 16),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Buscar funcionário',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _busca = v.toLowerCase().trim()),
            ),
            const SizedBox(height: 12),
            // Altura limitada: o sheet não empurra o teclado nem cresce
            // sem controle no desktop.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: async.when(
                loading: () => const Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator())),
                error: (e, _) => Text('Erro: ${friendlyError(e)}'),
                // A consulta já vem filtrada pelo termo — nada de refiltrar
                // aqui, o que descartaria acertos por matrícula/cargo.
                data: (funcionarios) {
                  if (funcionarios.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.person_search,
                              size: 32,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 8),
                          Text(
                            'Nenhum funcionário com esse nome, matrícula ou '
                            'cargo. Se a empresa ainda não tem fichas, '
                            'cadastre-as em RH > Funcionários antes de abrir '
                            'o período.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: funcionarios.length,
                    itemBuilder: (_, i) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(funcionarios[i].nome),
                      subtitle: funcionarios[i].cargo == null
                          ? null
                          : Text(funcionarios[i].cargo!),
                      onTap: () => Navigator.pop(context, funcionarios[i].id),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Abono pecuniário: até 1/3 do direito, limitado ao saldo livre.
class _AbonoSheet extends StatefulWidget {
  const _AbonoSheet({required this.saldo});

  final FeriasSaldo saldo;

  @override
  State<_AbonoSheet> createState() => _AbonoSheetState();
}

class _AbonoSheetState extends State<_AbonoSheet> {
  late double _dias = widget.saldo.diasAbonados.toDouble();

  @override
  Widget build(BuildContext context) {
    final s = widget.saldo;
    // Teto legal (1/3) cruzado com o que ainda não foi comprometido.
    final tetoLegal = s.diasDireito ~/ 3;
    final livre = s.diasDireito - s.diasGozados - s.diasReservados;
    final maximo = tetoLegal < livre ? tetoLegal : livre;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Abono pecuniário',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Dias convertidos em dinheiro. Máximo de $maximo '
              '(1/3 do direito, respeitando o que já foi usado).',
              style: TextStyle(
                  fontSize: 12.5, color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 20),
            Text('${_dias.round()} dia(s)',
                style: Theme.of(context).textTheme.titleMedium),
            if (maximo > 0)
              Slider(
                value: _dias.clamp(0, maximo.toDouble()),
                max: maximo.toDouble(),
                divisions: maximo,
                label: '${_dias.round()}',
                onChanged: (v) => setState(() => _dias = v),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Sem dias livres para abono neste período.'),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: maximo > 0
                  ? () => Navigator.pop(context, _dias.round())
                  : null,
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers compartilhados ───────────────────────────────────

StatusRole statusRole(String status) => switch (status) {
      'aprovado' => StatusRole.success,
      'rejeitado' => StatusRole.danger,
      _ => StatusRole.warning,
    };

String formatTipo(String tipo) => switch (tipo) {
      'ferias' => 'Férias',
      'licenca_medica' => 'Licença médica / atestado',
      'folga' => 'Folga',
      _ => 'Outro',
    };
