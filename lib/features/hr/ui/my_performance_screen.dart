import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/desempenho_model.dart';
import 'package:alinha_ja/features/hr/providers/desempenho_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_responsive.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-27 / Fase 8 — desempenho na visão do funcionário.
///
/// Três coisas: as avaliações que ele precisa responder (inclusive a
/// autoavaliação), as próprias metas e o resultado consolidado — este
/// último sempre anonimizado pelo servidor.
class MyPerformanceScreen extends ConsumerStatefulWidget {
  const MyPerformanceScreen({super.key});

  @override
  ConsumerState<MyPerformanceScreen> createState() =>
      _MyPerformanceScreenState();
}

class _MyPerformanceScreenState extends ConsumerState<MyPerformanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendentes = ref.watch(convites360PendentesProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Desempenho'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('A responder'),
                  if (pendentes > 0) ...[
                    const SizedBox(width: 6),
                    _Selo(texto: '$pendentes'),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Minhas metas'),
            const Tab(text: 'Meu resultado'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _ConvitesTab(),
          _MinhasMetasTab(),
          _MeuResultadoTab(),
        ],
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  const _Selo({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final tokens = context.statusTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.warning,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(texto,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}

// ── Convites a responder ─────────────────────────────────────

class _ConvitesTab extends ConsumerWidget {
  const _ConvitesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(meusConvites360Provider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
      data: (convites) {
        if (convites.isEmpty) {
          return const _Vazio(
            icone: Icons.how_to_reg,
            titulo: 'Nada para avaliar',
            texto: 'Quando o RH abrir um ciclo e convidar você, as avaliações '
                'aparecem aqui.',
          );
        }
        final pendentes = convites.where((c) => c.podeResponder).toList();
        final feitas = convites.where((c) => !c.podeResponder).toList();

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(meusConvites360Provider),
          child: HrContentColumn(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                if (pendentes.isNotEmpty) ...[
                  const _Secao('Aguardando sua resposta'),
                  const SizedBox(height: 8),
                  for (final c in pendentes) _ConviteCard(convite: c),
                  const SizedBox(height: 20),
                ],
                if (feitas.isNotEmpty) ...[
                  const _Secao('Já respondidas'),
                  const SizedBox(height: 8),
                  for (final c in feitas) _ConviteCard(convite: c),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConviteCard extends ConsumerWidget {
  const _ConviteCard({required this.convite});

  final Convite360 convite;

  static final _data = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final c = convite;
    final atrasado = c.podeResponder &&
        c.prazoResposta != null &&
        c.prazoResposta!.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.autoavaliacao ? 'Sua autoavaliação' : c.avaliadoNome,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 2),
            Text('${c.cicloNome} · ${Origem360.label(c.origem)}',
                style: TextStyle(
                    fontSize: 12.5, color: theme.colorScheme.outline)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (c.prazoResposta != null)
                  Text(
                    atrasado
                        ? 'Prazo venceu em ${_data.format(c.prazoResposta!)}'
                        : 'Até ${_data.format(c.prazoResposta!)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: atrasado
                            ? tokens.danger
                            : theme.colorScheme.outline),
                  ),
                if (!c.pendente)
                  Text('Respondida — nota ${c.nota ?? '-'}',
                      style: TextStyle(fontSize: 12, color: tokens.success)),
                if (c.pendente && c.cicloStatus != 'aberto')
                  Text('Ciclo ainda não aberto',
                      style: TextStyle(
                          fontSize: 12, color: theme.colorScheme.outline)),
              ],
            ),
            if (c.podeResponder) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => _responder(context, ref),
                  child: const Text('Responder'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _responder(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showHrFormSheet<bool>(
      context: context,
      builder: (_) => _ResponderSheet(convite: convite),
    );
    if (ok != true) return;
    ref.invalidate(meusConvites360Provider);
    messenger
        .showSnackBar(const SnackBar(content: Text('Avaliação enviada.')));
  }
}

/// Formulário de resposta: nota 0–100 + dois campos de texto.
class _ResponderSheet extends ConsumerStatefulWidget {
  const _ResponderSheet({required this.convite});

  final Convite360 convite;

  @override
  ConsumerState<_ResponderSheet> createState() => _ResponderSheetState();
}

class _ResponderSheetState extends ConsumerState<_ResponderSheet> {
  double _nota = 70;
  final _fortes = TextEditingController();
  final _melhoria = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _fortes.dispose();
    _melhoria.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.convite;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              c.autoavaliacao ? 'Autoavaliação' : 'Avaliar ${c.avaliadoNome}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              c.autoavaliacao
                  ? '${c.cicloNome}. Sua nota entra no consolidado junto com '
                      'as demais.'
                  : '${c.cicloNome} · ${Origem360.label(c.origem)}. A pessoa '
                      'avaliada vê apenas médias, nunca quem escreveu.',
              style: TextStyle(
                  fontSize: 12.5, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 20),
            Text('Nota: ${_nota.round()}/100',
                style: theme.textTheme.titleMedium),
            Slider(
              value: _nota,
              max: 100,
              divisions: 20,
              label: '${_nota.round()}',
              onChanged: _enviando ? null : (v) => setState(() => _nota = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _fortes,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Pontos fortes',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _melhoria,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Pontos a desenvolver',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _enviando ? null : _enviar,
              child: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enviar avaliação'),
            ),
            const SizedBox(height: 8),
            Text(
              'Depois de enviar não dá para alterar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enviar() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _enviando = true);
    try {
      await ref.read(desempenhoServiceProvider).responder(
            avaliacaoId: widget.convite.id,
            nota: _nota.round(),
            pontosFortes: _fortes.text,
            pontosMelhoria: _melhoria.text,
          );
      navigator.pop(true);
    } catch (e) {
      if (mounted) setState(() => _enviando = false);
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }
}

// ── Minhas metas ─────────────────────────────────────────────

class _MinhasMetasTab extends ConsumerWidget {
  const _MinhasMetasTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(minhasMetasProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
      data: (metas) {
        if (metas.isEmpty) {
          // Aqui o colaborador não tem o que cadastrar — quem define meta é
          // o gestor. O passo a passo explica o fluxo para a espera não
          // parecer erro do app.
          return const HrEmptyState(
            icone: Icons.flag_outlined,
            titulo: 'Nenhuma meta definida para você',
            descricao:
                'Meta é o combinado do período: o que você precisa entregar '
                'e como isso será medido. Quem cadastra é o seu gestor ou o '
                'RH, dentro de um ciclo de avaliação.',
            passos: [
              'O RH abre um ciclo de avaliação do período.',
              'Seu gestor cadastra as suas metas dentro desse ciclo.',
              'Elas aparecem aqui, e você atualiza o progresso de cada uma.',
            ],
            nota: 'Se o ciclo já começou e nada apareceu, fale com o seu '
                'gestor ou com o RH.',
            estrutura: HrGhostList(
              comAvatar: false,
              colunas: ['Meta', 'Peso', 'Progresso'],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(minhasMetasProvider),
          child: HrContentColumn(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                for (final m in metas) MetaCard(meta: m, editavel: true),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Card de meta com barra de progresso. [editavel] libera o ajuste do
/// andamento (dono da meta ou RH).
class MetaCard extends ConsumerStatefulWidget {
  const MetaCard({
    super.key,
    required this.meta,
    this.editavel = false,
    this.mostrarNome = false,
  });

  final MetaModel meta;
  final bool editavel;
  final bool mostrarNome;

  @override
  ConsumerState<MetaCard> createState() => _MetaCardState();
}

class _MetaCardState extends ConsumerState<MetaCard> {
  bool _salvando = false;

  static final _data = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final m = widget.meta;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.mostrarNome && m.funcionarioNome != null) ...[
              Text(m.funcionarioNome!,
                  style: TextStyle(
                      fontSize: 12.5, color: theme.colorScheme.outline)),
              const SizedBox(height: 4),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(m.titulo,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                if (m.peso > 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('peso ${m.peso}',
                        style: TextStyle(
                            fontSize: 11.5, color: theme.colorScheme.outline)),
                  ),
              ],
            ),
            if ((m.descricao ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(m.descricao!,
                  style:
                      TextStyle(fontSize: 13, color: theme.colorScheme.outline)),
            ],
            if ((m.metrica ?? '').isNotEmpty || (m.alvo ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if ((m.metrica ?? '').isNotEmpty)
                    Text('Métrica: ${m.metrica}',
                        style: TextStyle(
                            fontSize: 12, color: theme.colorScheme.outline)),
                  if ((m.alvo ?? '').isNotEmpty)
                    Text('Alvo: ${m.alvo}',
                        style: TextStyle(
                            fontSize: 12, color: theme.colorScheme.outline)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: m.progresso / 100,
                      minHeight: 8,
                      color: m.atingida ? tokens.success : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${m.progresso}%',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (m.prazo != null)
                  Text(
                    m.atrasada
                        ? 'Venceu em ${_data.format(m.prazo!)}'
                        : 'Prazo: ${_data.format(m.prazo!)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: m.atrasada
                            ? tokens.danger
                            : theme.colorScheme.outline),
                  ),
                if (m.atingida)
                  Text('Atingida',
                      style: TextStyle(fontSize: 12, color: tokens.success)),
                if (m.cancelada)
                  Text('Cancelada',
                      style: TextStyle(
                          fontSize: 12, color: theme.colorScheme.outline)),
                if (widget.editavel && !m.cancelada)
                  TextButton.icon(
                    onPressed: _salvando ? null : _atualizar,
                    icon: _salvando
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.tune, size: 16),
                    label: const Text('Atualizar andamento'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _atualizar() async {
    final messenger = ScaffoldMessenger.of(context);
    final resultado = await showHrFormSheet<(int, String)>(
      context: context,
      builder: (_) => _ProgressoSheet(meta: widget.meta),
    );
    if (resultado == null) return;

    setState(() => _salvando = true);
    try {
      await ref.read(desempenhoServiceProvider).atualizarProgresso(
            widget.meta.id,
            resultado.$1,
            resultado: resultado.$2,
          );
      ref.invalidate(minhasMetasProvider);
      ref.invalidate(metasDoCicloProvider(widget.meta.cicloId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }
}

class _ProgressoSheet extends StatefulWidget {
  const _ProgressoSheet({required this.meta});

  final MetaModel meta;

  @override
  State<_ProgressoSheet> createState() => _ProgressoSheetState();
}

class _ProgressoSheetState extends State<_ProgressoSheet> {
  late double _progresso = widget.meta.progresso.toDouble();
  late final _resultado =
      TextEditingController(text: widget.meta.resultado ?? '');

  @override
  void dispose() {
    _resultado.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.meta.titulo,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Andamento: ${_progresso.round()}%',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: _progresso,
              max: 100,
              divisions: 20,
              label: '${_progresso.round()}%',
              onChanged: (v) => setState(() => _progresso = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _resultado,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Resultado alcançado (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(
                  context, (_progresso.round(), _resultado.text)),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Meu resultado ────────────────────────────────────────────

class _MeuResultadoTab extends ConsumerStatefulWidget {
  const _MeuResultadoTab();

  @override
  ConsumerState<_MeuResultadoTab> createState() => _MeuResultadoTabState();
}

class _MeuResultadoTabState extends ConsumerState<_MeuResultadoTab> {
  String? _cicloId;

  @override
  Widget build(BuildContext context) {
    final ciclos = ref.watch(ciclosVisiveisProvider);

    return ciclos.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
      data: (lista) {
        if (lista.isEmpty) {
          return const HrEmptyState(
            icone: Icons.insights,
            titulo: 'Nenhum ciclo de avaliação aberto',
            descricao:
                'O ciclo é o período em que a empresa avalia o desempenho '
                '— semestre, ano. É nele que ficam as suas metas e a '
                'avaliação 360 feita por gestor, pares e por você.',
            passos: [
              'O RH abre o ciclo do período.',
              'Suas metas são cadastradas e você acompanha o progresso.',
              'Na fase de avaliação, você responde a sua autoavaliação e '
                  'as avaliações de quem trabalha com você.',
              'Com o ciclo encerrado, o resultado consolidado aparece aqui.',
            ],
            nota: 'Não há nada para você configurar: a abertura do ciclo é '
                'do RH.',
          );
        }
        final selecionado = _cicloId ?? lista.first.id;

        return HrContentColumn(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: selecionado,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Ciclo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final c in lista)
                    DropdownMenuItem(
                        value: c.id,
                        child:
                            Text(c.nome, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _cicloId = v),
              ),
              const SizedBox(height: 16),
              _Resultado(cicloId: selecionado),
            ],
          ),
        );
      },
    );
  }
}

class _Resultado extends ConsumerWidget {
  const _Resultado({required this.cicloId});

  final String cicloId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(meuResultado360Provider(cicloId));
    final theme = Theme.of(context);
    final tokens = context.statusTokens;

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('Erro: ${friendlyError(e)}'),
      ),
      data: (r) {
        if (r == null || r.respondidas == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(Icons.hourglass_empty,
                    size: 48, color: theme.colorScheme.outline),
                const SizedBox(height: 12),
                Text('Ainda sem respostas neste ciclo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.outline)),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nota geral',
                        style: TextStyle(color: theme.colorScheme.outline)),
                    const SizedBox(height: 4),
                    Text(
                      r.notaGeral?.toStringAsFixed(1) ?? '—',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                        height: 1.1,
                      ),
                    ),
                    Text('${r.respondidas} '
                        '${r.respondidas == 1 ? 'resposta recebida' : 'respostas recebidas'}',
                        style: TextStyle(
                            fontSize: 12.5, color: theme.colorScheme.outline)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Notas por origem em grade que acompanha a largura.
            LayoutBuilder(
              builder: (context, constraints) {
                final colunas = constraints.maxWidth >= 560 ? 3 : 2;
                final largura =
                    (constraints.maxWidth - (colunas - 1) * 10) / colunas;
                final blocos = <Widget>[
                  _NotaOrigem(rotulo: 'Autoavaliação', valor: r.notaAuto),
                  _NotaOrigem(rotulo: 'Gestor', valor: r.notaGestor),
                  _NotaOrigem(
                    rotulo: 'Pares',
                    valor: r.notaPares,
                    // Sem k-anonimato, a média de pares fica oculta.
                    aviso: r.paresAnonimatoOk
                        ? null
                        : 'Poucas respostas ainda '
                            '(${r.paresRespondidas}) para exibir sem '
                            'identificar quem respondeu.',
                  ),
                  if (r.progressoMetas != null)
                    _NotaOrigem(
                      rotulo: 'Metas',
                      valor: r.progressoMetas,
                      sufixo: '%',
                    ),
                ];
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final b in blocos)
                      SizedBox(width: largura, child: b),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 16, color: tokens.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Você vê apenas médias. Os comentários individuais e a '
                    'identidade de quem avaliou ficam com o RH.',
                    style: TextStyle(fontSize: 12, color: tokens.info),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _NotaOrigem extends StatelessWidget {
  const _NotaOrigem({
    required this.rotulo,
    required this.valor,
    this.aviso,
    this.sufixo = '',
  });

  final String rotulo;
  final double? valor;
  final String? aviso;
  final String sufixo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(rotulo,
                style:
                    TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
            const SizedBox(height: 4),
            Text(
              valor == null ? '—' : '${valor!.toStringAsFixed(1)}$sufixo',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            if (aviso != null) ...[
              const SizedBox(height: 4),
              Text(aviso!,
                  style: TextStyle(
                      fontSize: 10.5, color: theme.colorScheme.outline)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Compartilhados ───────────────────────────────────────────

class _Secao extends StatelessWidget {
  const _Secao(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(texto,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w700));
}

class _Vazio extends StatelessWidget {
  const _Vazio({
    required this.icone,
    required this.titulo,
    required this.texto,
  });

  final IconData icone;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: HrContentColumn(
        maxWidth: 420,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 72),
            Icon(icone, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(titulo,
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(texto,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}
