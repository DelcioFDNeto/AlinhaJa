import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/features/hr/providers/people_management_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// Fase 8 (rh21/rh22) — Seções da ficha do funcionário: Histórico de
/// Cargos e Salários (cifrado; leitura/gravação só por RPC auditada)
/// e Dependentes (CPF cifrado).
class SalaryHistorySection extends ConsumerWidget {
  const SalaryHistorySection({super.key, required this.funcionarioId});

  final String funcionarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historico = ref.watch(historicoSalarialProvider(funcionarioId));
    final theme = Theme.of(context);
    final fmt = DateFormat('dd/MM/yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Histórico de cargos e salários',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Registrar'),
              onPressed: () => _showAddSheet(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Valores cifrados por organização; leitura auditada em rh_access_log.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 8),
        historico.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Erro: ${friendlyError(e)}'),
          data: (list) {
            if (list.isEmpty) {
              return const HrEmptyBlock(
                icone: Icons.trending_up,
                titulo: 'Nenhum registro salarial',
                dica:
                    'Cada reajuste, promoção ou mérito vira uma linha aqui, '
                    'formando o histórico da pessoa. Use "Novo registro" '
                    'para lançar o primeiro — normalmente o salário de '
                    'admissão.',
                altura: 150,
              );
            }
            return Column(
              children: [
                for (final h in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.trending_up_rounded, size: 20),
                    title: Text(
                      'R\$ ${h['salario'] ?? '—'} · ${h['motivo'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                        'Vigência: ${fmt.format(DateTime.parse(h['data_inicio'] as String))}'),
                    trailing: IconButton(
                      tooltip: 'Excluir registro',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Excluir registro salarial?'),
                            content:
                                const Text('Esta ação não pode ser desfeita.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancelar')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Excluir')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await ref
                            .read(peopleManagementServiceProvider)
                            .deleteHistoricoSalarial(h['id'] as String);
                        ref.invalidate(
                            historicoSalarialProvider(funcionarioId));
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    final salarioCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();
    var dataInicio = DateTime.now();
    var isLoading = false;
    final fmt = DateFormat('dd/MM/yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Registrar cargo/salário',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: salarioCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Salário (R\$)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: motivoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo (Contratação, Promoção, Dissídio...)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text('Vigência a partir de ${fmt.format(dataInicio)}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: dataInicio,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => dataInicio = d);
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final salario = salarioCtrl.text.trim();
                        final motivo = motivoCtrl.text.trim();
                        if (salario.isEmpty || motivo.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content: Text('Informe salário e motivo.')));
                          return;
                        }
                        setState(() => isLoading = true);
                        try {
                          await ref
                              .read(peopleManagementServiceProvider)
                              .addHistoricoSalarial(
                                funcionarioId: funcionarioId,
                                salario: salario,
                                dataInicio: dataInicio,
                                motivo: motivo,
                              );
                          ref.invalidate(
                              historicoSalarialProvider(funcionarioId));
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Erro: ${friendlyError(e)}')));
                          }
                        } finally {
                          if (ctx.mounted) setState(() => isLoading = false);
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator())
                    : const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DependentesSection extends ConsumerWidget {
  const DependentesSection({super.key, required this.funcionarioId});

  final String funcionarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dependentes = ref.watch(dependentesProvider(funcionarioId));
    final theme = Theme.of(context);
    final fmt = DateFormat('dd/MM/yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Dependentes',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar'),
              onPressed: () => _showAddSheet(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 8),
        dependentes.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Erro: ${friendlyError(e)}'),
          data: (list) {
            if (list.isEmpty) {
              return const HrEmptyBlock(
                icone: Icons.family_restroom,
                titulo: 'Nenhum dependente registrado',
                dica:
                    'Dependentes entram aqui com nome, parentesco e data de '
                    'nascimento. São eles que sustentam imposto de renda, '
                    'salário-família e a inclusão no plano de saúde.',
                altura: 150,
              );
            }
            return Column(
              children: [
                for (final d in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading:
                        const Icon(Icons.family_restroom_rounded, size: 20),
                    title: Text('${d['nome']} (${d['parentesco']})',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      'Nascimento: ${fmt.format(DateTime.parse(d['data_nascimento'] as String))}',
                      if ((d['cpf'] as String?)?.isNotEmpty == true)
                        'CPF: ${d['cpf']}',
                    ].join(' · ')),
                    trailing: IconButton(
                      tooltip: 'Remover',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Remover dependente?'),
                            content: Text('${d['nome']} será removido.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancelar')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Remover')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await ref
                            .read(peopleManagementServiceProvider)
                            .deleteDependente(d['id'] as String);
                        ref.invalidate(dependentesProvider(funcionarioId));
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    final nomeCtrl = TextEditingController();
    final cpfCtrl = TextEditingController();
    const parentescos = ['Filho(a)', 'Cônjuge', 'Pai/Mãe', 'Outro'];
    var parentesco = parentescos.first;
    DateTime? nascimento;
    var isLoading = false;
    final fmt = DateFormat('dd/MM/yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Adicionar dependente',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: nomeCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nome completo', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: parentesco,
                decoration: const InputDecoration(
                    labelText: 'Parentesco', border: OutlineInputBorder()),
                items: [
                  for (final p in parentescos)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (v) => setState(() => parentesco = v!),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.cake_outlined),
                label: Text(nascimento != null
                    ? 'Nascimento: ${fmt.format(nascimento!)}'
                    : 'Data de nascimento'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime(2010),
                    firstDate: DateTime(1930),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => nascimento = d);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: cpfCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'CPF (opcional)',
                  helperText: 'Armazenado criptografado por organização.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final nome = nomeCtrl.text.trim();
                        if (nome.isEmpty || nascimento == null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content:
                                  Text('Informe nome e data de nascimento.')));
                          return;
                        }
                        setState(() => isLoading = true);
                        try {
                          await ref
                              .read(peopleManagementServiceProvider)
                              .addDependente(
                                funcionarioId: funcionarioId,
                                nome: nome,
                                dataNascimento: nascimento!,
                                parentesco: parentesco,
                                cpf: cpfCtrl.text.trim().isEmpty
                                    ? null
                                    : cpfCtrl.text.trim(),
                              );
                          ref.invalidate(dependentesProvider(funcionarioId));
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Erro: ${friendlyError(e)}')));
                          }
                        } finally {
                          if (ctx.mounted) setState(() => isLoading = false);
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator())
                    : const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
