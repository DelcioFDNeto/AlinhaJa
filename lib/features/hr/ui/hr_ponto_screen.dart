import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/features/hr/models/ponto_model.dart';
import 'package:alinha_ja/features/hr/providers/people_management_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// Fase 8 — Controle de Ponto (visão do RH).
/// Espelho dos registros por período/funcionário, lançamento manual
/// (origem 'importacao') e aprovação/ajuste de batidas.
class HrPontoScreen extends ConsumerStatefulWidget {
  const HrPontoScreen({super.key});

  @override
  ConsumerState<HrPontoScreen> createState() => _HrPontoScreenState();
}

class _HrPontoScreenState extends ConsumerState<HrPontoScreen> {
  String? _funcionarioId;
  late DateTime _de;
  late DateTime _ate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _de = DateTime(now.year, now.month, 1);
    _ate = DateTime(now.year, now.month + 1, 0);
  }

  PontoFilters get _filters =>
      PontoFilters(funcionarioId: _funcionarioId, de: _de, ate: _ate);

  Future<void> _pickPeriodo() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _de, end: _ate),
    );
    if (range != null) {
      setState(() {
        _de = range.start;
        _ate = range.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final registros = ref.watch(pontoRegistrosProvider(_filters));
    final funcionarios = ref.watch(funcionariosLiteProvider);
    final periodoFmt = DateFormat('dd/MM/yyyy');
    final canManage = ref.watch(rbacCanProvider((module: 'rh_ponto', action: 'manage')));

    return Scaffold(
      appBar: AppBar(title: const Text('Controle de Ponto')),
      floatingActionButton: !canManage
          ? null
          : FloatingActionButton.extended(
        onPressed: () => _showLancamentoManual(context),
        icon: const Icon(Icons.more_time),
        label: const Text('Lançar registro'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                      '${periodoFmt.format(_de)} — ${periodoFmt.format(_ate)}'),
                  onPressed: _pickPeriodo,
                ),
                SizedBox(
                  width: 260,
                  child: funcionarios.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erro: ${friendlyError(e)}'),
                    data: (list) => DropdownButtonFormField<String?>(
                      initialValue: _funcionarioId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Funcionário',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Todos')),
                        for (final f in list)
                          DropdownMenuItem(
                              value: f['id'] as String,
                              child: Text(f['nome'] as String? ?? '',
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _funcionarioId = v),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: registros.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
              data: (list) {
                if (list.isEmpty) {
                  return HrEmptyState(
                    icone: Icons.schedule,
                    titulo: 'Nenhuma batida no período',
                    descricao:
                        'Aqui ficam as batidas de entrada e saída do time. '
                        'Elas chegam sozinhas quando o colaborador registra '
                        'ponto pelo app, e o RH pode lançar à mão o que '
                        'faltou.',
                    passos: const [
                      'Confira o período e o funcionário nos filtros acima '
                          '— o recorte pode estar escondendo registros.',
                      'Oriente o time a bater ponto pelo app, em "Meu ponto".',
                      'Use "Lançar registro" para incluir uma batida '
                          'esquecida; ela entra com origem "importação".',
                    ],
                    acaoLabel: 'Lançar registro',
                    acaoIcone: Icons.add,
                    onAcao: () => _showLancamentoManual(context),
                    estrutura: const HrGhostList(
                      colunas: ['Funcionário', 'Entrada/Saída', 'Origem'],
                    ),
                  );
                }
                // Agrupa por dia (registros já vêm em ordem decrescente).
                // Dias da semana fixos: o app não inicializa locale pt_BR
                // no intl (mesmo padrão do dashboard de RH).
                const dias = [
                  'Segunda-feira', 'Terça-feira', 'Quarta-feira',
                  'Quinta-feira', 'Sexta-feira', 'Sábado', 'Domingo',
                ];
                final grupos = <String, List<PontoRegistroModel>>{};
                final diaFmt = DateFormat('dd/MM/yyyy');
                for (final r in list) {
                  final local = r.dataHora.toLocal();
                  final key =
                      '${dias[local.weekday - 1]}, ${diaFmt.format(local)}';
                  grupos.putIfAbsent(key, () => []).add(r);
                }
                final keys = grupos.keys.toList();
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: keys.length,
                  itemBuilder: (context, i) {
                    final dia = keys[i];
                    final items = grupos[dia]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(dia,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                        for (final r in items) _RegistroTile(registro: r),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showLancamentoManual(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LancamentoManualSheet(onSaved: () {
        ref.invalidate(pontoRegistrosProvider(_filters));
      }),
    );
  }
}

class _RegistroTile extends ConsumerWidget {
  const _RegistroTile({required this.registro});

  final PontoRegistroModel registro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final horaFmt = DateFormat('HH:mm');
    final canManage = ref.watch(rbacCanProvider((module: 'rh_ponto', action: 'manage')));

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          registro.origem == 'app'
              ? Icons.smartphone_outlined
              : Icons.edit_calendar_outlined,
          size: 20,
        ),
        title: Text(
          '${horaFmt.format(registro.dataHora.toLocal())} · '
          '${PontoTipo.label(registro.tipo)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(registro.funcionarioNome ?? 'Funcionário'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusBadge(
              label: PontoStatus.label(registro.status),
              role: PontoStatus.role(registro.status),
            ),
            if (canManage)
            PopupMenuButton<String>(
              tooltip: 'Alterar status',
              onSelected: (status) async {
                await ref
                    .read(peopleManagementServiceProvider)
                    .atualizarStatusPonto(registro.id, status);
                ref.invalidate(pontoRegistrosProvider);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'aprovado', child: Text('Aprovar')),
                PopupMenuItem(
                    value: 'aguardando_ajuste',
                    child: Text('Marcar p/ ajuste')),
                PopupMenuItem(value: 'rejeitado', child: Text('Rejeitar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LancamentoManualSheet extends ConsumerStatefulWidget {
  const _LancamentoManualSheet({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_LancamentoManualSheet> createState() =>
      _LancamentoManualSheetState();
}

class _LancamentoManualSheetState
    extends ConsumerState<_LancamentoManualSheet> {
  String? _funcionarioId;
  String _tipo = PontoTipo.entrada;
  DateTime _dataHora = DateTime.now();
  bool _isLoading = false;

  Future<void> _pickDataHora() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dataHora,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dataHora),
    );
    if (t == null) return;
    setState(() =>
        _dataHora = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _submit() async {
    if (_funcionarioId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione o funcionário.')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(peopleManagementServiceProvider).lancarPontoManual(
            funcionarioId: _funcionarioId!,
            dataHora: _dataHora,
            tipo: _tipo,
          );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final funcionarios = ref.watch(funcionariosLiteProvider);
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Lançamento manual de ponto',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Registrado com origem "importação" (ajuste do RH).',
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 16),
          funcionarios.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Erro: ${friendlyError(e)}'),
            data: (list) => DropdownButtonFormField<String>(
              initialValue: _funcionarioId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Funcionário', border: OutlineInputBorder()),
              items: [
                for (final f in list)
                  DropdownMenuItem(
                      value: f['id'] as String,
                      child: Text(f['nome'] as String? ?? '',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _funcionarioId = v),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _tipo,
            decoration: const InputDecoration(
                labelText: 'Tipo de batida', border: OutlineInputBorder()),
            items: [
              for (final t in PontoTipo.ordem)
                DropdownMenuItem(value: t, child: Text(PontoTipo.label(t))),
            ],
            onChanged: (v) => setState(() => _tipo = v!),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.schedule),
            label: Text(fmt.format(_dataHora)),
            onPressed: _pickDataHora,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator())
                : const Text('Salvar registro'),
          ),
        ],
      ),
    );
  }
}
