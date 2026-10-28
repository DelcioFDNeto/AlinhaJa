import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/desempenho_model.dart';
import 'package:alinha_ja/features/hr/models/employee_model.dart';
import 'package:alinha_ja/features/hr/providers/desempenho_provider.dart';
import 'package:alinha_ja/features/hr/providers/employee_provider.dart';
import 'package:alinha_ja/features/hr/providers/talent_bank_provider.dart'
    show orgUsersProvider;
import 'package:alinha_ja/features/hr/ui/my_performance_screen.dart' show MetaCard;
import 'package:alinha_ja/features/hr/ui/widgets/hr_responsive.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-27 — detalhe de um ciclo: consolidado das avaliações 360 e metas.
class CicloDetailScreen extends ConsumerStatefulWidget {
  const CicloDetailScreen({super.key, required this.ciclo});

  final CicloAvaliacao ciclo;

  @override
  ConsumerState<CicloDetailScreen> createState() => _CicloDetailScreenState();
}

class _CicloDetailScreenState extends ConsumerState<CicloDetailScreen>
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
        title: Text(widget.ciclo.nome, overflow: TextOverflow.ellipsis),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Resultados'),
            Tab(text: 'Metas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ResultadosTab(ciclo: widget.ciclo),
          _MetasTab(ciclo: widget.ciclo),
        ],
      ),
    );
  }
}

// ── Resultados (consolidado 360) ─────────────────────────────

class _ResultadosTab extends ConsumerWidget {
  const _ResultadosTab({required this.ciclo});

  final CicloAvaliacao ciclo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(consolidadoCicloProvider(ciclo.id));

