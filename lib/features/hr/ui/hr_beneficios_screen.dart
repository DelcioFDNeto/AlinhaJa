import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/features/hr/models/beneficio_model.dart';
import 'package:alinha_ja/features/hr/providers/people_management_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// Fase 8 — Benefícios (visão do RH): catálogo de benefícios da org
/// (plano de saúde, VA/VR, VT...) e adesões por funcionário com
/// desconto em folha cifrado (RPCs rh_add_adesao_beneficio /
/// rh_list_adesoes_beneficio).
class HrBeneficiosScreen extends ConsumerWidget {
  const HrBeneficiosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Benefícios'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Catálogo'),
            Tab(text: 'Adesões'),
          ]),
        ),
        body: const TabBarView(children: [
          _CatalogoTab(),
          _AdesoesTab(),
        ]),
      ),
    );
  }
}

// ── Catálogo ─────────────────────────────────────────────────

class _CatalogoTab extends ConsumerWidget {
  const _CatalogoTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final beneficios = ref.watch(beneficiosProvider);
    final theme = Theme.of(context);
    final canManage = ref.watch(rbacCanProvider((module: 'rh_beneficios', action: 'manage')));

    return Scaffold(
      floatingActionButton: !canManage
          ? null
          : FloatingActionButton.extended(
        heroTag: 'novo_beneficio',
        onPressed: () => _showForm(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Novo benefício'),
      ),
      body: beneficios.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
        data: (list) {
          if (list.isEmpty) {
            return HrEmptyState(
              icone: Icons.card_giftcard_outlined,
              titulo: 'Nenhum benefício cadastrado',
              descricao:
                  'O catálogo é a lista de benefícios que a empresa oferece '
                  '(plano de saúde, VA/VR, VT, seguro). Ele existe primeiro; '
                  'depois cada funcionário adere ao que lhe cabe, na aba '
                  'Adesões.',
              passos: const [
                'Cadastre o benefício com nome, tipo e valor de referência.',
                'Repita para cada benefício que a empresa oferece.',
                'Vá à aba Adesões e vincule os funcionários — o desconto '
                    'em folha é gravado cifrado.',
              ],
              acaoLabel: 'Cadastrar primeiro benefício',
              acaoIcone: Icons.add,
              onAcao: () => _showForm(context, ref, null),
              estrutura: const HrGhostList(
                comAvatar: false,
                colunas: ['Benefício', 'Tipo', 'Valor'],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final b = list[i];
              return Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: const Icon(Icons.card_giftcard_outlined),
                  title: Text(b.nome,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    b.tipo,
                    if (b.fornecedor?.isNotEmpty == true) b.fornecedor!,
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusBadge(
                        label: b.ativo ? 'Ativo' : 'Inativo',
                        role:
                            b.ativo ? StatusRole.success : StatusRole.neutral,
                      ),
                      if (canManage)
                      IconButton(
                        tooltip: 'Editar',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showForm(context, ref, b),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showForm(BuildContext context, WidgetRef ref, BeneficioModel? b) {
    final nomeCtrl = TextEditingController(text: b?.nome ?? '');
    final fornecedorCtrl = TextEditingController(text: b?.fornecedor ?? '');
    const tipos = ['Saúde', 'Odonto', 'VA', 'VR', 'VT', 'Seguro de Vida', 'Outro'];
    var tipo = tipos.contains(b?.tipo) ? b!.tipo : tipos.first;
    var ativo = b?.ativo ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(b == null ? 'Novo benefício' : 'Editar benefício'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nome (ex: Plano Unimed)'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: tipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: [
                    for (final t in tipos)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setState(() => tipo = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: fornecedorCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Fornecedor (opcional)'),
                ),
                if (b != null) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Benefício ativo'),
                    value: ativo,
                    onChanged: (v) => setState(() => ativo = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final nome = nomeCtrl.text.trim();
                if (nome.isEmpty) return;
                final service = ref.read(peopleManagementServiceProvider);
                if (b == null) {
                  await service.createBeneficio(
                    nome: nome,
                    tipo: tipo,
                    fornecedor: fornecedorCtrl.text.trim().isEmpty
                        ? null
                        : fornecedorCtrl.text.trim(),
                  );
                } else {
                  await service.updateBeneficio(
                    b.id,
                    nome: nome,
                    tipo: tipo,
                    fornecedor: fornecedorCtrl.text.trim(),
                    ativo: ativo,
                  );
                }
                ref.invalidate(beneficiosProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Adesões ──────────────────────────────────────────────────

class _AdesoesTab extends ConsumerStatefulWidget {
  const _AdesoesTab();

  @override
  ConsumerState<_AdesoesTab> createState() => _AdesoesTabState();
}

class _AdesoesTabState extends ConsumerState<_AdesoesTab> {
  String? _funcionarioId;

  @override
  Widget build(BuildContext context) {
    final adesoes = ref.watch(adesoesProvider(_funcionarioId));
    final canManage = ref.watch(rbacCanProvider((module: 'rh_beneficios', action: 'manage')));
    final funcionarios = ref.watch(funcionariosLiteProvider);
    final theme = Theme.of(context);
    final fmt = DateFormat('dd/MM/yyyy');

    return Scaffold(
      floatingActionButton: !canManage
          ? null
          : FloatingActionButton.extended(
        heroTag: 'nova_adesao',
        onPressed: () => _showAdesaoSheet(context),
        icon: const Icon(Icons.person_add_alt_outlined),
        label: const Text('Nova adesão'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
                  const DropdownMenuItem(value: null, child: Text('Todos')),
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
          Expanded(
            child: adesoes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
              data: (list) {
                if (list.isEmpty) {
                  return const HrEmptyState(
                    icone: Icons.badge_outlined,
                    titulo: 'Nenhuma adesão registrada',
                    descricao:
                        'A adesão liga um funcionário a um benefício do '
                        'catálogo e define o desconto em folha dele.',
                    passos: [
                      'Escolha o funcionário no seletor acima.',
                      'Toque em "Nova adesão" e escolha o benefício do '
                          'catálogo.',
                      'Informe o valor descontado — ele é gravado cifrado e '
                          'só aparece para quem tem permissão de RH.',
                    ],
                    nota: 'Se o catálogo estiver vazio, cadastre os '
                        'benefícios na primeira aba antes de vincular alguém.',
                    estrutura: HrGhostList(
                      colunas: ['Funcionário', 'Benefício', 'Desconto'],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final a = list[i];
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: theme.colorScheme.outlineVariant),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: Text(
                          '${a.beneficioNome} · ${a.funcionarioNome ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text([
                          'Adesão: ${fmt.format(a.dataAdesao)}',
                          if (a.dataCancelamento != null)
                            'Cancelada: ${fmt.format(a.dataCancelamento!)}',
                          if (a.valorDesconto?.isNotEmpty == true)
                            'Desconto: R\$ ${a.valorDesconto}',
                        ].join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusBadge(
                              label: a.ativa ? 'Ativa' : 'Cancelada',
                              role: a.ativa
                                  ? StatusRole.success
                                  : StatusRole.neutral,
                            ),
                            if (a.ativa && canManage)
                              IconButton(
                                tooltip: 'Cancelar adesão',
                                icon: const Icon(Icons.cancel_outlined),
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Cancelar adesão?'),
                                      content: Text(
                                          'A adesão de ${a.funcionarioNome ?? 'funcionário'} a ${a.beneficioNome} será encerrada hoje.'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Voltar')),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('Cancelar adesão')),
                                      ],
                                    ),
                                  );
                                  if (ok != true) return;
                                  await ref
                                      .read(peopleManagementServiceProvider)
                                      .cancelarAdesao(a.id);
                                  ref.invalidate(adesoesProvider);
                                },
                              ),
                          ],
                        ),
                      ),
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

  void _showAdesaoSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NovaAdesaoSheet(onSaved: () {
        ref.invalidate(adesoesProvider);
      }),
    );
  }
}

class _NovaAdesaoSheet extends ConsumerStatefulWidget {
  const _NovaAdesaoSheet({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_NovaAdesaoSheet> createState() => _NovaAdesaoSheetState();
}

class _NovaAdesaoSheetState extends ConsumerState<_NovaAdesaoSheet> {
  String? _funcionarioId;
  String? _beneficioId;
  DateTime _dataAdesao = DateTime.now();
  final _descontoCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _submit() async {
    if (_funcionarioId == null || _beneficioId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecione o funcionário e o benefício.')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(peopleManagementServiceProvider).addAdesao(
            funcionarioId: _funcionarioId!,
            beneficioId: _beneficioId!,
            dataAdesao: _dataAdesao,
            valorDesconto: _descontoCtrl.text.trim().isEmpty
                ? null
                : _descontoCtrl.text.trim(),
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
    final beneficios = ref.watch(beneficiosProvider);
    final fmt = DateFormat('dd/MM/yyyy');

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
          const Text('Nova adesão',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
          beneficios.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Erro: ${friendlyError(e)}'),
            data: (list) {
              final ativos = list.where((b) => b.ativo).toList();
              return DropdownButtonFormField<String>(
                initialValue: _beneficioId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Benefício', border: OutlineInputBorder()),
                items: [
                  for (final b in ativos)
                    DropdownMenuItem(
                        value: b.id,
                        child: Text('${b.nome} (${b.tipo})',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _beneficioId = v),
              );
            },
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text('Adesão em ${fmt.format(_dataAdesao)}'),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _dataAdesao,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 60)),
              );
              if (d != null) setState(() => _dataAdesao = d);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descontoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Desconto em folha (R\$, opcional)',
              helperText: 'Armazenado criptografado por organização.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator())
                : const Text('Registrar adesão'),
          ),
        ],
      ),
    );
  }
}
