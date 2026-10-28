import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/features/hr/models/desempenho_model.dart';
import 'package:alinha_ja/features/hr/providers/desempenho_provider.dart';
import 'package:alinha_ja/features/hr/ui/ciclo_detail_screen.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_responsive.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-27 — lista de ciclos de avaliação (visão do RH).
class CiclosTab extends ConsumerWidget {
  const CiclosTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ciclosProvider);
    final canManage = ref.watch(rbacCanProvider((module: 'rh_desempenho', action: 'manage')));

    return Scaffold(
      floatingActionButton: !canManage
          ? null
          : FloatingActionButton.extended(
        onPressed: () => _editar(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo ciclo'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
        data: (ciclos) {
          if (ciclos.isEmpty) {
            return HrEmptyState(
              icone: Icons.donut_large,
              titulo: 'Nenhum ciclo de avaliação',
              descricao:
                  'Um ciclo é o período de avaliação da empresa — semestre, '
                  'ano, safra. Ele agrupa as metas de cada pessoa e as '
                  'avaliações 360 daquele intervalo; sem um ciclo aberto, o '
                  'colaborador não vê nada em "Meu desempenho".',
              passos: const [
                'Crie o ciclo com nome e as datas de início e fim.',
                'Dentro do ciclo, cadastre as metas de cada pessoa.',
                'Abra o ciclo para avaliação: gestor, pares e a própria '
                    'pessoa passam a responder o 360.',
                'Feche o ciclo quando o período terminar — o resultado fica '
                    'no histórico de cada funcionário.',
              ],
              acaoLabel: 'Criar primeiro ciclo',
              acaoIcone: Icons.add,
              onAcao: () => _editar(context, ref),
              estrutura: const HrGhostList(
                comAvatar: false,
                colunas: ['Ciclo', 'Período', 'Situação'],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(ciclosProvider),
            child: HrContentColumn(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 96),
                children: [
                  for (final c in ciclos)
                    _CicloCard(
                      ciclo: c,
                      onAbrir: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CicloDetailScreen(ciclo: c),
                        ),
                      ),
                      onEditar: () => _editar(context, ref, c),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _editar(BuildContext context, WidgetRef ref,
      [CicloAvaliacao? ciclo]) async {
    final salvo = await showHrFormSheet<bool>(
      context: context,
      builder: (_) => _CicloFormSheet(ciclo: ciclo),
    );
    if (salvo == true) ref.invalidate(ciclosProvider);
  }
}

class _CicloCard extends ConsumerWidget {
  const _CicloCard({
    required this.ciclo,
    required this.onAbrir,
    required this.onEditar,
  });

  final CicloAvaliacao ciclo;
  final VoidCallback onAbrir;
  final VoidCallback onEditar;

  static final _data = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canManage = ref.watch(rbacCanProvider((module: 'rh_desempenho', action: 'manage')));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onAbrir,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(ciclo.nome,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge(
                      label: _statusLabel(ciclo.status),
                      role: _statusRole(ciclo.status)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_data.format(ciclo.periodoInicio)} — ${_data.format(ciclo.periodoFim)}',
                style:
                    TextStyle(fontSize: 12.5, color: theme.colorScheme.outline),
              ),
              if ((ciclo.descricao ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(ciclo.descricao!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: theme.colorScheme.outline)),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in ciclo.origens)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(Origem360.label(o),
                          style: const TextStyle(fontSize: 11.5)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Ações quebram para a linha de baixo em telas estreitas.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  if (canManage)
                    TextButton(onPressed: onEditar, child: const Text('Editar')),
                  if (canManage && ciclo.rascunho)
                    FilledButton.tonal(
                      onPressed: () => _mudarStatus(context, ref, 'aberto'),
                      child: const Text('Abrir ciclo'),
                    ),
                  if (canManage && ciclo.aberto)
                    FilledButton.tonal(
                      onPressed: () => _confirmarEncerrar(context, ref),
                      child: const Text('Encerrar'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmarEncerrar(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar ciclo?'),
        content: const Text(
            'Depois de encerrado, ninguém mais consegue responder as '
            'avaliações pendentes. Os resultados já enviados continuam '
            'disponíveis.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Encerrar')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _mudarStatus(context, ref, 'encerrado');
    }
  }

  Future<void> _mudarStatus(
      BuildContext context, WidgetRef ref, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(desempenhoServiceProvider)
          .mudarStatusCiclo(ciclo.id, status);
      ref.invalidate(ciclosProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  static String _statusLabel(String s) => switch (s) {
        'aberto' => 'ABERTO',
        'encerrado' => 'ENCERRADO',
        _ => 'RASCUNHO',
      };

  static StatusRole _statusRole(String s) => switch (s) {
        'aberto' => StatusRole.success,
        'encerrado' => StatusRole.neutral,
        _ => StatusRole.warning,
      };
}

/// Criação/edição de ciclo.
class _CicloFormSheet extends ConsumerStatefulWidget {
  const _CicloFormSheet({this.ciclo});

  final CicloAvaliacao? ciclo;

  @override
  ConsumerState<_CicloFormSheet> createState() => _CicloFormSheetState();
}

class _CicloFormSheetState extends ConsumerState<_CicloFormSheet> {
  late final _nome = TextEditingController(text: widget.ciclo?.nome ?? '');
  late final _descricao =
      TextEditingController(text: widget.ciclo?.descricao ?? '');
  late DateTime _inicio = widget.ciclo?.periodoInicio ??
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _fim = widget.ciclo?.periodoFim ??
      DateTime(DateTime.now().year, DateTime.now().month + 3, 0);
  late DateTime? _prazo = widget.ciclo?.prazoResposta;
  late bool _auto = widget.ciclo?.usaAuto ?? true;
  late bool _gestor = widget.ciclo?.usaGestor ?? true;
  late bool _pares = widget.ciclo?.usaPares ?? true;
  late bool _subordinado = widget.ciclo?.usaSubordinado ?? false;
  late double _minPares =
      (widget.ciclo?.minParesAnonimato ?? 3).toDouble();
  bool _salvando = false;

  static final _data = DateFormat('dd/MM/yyyy');

  bool get _edicao => widget.ciclo != null;

  @override
  void dispose() {
    _nome.dispose();
    _descricao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_edicao ? 'Editar ciclo' : 'Novo ciclo de avaliação',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _nome,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome *',
                hintText: 'Ex.: Avaliação Anual 2026',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descricao,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            HrFieldRow(
              children: [
                _BotaoData(
                  rotulo: 'Início',
                  valor: _inicio,
                  onEscolher: (d) => setState(() {
                    _inicio = d;
                    if (_fim.isBefore(d)) _fim = d;
                  }),
                ),
                _BotaoData(
                  rotulo: 'Fim',
                  valor: _fim,
                  primeiraData: _inicio,
                  onEscolher: (d) => setState(() => _fim = d),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_available),
              label: Text(_prazo == null
                  ? 'Prazo para responder (opcional)'
                  : 'Responder até ${_data.format(_prazo!)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _prazo ?? _fim,
                  firstDate: _inicio,
                  lastDate: DateTime(_fim.year + 1),
                );
                if (d != null) setState(() => _prazo = d);
              },
            ),
            const SizedBox(height: 16),
            Text('Origens de feedback', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            _Origem(
              valor: _auto,
              titulo: 'Autoavaliação',
              onChanged: (v) => setState(() => _auto = v),
            ),
            _Origem(
              valor: _gestor,
              titulo: 'Gestor',
              onChanged: (v) => setState(() => _gestor = v),
            ),
            _Origem(
              valor: _pares,
              titulo: 'Pares',
              onChanged: (v) => setState(() => _pares = v),
            ),
            _Origem(
              valor: _subordinado,
              titulo: 'Subordinados',
              onChanged: (v) => setState(() => _subordinado = v),
            ),
            if (_pares) ...[
              const SizedBox(height: 12),
              Text('Mínimo de respostas de pares: ${_minPares.round()}',
                  style: theme.textTheme.titleSmall),
              Text(
                'Abaixo desse número, a média de pares fica oculta para o '
                'avaliado — com poucas respostas dá para adivinhar quem '
                'escreveu.',
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.outline),
              ),
              Slider(
                value: _minPares,
                min: 1,
                max: 10,
                divisions: 9,
                label: '${_minPares.round()}',
                onChanged: (v) => setState(() => _minPares = v),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _salvando ? null : _salvar,
              child: _salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _salvar() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (_nome.text.trim().length < 3) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Dê um nome ao ciclo (mínimo 3 caracteres).')));
      return;
    }
    if (!_auto && !_gestor && !_pares && !_subordinado) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Escolha ao menos uma origem de feedback.')));
      return;
    }

    setState(() => _salvando = true);
    try {
      await ref.read(desempenhoServiceProvider).salvarCiclo(
            id: widget.ciclo?.id,
            nome: _nome.text,
            descricao: _descricao.text,
            periodoInicio: _inicio,
            periodoFim: _fim,
            prazoResposta: _prazo,
            usaAuto: _auto,
            usaGestor: _gestor,
            usaPares: _pares,
            usaSubordinado: _subordinado,
            minParesAnonimato: _minPares.round(),
          );
      navigator.pop(true);
    } catch (e) {
      if (mounted) setState(() => _salvando = false);
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }
}

class _Origem extends StatelessWidget {
  const _Origem({
    required this.valor,
    required this.titulo,
    required this.onChanged,
  });

  final bool valor;
  final String titulo;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: valor,
      title: Text(titulo),
      onChanged: (v) => onChanged(v ?? false),
    );
  }
}

class _BotaoData extends StatelessWidget {
  const _BotaoData({
    required this.rotulo,
    required this.valor,
    required this.onEscolher,
    this.primeiraData,
  });

  final String rotulo;
  final DateTime valor;
  final ValueChanged<DateTime> onEscolher;
  final DateTime? primeiraData;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today, size: 18),
      label: Text('$rotulo: ${DateFormat('dd/MM/yy').format(valor)}',
          overflow: TextOverflow.ellipsis),
      onPressed: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: valor,
          firstDate: primeiraData ?? DateTime(valor.year - 2),
          lastDate: DateTime(valor.year + 3),
        );
        if (d != null) onEscolher(d);
      },
    );
  }
}
