import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/features/hr/models/absence_model.dart';
import 'package:alinha_ja/features/hr/providers/absences_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/absence_calendar.dart';
import 'package:alinha_ja/features/hr/ui/widgets/ferias_saldo_card.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_responsive.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-17 + RH-26 — visão do funcionário: saldo de férias, calendário do
/// mês e histórico das próprias solicitações.
class MyAbsencesScreen extends ConsumerStatefulWidget {
  const MyAbsencesScreen({super.key});

  @override
  ConsumerState<MyAbsencesScreen> createState() => _MyAbsencesScreenState();
}

class _MyAbsencesScreenState extends ConsumerState<MyAbsencesScreen> {
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  Widget build(BuildContext context) {
    final asyncAbsences = ref.watch(myAbsencesProvider);
    final saldos = ref.watch(myFeriasSaldosProvider);
    final calendario = ref.watch(absenceCalendarProvider(_mes));

    return Scaffold(
      appBar: AppBar(title: const Text('Minhas Ausências e Férias')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRequestForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova solicitação'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myAbsencesProvider);
          ref.invalidate(myFeriasSaldosProvider);
          ref.invalidate(absenceCalendarProvider);
        },
        child: HrContentColumn(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 96),
            children: [
              // ── Saldo de férias ──
              saldos.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (lista) {
                  final abertos = lista.where((s) => s.aberto).toList();
                  if (abertos.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Titulo('Saldo de férias'),
                      const SizedBox(height: 8),
                      for (final s in abertos) FeriasSaldoCard(saldo: s),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),

              // ── Calendário ──
              const _Titulo('Calendário'),
              const SizedBox(height: 4),
              calendario.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('Erro no calendário: ${friendlyError(e)}'),
                ),
                data: (entradas) => AbsenceCalendar(
                  mes: _mes,
                  entradas: entradas,
                  onMesAlterado: (m) => setState(() => _mes = m),
                ),
              ),
              const SizedBox(height: 24),

              // ── Histórico ──
              const _Titulo('Minhas solicitações'),
              const SizedBox(height: 8),
              asyncAbsences.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Erro: ${friendlyError(e)}'),
                data: (list) {
                  if (list.isEmpty) {
                    return HrEmptyBlock(
                      icone: Icons.event_available,
                      titulo: 'Nenhuma solicitação ainda',
                      dica:
                          'Use "Nova solicitação" para pedir férias, folga '
                          'ou registrar atestado. O RH recebe o pedido e você '
                          'acompanha a resposta por aqui.',
                      altura: 160,
                      acaoLabel: 'Fazer a primeira solicitação',
                      onAcao: () => _showRequestForm(context),
                    );
                  }
                  return Column(
                    children: [
                      for (final a in list) _SolicitacaoTile(ausencia: a),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRequestForm(BuildContext context) {
    showHrFormSheet<void>(
      context: context,
      builder: (_) => const _RequestAbsenceSheet(),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(texto,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700));
  }
}

class _SolicitacaoTile extends StatelessWidget {
  const _SolicitacaoTile({required this.ausencia});

  final AbsenceModel ausencia;

  static final _data = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = ausencia;
    final dias = a.dataFim.difference(a.dataInicio).inDays + 1;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        isThreeLine: (a.justificativa ?? '').isNotEmpty,
        title: Text(_formatTipo(a.tipo),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${_data.format(a.dataInicio)} até ${_data.format(a.dataFim)}'
                ' · $dias ${dias == 1 ? 'dia' : 'dias'}'),
            if ((a.justificativa ?? '').isNotEmpty)
              Text(a.justificativa!,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: StatusBadge(
          label: a.status.toUpperCase(),
          role: _statusRole(a.status),
        ),
      ),
    );
  }

  static StatusRole _statusRole(String status) => switch (status) {
        'aprovado' => StatusRole.success,
        'rejeitado' => StatusRole.danger,
        _ => StatusRole.warning,
      };

  static String _formatTipo(String tipo) => switch (tipo) {
        'ferias' => 'Férias',
        'licenca_medica' => 'Licença médica / atestado',
        'folga' => 'Folga',
        _ => 'Outro',
      };
}

class _RequestAbsenceSheet extends ConsumerStatefulWidget {
  const _RequestAbsenceSheet();

  @override
  ConsumerState<_RequestAbsenceSheet> createState() => _RequestAbsenceSheetState();
}

class _RequestAbsenceSheetState extends ConsumerState<_RequestAbsenceSheet> {
  final _formKey = GlobalKey<FormState>();
  String _tipo = 'ferias';
  DateTime? _inicio;
  DateTime? _fim;
  final _justifCtrl = TextEditingController();
  bool _isLoading = false;

  void _submit() async {
    if (!_formKey.currentState!.validate() || _inicio == null || _fim == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha os campos obrigatórios.')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(absenceActionsProvider).create({
        'tipo': _tipo,
        'data_inicio': _inicio!.toIso8601String().split('T')[0],
        'data_fim': _fim!.toIso8601String().split('T')[0],
        'justificativa': _justifCtrl.text,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Solicitar ausência', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Férias descontam do seu saldo do período aquisitivo assim que '
              'o RH aprovar.',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'ferias', child: Text('Férias')),
                DropdownMenuItem(value: 'licenca_medica', child: Text('Licença Médica / Atestado')),
                DropdownMenuItem(value: 'folga', child: Text('Folga')),
                DropdownMenuItem(value: 'outro', child: Text('Outro')),
              ],
              onChanged: (v) => setState(() => _tipo = v!),
            ),
            const SizedBox(height: 16),
            // Datas lado a lado quando cabe; empilhadas no celular.
            HrFieldRow(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_inicio != null
                      ? DateFormat('dd/MM/yyyy').format(_inicio!)
                      : 'Início'),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _inicio ?? DateTime.now(),
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d == null) return;
                    setState(() {
                      _inicio = d;
                      // Fim anterior ao novo início não faz sentido:
                      // o banco recusaria (chk_data_fim_maior_inicio).
                      if (_fim != null && _fim!.isBefore(d)) _fim = d;
                    });
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_fim != null
                      ? DateFormat('dd/MM/yyyy').format(_fim!)
                      : 'Fim'),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _fim ?? _inicio ?? DateTime.now(),
                      firstDate: _inicio ??
                          DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _fim = d);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _justifCtrl,
              decoration: const InputDecoration(
                labelText: 'Justificativa / Observação',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading ? const CircularProgressIndicator() : const Text('Enviar Solicitação'),
            )
          ],
        ),
      ),
    );
  }
}