    return Scaffold(
      floatingActionButton: ciclo.encerrado || !ref.watch(rbacCanProvider((module: 'rh_desempenho', action: 'manage')))
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _convidar(context, ref),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Convidar avaliador'),
            ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
        data: (lista) {
          if (lista.isEmpty) {
            return Center(
              child: HrContentColumn(
                maxWidth: 430,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 72),
                    Icon(Icons.groups_outlined,
                        size: 56, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text('Ninguém convidado ainda',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Convide os avaliadores de cada pessoa. Cada convite '
                      'vira uma tarefa em "Meu Desempenho" de quem vai avaliar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(consolidadoCicloProvider(ciclo.id)),
            child: HrContentColumn(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 96),
                children: [
                  for (final r in lista) _ConsolidadoCard(resultado: r),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _convidar(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await showHrFormSheet<_ConviteDados>(
      context: context,
      builder: (_) => _ConvidarSheet(ciclo: ciclo),
    );
    if (res == null) return;
    try {
      await ref.read(desempenhoServiceProvider).convidar(
            cicloId: ciclo.id,
            avaliadoId: res.avaliadoId,
            avaliadorUserId: res.avaliadorUserId,
            origem: res.origem,
          );
      ref.invalidate(consolidadoCicloProvider(ciclo.id));
      messenger.showSnackBar(const SnackBar(content: Text('Convite criado.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          duration: const Duration(seconds: 6)));
    }
  }
}

class _ConsolidadoCard extends StatelessWidget {
  const _ConsolidadoCard({required this.resultado});

  final DesempenhoConsolidado resultado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final r = resultado;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(r.avaliadoNome,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Text(
                  r.notaGeral?.toStringAsFixed(1) ?? '—',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: r.taxaResposta,
                      minHeight: 5,
                      color: r.respondidas == r.convites ? tokens.success : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${r.respondidas}/${r.convites} respostas',
                    style: TextStyle(
                        fontSize: 11.5, color: theme.colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 12),
            // Notas por origem: fluem em Wrap, sem tabela rígida.
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _Mini(rotulo: 'Auto', valor: r.notaAuto),
                _Mini(rotulo: 'Gestor', valor: r.notaGestor),
                _Mini(rotulo: 'Pares', valor: r.notaPares),
                if (r.notaSubordinados != null)
                  _Mini(rotulo: 'Subord.', valor: r.notaSubordinados),
                if (r.progressoMetas != null)
                  _Mini(
                      rotulo: 'Metas',
                      valor: r.progressoMetas,
                      sufixo: '%'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.rotulo, required this.valor, this.sufixo = ''});

  final String rotulo;
  final double? valor;
  final String sufixo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(valor == null ? '—' : '${valor!.toStringAsFixed(1)}$sufixo',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Text(rotulo,
            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
      ],
    );
  }
}

/// Dados escolhidos no sheet de convite.
class _ConviteDados {
  final String avaliadoId;
  final String avaliadorUserId;
  final String origem;

  const _ConviteDados(this.avaliadoId, this.avaliadorUserId, this.origem);
}

/// Escolhe quem será avaliado, quem avalia e em que papel.
class _ConvidarSheet extends ConsumerStatefulWidget {
  const _ConvidarSheet({required this.ciclo});

  final CicloAvaliacao ciclo;

  @override
  ConsumerState<_ConvidarSheet> createState() => _ConvidarSheetState();
}

class _ConvidarSheetState extends ConsumerState<_ConvidarSheet> {
  EmployeeModel? _avaliado;
  String? _avaliadorUserId;
  late String _origem = widget.ciclo.origens.first;
  String _buscaAvaliado = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final funcionarios = ref.watch(_buscaFuncionarios(_buscaAvaliado));
    // Todos os usuários da org: o avaliador quase sempre já tem ficha
    // vinculada, então linkableUsersProvider (só não-vinculados) não serve.
    final usuarios = ref.watch(orgUsersProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Convidar avaliador', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),

            // 1. Quem será avaliado
            Text('1. Quem será avaliado', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_avaliado != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_avaliado!.nome),
                trailing: TextButton(
                  onPressed: () => setState(() => _avaliado = null),
                  child: const Text('Trocar'),
                ),
              )
            else ...[
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar funcionário',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) =>
                    setState(() => _buscaAvaliado = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: funcionarios.when(
                  loading: () => const Center(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator())),
                  error: (e, _) => Text('Erro: ${friendlyError(e)}'),
                  data: (lista) => ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in lista)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(f.nome),
                          onTap: () => setState(() => _avaliado = f),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // 2. Papel do avaliador
            Text('2. Papel de quem avalia', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _origem,
              isExpanded: true,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true),
              items: [
                for (final o in widget.ciclo.origens)
                  DropdownMenuItem(value: o, child: Text(Origem360.label(o))),
              ],
              onChanged: (v) => setState(() => _origem = v ?? _origem),
            ),
            if (_origem == 'auto')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Na autoavaliação o avaliador é o próprio avaliado — o '
                  'usuário vinculado à ficha dele.',
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.outline),
                ),
              ),
            const SizedBox(height: 16),

            // 3. Quem avalia (não se aplica à autoavaliação)
            if (_origem != 'auto') ...[
              Text('3. Quem vai avaliar', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              usuarios.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Erro: ${friendlyError(e)}'),
                data: (lista) => DropdownButtonFormField<String>(
                  initialValue: _avaliadorUserId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Usuário do app',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final u in lista)
                      DropdownMenuItem(
                        value: u['id'] as String,
                        child: Text(
                          (u['full_name'] as String?)?.trim().isNotEmpty == true
                              ? u['full_name'] as String
                              : (u['email'] as String? ?? 'Sem nome'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _avaliadorUserId = v),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Só quem tem login no app pode responder.',
                style:
                    TextStyle(fontSize: 12, color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
            ],

            FilledButton(
              onPressed: _podeSalvar ? _confirmar : null,
              child: const Text('Criar convite'),
            ),
          ],
        ),
      ),
    );
  }

  bool get _podeSalvar {
    if (_avaliado == null) return false;
    if (_origem == 'auto') return _avaliado!.userId != null;
    return _avaliadorUserId != null;
  }

  void _confirmar() {
    // Autoavaliação: o avaliador é o usuário vinculado ao próprio avaliado.
    final avaliador =
        _origem == 'auto' ? _avaliado!.userId! : _avaliadorUserId!;
    Navigator.pop(
        context, _ConviteDados(_avaliado!.id, avaliador, _origem));
  }
}

/// Busca de funcionários server-side para o sheet de convite.
final _buscaFuncionarios = FutureProvider.autoDispose
    .family<List<EmployeeModel>, String>((ref, termo) {
  return ref.watch(employeeServiceProvider).fetchEmployees(search: termo);
});

// ── Metas do ciclo ───────────────────────────────────────────

class _MetasTab extends ConsumerWidget {
  const _MetasTab({required this.ciclo});

  final CicloAvaliacao ciclo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(metasDoCicloProvider(ciclo.id));

    return Scaffold(
      floatingActionButton: ciclo.encerrado || !ref.watch(rbacCanProvider((module: 'rh_desempenho', action: 'manage')))
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _novaMeta(context, ref),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Nova meta'),
            ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
        data: (metas) {
          if (metas.isEmpty) {
            return HrEmptyState(
              icone: Icons.flag_outlined,
              titulo: 'Nenhuma meta neste ciclo',
              descricao:
                  'A meta é o combinado do período: o que aquela pessoa '
                  'precisa entregar e como isso será medido. É o que o '
                  'colaborador acompanha em "Meu desempenho" e o que sustenta '
                  'a nota do ciclo.',
              passos: ciclo.encerrado
                  ? const [
                      'Este ciclo já foi encerrado e não aceita metas novas.',
                      'Abra um novo ciclo para o próximo período.',
                    ]
                  : const [
                      'Toque em "Nova meta" e escolha o funcionário.',
                      'Descreva a entrega, o indicador e o valor esperado.',
                      'Defina o peso da meta — ele distribui a nota final '
                          'entre as entregas.',
                      'Ao longo do ciclo, atualize o progresso de cada meta.',
                    ],
              acaoLabel: ciclo.encerrado ? null : 'Cadastrar primeira meta',
              acaoIcone: Icons.flag_outlined,
              onAcao: ciclo.encerrado ? null : () => _novaMeta(context, ref),
              estrutura: const HrGhostList(
                colunas: ['Funcionário', 'Meta', 'Progresso'],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(metasDoCicloProvider(ciclo.id)),
            child: HrContentColumn(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 96),
                children: [
                  for (final m in metas)
                    MetaCard(meta: m, editavel: true, mostrarNome: true),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _novaMeta(BuildContext context, WidgetRef ref) async {
    final salvo = await showHrFormSheet<bool>(
      context: context,
      builder: (_) => _MetaFormSheet(cicloId: ciclo.id),
    );
    if (salvo == true) ref.invalidate(metasDoCicloProvider(ciclo.id));
  }
}

class _MetaFormSheet extends ConsumerStatefulWidget {
  const _MetaFormSheet({required this.cicloId});

  final String cicloId;

  @override
  ConsumerState<_MetaFormSheet> createState() => _MetaFormSheetState();
}

class _MetaFormSheetState extends ConsumerState<_MetaFormSheet> {
  final _titulo = TextEditingController();
  final _descricao = TextEditingController();
  final _metrica = TextEditingController();
  final _alvo = TextEditingController();
  EmployeeModel? _funcionario;
  String _busca = '';
  double _peso = 1;
  DateTime? _prazo;
  bool _salvando = false;

  @override
  void dispose() {
    _titulo.dispose();
    _descricao.dispose();
    _metrica.dispose();
    _alvo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final funcionarios = ref.watch(_buscaFuncionarios(_busca));

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nova meta', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            if (_funcionario != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_funcionario!.nome),
                trailing: TextButton(
                  onPressed: () => setState(() => _funcionario = null),
                  child: const Text('Trocar'),
                ),
              )
            else ...[
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Funcionário *',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) =>
                    setState(() => _busca = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: funcionarios.when(
                  loading: () => const Center(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator())),
                  error: (e, _) => Text('Erro: ${friendlyError(e)}'),
                  data: (lista) => ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in lista)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(f.nome),
                          onTap: () => setState(() => _funcionario = f),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _titulo,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Meta *',
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
                TextField(
                  controller: _metrica,
                  decoration: const InputDecoration(
                    labelText: 'Métrica',
                    hintText: 'Ex.: NPS',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                TextField(
                  controller: _alvo,
                  decoration: const InputDecoration(
                    labelText: 'Alvo',
                    hintText: 'Ex.: 70',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Peso: ${_peso.round()}', style: theme.textTheme.titleSmall),
            Text(
              'Metas com peso maior contam mais no progresso consolidado.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            Slider(
              value: _peso,
              min: 1,
              max: 10,
              divisions: 9,
              label: '${_peso.round()}',
              onChanged: (v) => setState(() => _peso = v),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 18),
              label: Text(_prazo == null
                  ? 'Prazo (opcional)'
                  : 'Prazo: ${DateFormat('dd/MM/yyyy').format(_prazo!)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _prazo ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (d != null) setState(() => _prazo = d);
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _salvando ? null : _salvar,
              child: _salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar meta'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _salvar() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (_funcionario == null || _titulo.text.trim().length < 3) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Escolha o funcionário e descreva a meta.')));
      return;
    }
    setState(() => _salvando = true);
    try {
      await ref.read(desempenhoServiceProvider).salvarMeta(
            cicloId: widget.cicloId,
            funcionarioId: _funcionario!.id,
            titulo: _titulo.text,
            descricao: _descricao.text,
            metrica: _metrica.text,
            alvo: _alvo.text,
            peso: _peso.round(),
            prazo: _prazo,
          );
      navigator.pop(true);
    } catch (e) {
      if (mounted) setState(() => _salvando = false);
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }
}
