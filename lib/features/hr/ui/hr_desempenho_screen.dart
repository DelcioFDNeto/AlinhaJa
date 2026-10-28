import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/desempenho_model.dart';
import 'package:alinha_ja/features/hr/providers/people_management_provider.dart';
import 'package:alinha_ja/features/hr/ui/ciclos_tab.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// Fase 8 — Desempenho na visão do RH.
///
/// Duas frentes: os **ciclos** de avaliação (RH-27 — metas + 360) e o
/// registro avulso de avaliações 1:1/experiência que já existia (rh21).
class HrDesempenhoScreen extends ConsumerStatefulWidget {
  const HrDesempenhoScreen({super.key});

  @override
  ConsumerState<HrDesempenhoScreen> createState() =>
      _HrDesempenhoScreenState();
}

class _HrDesempenhoScreenState extends ConsumerState<HrDesempenhoScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Desempenho'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Ciclos'),
            Tab(text: 'Avaliações 1:1'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          CiclosTab(),
          _Avaliacoes1a1Tab(),
        ],
      ),
    );
  }
}

/// Registro avulso de avaliações (1:1, experiência, anual) — comportamento
/// original da tela, preservado.
class _Avaliacoes1a1Tab extends ConsumerStatefulWidget {
  const _Avaliacoes1a1Tab();

  @override
  ConsumerState<_Avaliacoes1a1Tab> createState() => _Avaliacoes1a1TabState();
}

class _Avaliacoes1a1TabState extends ConsumerState<_Avaliacoes1a1Tab> {
  String? _funcionarioId;

  @override
  Widget build(BuildContext context) {
    final avaliacoes = ref.watch(avaliacoesDesempenhoProvider(_funcionarioId));
    final canManage = ref.watch(rbacCanProvider((module: 'rh_desempenho', action: 'manage')));
    final funcionarios = ref.watch(funcionariosLiteProvider);

    return Scaffold(
      floatingActionButton: !canManage
          ? null
          : FloatingActionButton.extended(
        onPressed: () => _showForm(context),
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('Nova avaliação'),
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
            child: avaliacoes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
              data: (list) {
                if (list.isEmpty) {
                  return HrEmptyState(
                    icone: Icons.assignment_turned_in_outlined,
                    titulo: 'Nenhuma avaliação avulsa registrada',
                    descricao:
                        'Esta aba guarda avaliações pontuais — 1:1, fim de '
                        'experiência, feedback formal — que não dependem de '
                        'um ciclo aberto. Para metas e 360 do período, use a '
                        'aba Ciclos.',
                    passos: const [
                      'Toque em "Nova avaliação".',
                      'Escolha o funcionário, o tipo e a data.',
                      'Registre a nota e o parecer — fica no histórico da '
                          'ficha da pessoa.',
                    ],
                    acaoLabel: 'Nova avaliação',
                    acaoIcone: Icons.add,
                    onAcao: () => _showForm(context),
                    estrutura: const HrGhostList(
                      colunas: ['Funcionário', 'Tipo', 'Nota'],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => _AvaliacaoTile(
                    avaliacao: list[i],
                    onChanged: () => ref.invalidate(
                        avaliacoesDesempenhoProvider(_funcionarioId)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NovaAvaliacaoSheet(onSaved: () {
        ref.invalidate(avaliacoesDesempenhoProvider(_funcionarioId));
      }),
    );
  }
}

class _AvaliacaoTile extends ConsumerWidget {
  const _AvaliacaoTile({required this.avaliacao, required this.onChanged});

  final AvaliacaoDesempenhoModel avaliacao;
  final VoidCallback onChanged;

  StatusRole get _notaRole {
    final n = avaliacao.pontuacaoGeral;
    if (n == null) return StatusRole.neutral;
    if (n >= 70) return StatusRole.success;
    if (n >= 40) return StatusRole.warning;
    return StatusRole.danger;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canManage = ref.watch(rbacCanProvider((module: 'rh_desempenho', action: 'manage')));
    final fmt = DateFormat('dd/MM/yyyy');
    final notaColor = context.statusTokens.color(_notaRole);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: notaColor.withValues(alpha: 0.15),
          child: Text(
            avaliacao.pontuacaoGeral?.toStringAsFixed(0) ?? '—',
            style: TextStyle(
                color: notaColor, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        title: Text(
          '${avaliacao.funcionarioNome ?? 'Funcionário'} · ${avaliacao.tipo}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Avaliada em ${fmt.format(avaliacao.dataAvaliacao)}'),
            if (avaliacao.feedbackTexto?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  avaliacao.feedbackTexto!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
        trailing: !canManage
            ? null
            : IconButton(
          tooltip: 'Excluir',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Excluir avaliação?'),
                content: const Text('Esta ação não pode ser desfeita.'),
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
                .deleteAvaliacao(avaliacao.id);
            onChanged();
          },
        ),
      ),
    );
  }
}

class _NovaAvaliacaoSheet extends ConsumerStatefulWidget {
  const _NovaAvaliacaoSheet({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_NovaAvaliacaoSheet> createState() =>
      _NovaAvaliacaoSheetState();
}

class _NovaAvaliacaoSheetState extends ConsumerState<_NovaAvaliacaoSheet> {
  static const _tipos = [
    '1:1',
    'Experiência 45 dias',
    'Experiência 90 dias',
    'Semestral',
    'Anual',
    'Feedback 360',
  ];

  String? _funcionarioId;
  String _tipo = _tipos.first;
  DateTime _data = DateTime.now();
  double _pontuacao = 70;
  final _feedbackCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _submit() async {
    if (_funcionarioId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione o funcionário.')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(peopleManagementServiceProvider).createAvaliacao(
            funcionarioId: _funcionarioId!,
            tipo: _tipo,
            dataAvaliacao: _data,
            pontuacao: _pontuacao,
            feedback: _feedbackCtrl.text.trim().isEmpty
                ? null
                : _feedbackCtrl.text.trim(),
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
    final fmt = DateFormat('dd/MM/yyyy');

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nova avaliação de desempenho',
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
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(
                  labelText: 'Tipo de ciclo', border: OutlineInputBorder()),
              items: [
                for (final t in _tipos)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => setState(() => _tipo = v!),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text('Avaliada em ${fmt.format(_data)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _data,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _data = d);
              },
            ),
            const SizedBox(height: 16),
            Text('Pontuação geral: ${_pontuacao.toStringAsFixed(0)} / 100'),
            Slider(
              value: _pontuacao,
              max: 100,
              divisions: 100,
              label: _pontuacao.toStringAsFixed(0),
              onChanged: (v) => setState(() => _pontuacao = v),
            ),
            TextField(
              controller: _feedbackCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Feedback / observações',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator())
                  : const Text('Registrar avaliação'),
            ),
          ],
        ),
      ),
    );
  }
}
