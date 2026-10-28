import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/features/hr/models/ponto_model.dart';
import 'package:alinha_ja/features/hr/providers/absences_provider.dart';
import 'package:alinha_ja/features/hr/providers/people_management_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// Fase 8 — Meu Ponto (visão do colaborador): batida do dia com o
/// próximo tipo sugerido e espelho dos últimos 7 dias. Exige vínculo
/// funcionário ↔ usuário (F1.2).
class MyTimeClockScreen extends ConsumerWidget {
  const MyTimeClockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final funcionarioId = ref.watch(myFuncionarioIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meu Ponto')),
      body: funcionarioId.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
        data: (id) {
          if (id == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Seu usuário ainda não está vinculado a um funcionário.\n'
                  'Fale com o RH para liberar o registro de ponto.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _TimeClockBody(funcionarioId: id);
        },
      ),
    );
  }
}

class _TimeClockBody extends ConsumerStatefulWidget {
  const _TimeClockBody({required this.funcionarioId});

  final String funcionarioId;

  @override
  ConsumerState<_TimeClockBody> createState() => _TimeClockBodyState();
}

class _TimeClockBodyState extends ConsumerState<_TimeClockBody> {
  bool _isPunching = false;

  PontoFilters get _filters {
    final now = DateTime.now();
    final hoje = DateTime(now.year, now.month, now.day);
    return PontoFilters(
      funcionarioId: widget.funcionarioId,
      de: hoje.subtract(const Duration(days: 6)),
      ate: hoje,
    );
  }

  /// Próxima batida sugerida a partir das de hoje (entrada → saída
  /// almoço → retorno → saída). null quando o dia está completo.
  String? _proximoTipo(List<PontoRegistroModel> registros) {
    final now = DateTime.now();
    final hoje = registros.where((r) {
      final l = r.dataHora.toLocal();
      return l.year == now.year && l.month == now.month && l.day == now.day;
    }).toList();
    for (final tipo in PontoTipo.ordem) {
      if (!hoje.any((r) => r.tipo == tipo)) return tipo;
    }
    return null;
  }

  Future<void> _punch(String tipo) async {
    setState(() => _isPunching = true);
    try {
      final plataforma =
          kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
      await ref.read(peopleManagementServiceProvider).registrarPonto(
            funcionarioId: widget.funcionarioId,
            tipo: tipo,
            dispositivoInfo: plataforma,
          );
      ref.invalidate(pontoRegistrosProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('${PontoTipo.label(tipo)} registrada com sucesso!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao registrar: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isPunching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registros = ref.watch(pontoRegistrosProvider(_filters));
    final theme = Theme.of(context);
    final horaFmt = DateFormat('HH:mm');
    final diaFmt = DateFormat('dd/MM/yyyy');

    return registros.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
      data: (list) {
        final proximo = _proximoTipo(list);
        final grupos = <String, List<PontoRegistroModel>>{};
        for (final r in list) {
          final key = diaFmt.format(r.dataHora.toLocal());
          grupos.putIfAbsent(key, () => []).add(r);
        }
        final keys = grupos.keys.toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      diaFmt.format(DateTime.now()),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    if (proximo != null)
                      FilledButton.icon(
                        icon: const Icon(Icons.fingerprint),
                        label: Text(_isPunching
                            ? 'Registrando...'
                            : 'Registrar ${PontoTipo.label(proximo)}'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                        ),
                        onPressed: _isPunching ? null : () => _punch(proximo),
                      )
                    else
                      Text(
                        'Todas as batidas de hoje foram registradas. ✔',
                        style: theme.textTheme.bodyLarge,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Últimos 7 dias',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              const HrEmptyBlock(
                icone: Icons.schedule,
                titulo: 'Nenhuma batida nos últimos 7 dias',
                dica:
                    'Use o botão de registrar ponto acima ao começar e ao '
                    'encerrar o expediente. As batidas ficam listadas aqui '
                    'por dia, e o RH vê o mesmo histórico.',
                altura: 150,
              ),
            for (final dia in keys) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(dia, style: theme.textTheme.labelLarge),
              ),
              for (final r in grupos[dia]!)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 4),
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      r.origem == 'app'
                          ? Icons.smartphone_outlined
                          : Icons.edit_calendar_outlined,
                      size: 18,
                    ),
                    title: Text(
                        '${horaFmt.format(r.dataHora.toLocal())} · ${PontoTipo.label(r.tipo)}'),
                    trailing: StatusBadge(
                      label: PontoStatus.label(r.status),
                      role: PontoStatus.role(r.status),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
