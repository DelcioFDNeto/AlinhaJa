import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/avaliacao_model.dart';
import 'package:alinha_ja/features/hr/models/vacancy_model.dart';
import 'package:alinha_ja/features/hr/providers/avaliacao_provider.dart';
import 'package:alinha_ja/features/hr/providers/vacancy_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-12 / Fase 3 — aba Avaliações da Central de Recrutamento.
/// Banco de questões por cargo, geração por IA e correção server-side
/// (a correção acontece no portal; aqui é a gestão do banco).
class AvaliacoesTab extends ConsumerStatefulWidget {
  const AvaliacoesTab({super.key});

  @override
  ConsumerState<AvaliacoesTab> createState() => _AvaliacoesTabState();
}

class _AvaliacoesTabState extends ConsumerState<AvaliacoesTab> {
  String? _cargoFiltro;

  @override
  Widget build(BuildContext context) {
    final cargosAsync = ref.watch(cargosProvider(false));
    final questoesAsync = ref.watch(questoesProvider(_cargoFiltro));

    return Column(
      children: [
        // Ações + filtro por cargo
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: cargosAsync.when(
                  data: (cargos) => DropdownButtonFormField<String?>(
                    initialValue: _cargoFiltro,
                    isDense: true,
                    decoration: const InputDecoration(
                        labelText: 'Filtrar por cargo', isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Todos os cargos')),
                      for (final c in cargos)
                        DropdownMenuItem(value: c.id, child: Text(c.nome)),
                    ],
                    onChanged: (v) => setState(() => _cargoFiltro = v),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _gerarIA(context, cargosAsync.valueOrNull),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Gerar com IA'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _editarQuestao(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nova questão'),
                ),
              ),
            ],
          ),
        ),
        // RH-23 — regras da prova aplicada ao candidato.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: _ConfigProvaBar(onEditar: () => _configurarProva(context)),
        ),
        Expanded(
          child: questoesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erro ao carregar questões.\n${friendlyError(e)}',
                    textAlign: TextAlign.center),
              ),
            ),
            data: (questoes) {
              if (questoes.isEmpty) {
                return HrEmptyState(
                  icone: Icons.quiz_outlined,
                  titulo: 'Nenhuma questão no banco',
                  descricao:
                      'O banco de questões alimenta a prova objetiva que o '
                      'candidato responde no portal. Sem questão cadastrada, '
                      'a etapa de avaliação técnica do funil não tem o que '
                      'aplicar.',
                  passos: const [
                    'Use "Gerar com IA": escolha o cargo e a IA monta um '
                        'primeiro lote de questões para você revisar.',
                    'Ou use "Nova questão" para escrever à mão, com as '
                        'alternativas e a resposta certa.',
                    'Ajuste as regras da prova (quantidade de questões e '
                        'tempo) na barra logo acima da lista.',
                    'Envie a prova ao candidato pela ficha dele, na etapa de '
                        'avaliação técnica.',
                  ],
                  acaoLabel: 'Gerar questões com IA',
                  acaoIcone: Icons.auto_awesome,
                  onAcao: () => _gerarIA(context, cargosAsync.valueOrNull),
                  acaoSecundariaLabel: 'Criar questão manualmente',
                  onAcaoSecundaria: () => _editarQuestao(context),
                  estrutura: const HrGhostList(
                    comAvatar: false,
                    colunas: ['Questão', 'Cargo', 'Dificuldade'],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(questoesProvider),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  itemCount: questoes.length,
                  itemBuilder: (context, i) => _QuestaoCard(
                    questao: questoes[i],
                    onEdit: () => _editarQuestao(context, questoes[i]),
                    onDelete: () => _excluir(context, questoes[i]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _gerarIA(
      BuildContext context, List<CatalogItem>? cargos) async {
    if (cargos == null || cargos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Cadastre ao menos um cargo (Ajustes → Catálogo) para gerar questões.')));
      return;
    }
    final geradas = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GerarIaSheet(cargos: cargos),
    );
    if (geradas != null && geradas > 0) {
      ref.invalidate(questoesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$geradas questões geradas com IA.')));
      }
    }
  }

  Future<void> _configurarProva(BuildContext context) async {
    final config = ref.read(avaliacaoConfigProvider).valueOrNull;
    if (config == null) return;
    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ConfigProvaSheet(config: config),
    );
    if (salvo == true) ref.invalidate(avaliacaoConfigProvider);
  }

  Future<void> _editarQuestao(BuildContext context,
      [QuestaoModel? questao]) async {
    final cargos = ref.read(cargosProvider(false)).valueOrNull ?? [];
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _QuestaoFormSheet(cargos: cargos, questao: questao),
    );
    if (saved == true) ref.invalidate(questoesProvider);
  }

  Future<void> _excluir(BuildContext context, QuestaoModel q) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir questão?'),
        content: const Text('A questão sai do banco e das próximas provas.'),
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
    try {
      await ref.read(avaliacaoServiceProvider).deleteQuestao(q.id);
      ref.invalidate(questoesProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro ao excluir: ${friendlyError(e)}')));
    }
  }
}

/// RH-23 — resumo clicável das regras da prova (quantidade + tempo).
class _ConfigProvaBar extends ConsumerWidget {
  const _ConfigProvaBar({required this.onEditar});

  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final config = ref.watch(avaliacaoConfigProvider);

    return config.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (c) => InkWell(
        onTap: onEditar,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.tune, size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Prova do candidato: ${c.qtd} ${c.qtd == 1 ? 'questão' : 'questões'}'
                  ' · ${c.temTempo ? '${c.minutos} min' : 'sem limite de tempo'}',
                  style: TextStyle(
                      fontSize: 12.5, color: theme.colorScheme.outline),
                ),
              ),
              Text('Ajustar',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sheet de configuração da prova aplicada ao candidato (RH-23).
class _ConfigProvaSheet extends ConsumerStatefulWidget {
  const _ConfigProvaSheet({required this.config});

  final AvaliacaoConfig config;

  @override
  ConsumerState<_ConfigProvaSheet> createState() => _ConfigProvaSheetState();
}

class _ConfigProvaSheetState extends ConsumerState<_ConfigProvaSheet> {
  late double _qtd = widget.config.qtd.toDouble();
  late bool _comTempo = widget.config.temTempo;
  late double _minutos =
      widget.config.temTempo ? widget.config.minutos.toDouble() : 30;
  bool _salvando = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Regras da prova', style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Valem para todo candidato que iniciar a avaliação a partir de '
            'agora. Provas já em andamento mantêm as regras do início.',
            style: TextStyle(color: theme.colorScheme.outline, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Text('Questões sorteadas: ${_qtd.round()}',
              style: theme.textTheme.titleSmall),
          Slider(
            value: _qtd,
            min: 1,
            max: 15,
            divisions: 14,
            label: '${_qtd.round()}',
            onChanged: _salvando ? null : (v) => setState(() => _qtd = v),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _comTempo,
            title: const Text('Limitar o tempo da prova'),
            subtitle: Text(
              _comTempo
                  ? 'O candidato vê um cronômetro; ao zerar, o que estiver '
                      'respondido é enviado automaticamente.'
                  : 'O candidato responde sem pressa, sem cronômetro.',
              style: const TextStyle(fontSize: 12.5),
            ),
            onChanged:
                _salvando ? null : (v) => setState(() => _comTempo = v),
          ),
          if (_comTempo) ...[
            const SizedBox(height: 8),
            Text('Tempo: ${_minutos.round()} minutos',
                style: theme.textTheme.titleSmall),
            Slider(
              value: _minutos,
              min: 5,
              max: 180,
              divisions: 35,
              label: '${_minutos.round()} min',
              onChanged:
                  _salvando ? null : (v) => setState(() => _minutos = v),
            ),
          ],
          const SizedBox(height: 12),
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
    );
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await ref.read(avaliacaoServiceProvider).saveConfig(
            qtd: _qtd.round(),
            minutos: _comTempo ? _minutos.round() : 0,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }
}

class _QuestaoCard extends StatelessWidget {
  const _QuestaoCard({
    required this.questao,
    required this.onEdit,
    required this.onDelete,
  });

  final QuestaoModel questao;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(questao.enunciado,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                if (questao.isIa)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.auto_awesome,
                        size: 16, color: tokens.highlight),
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (v) => v == 'editar' ? onEdit() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'editar', child: Text('Editar')),
                    PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < questao.opcoes.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      i == questao.corretaIdx
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: i == questao.corretaIdx
                          ? tokens.success
                          : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(questao.opcoes[i],
                          style: TextStyle(
                              fontSize: 13,
                              color: i == questao.corretaIdx
                                  ? tokens.success
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: i == questao.corretaIdx
                                  ? FontWeight.w600
                                  : FontWeight.w400)),
                    ),
                  ],
                ),
              ),
            if ((questao.nivel ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Nível: ${_nivelLabel(questao.nivel!)}',
                  style: TextStyle(
                      fontSize: 11.5, color: theme.colorScheme.outline)),
            ],
          ],
        ),
      ),
    );
  }

  static String _nivelLabel(String n) =>
      _niveis[n] ?? n;
}

const _niveis = {
  'estagio': 'Estágio',
  'junior': 'Júnior',
  'pleno': 'Pleno',
  'senior': 'Sênior',
  'lideranca': 'Liderança',
};

/// Sheet de geração de questões por IA.
class _GerarIaSheet extends ConsumerStatefulWidget {
  const _GerarIaSheet({required this.cargos});

  final List<CatalogItem> cargos;

  @override
  ConsumerState<_GerarIaSheet> createState() => _GerarIaSheetState();
}

class _GerarIaSheetState extends ConsumerState<_GerarIaSheet> {
  String? _cargoId;
  String _nivel = 'pleno';
  double _qtd = 5;
  bool _gerando = false;

  @override
  void initState() {
    super.initState();
    _cargoId = widget.cargos.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Gerar questões com IA',
                  style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'A IA cria questões de múltipla escolha para o cargo escolhido. '
            'Revise antes de aplicar — o gabarito nunca é enviado ao candidato.',
            style: TextStyle(color: theme.colorScheme.outline, fontSize: 13),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _cargoId,
            decoration: const InputDecoration(labelText: 'Cargo'),
            items: [
              for (final c in widget.cargos)
                DropdownMenuItem(value: c.id, child: Text(c.nome)),
            ],
            onChanged: (v) => setState(() => _cargoId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _nivel,
            decoration: const InputDecoration(labelText: 'Nível'),
            items: [
              for (final e in _niveis.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _nivel = v ?? 'pleno'),
          ),
          const SizedBox(height: 16),
          Text('Quantidade: ${_qtd.round()} questões',
              style: theme.textTheme.titleSmall),
          Slider(
            value: _qtd,
            min: 1,
            max: 15,
            divisions: 14,
            label: '${_qtd.round()}',
            onChanged: _gerando ? null : (v) => setState(() => _qtd = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _gerando ? null : _gerar,
            icon: _gerando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_gerando ? 'Gerando…' : 'Gerar questões'),
          ),
        ],
      ),
    );
  }

  Future<void> _gerar() async {
    final cargo = widget.cargos.firstWhere((c) => c.id == _cargoId);
    setState(() => _gerando = true);
    try {
      final n = await ref.read(avaliacaoServiceProvider).gerarQuestoesIA(
            cargoNome: cargo.nome,
            cargoId: cargo.id,
            nivel: _nivel,
            quantidade: _qtd.round(),
          );
      if (mounted) Navigator.pop(context, n);
    } catch (e) {
      if (mounted) {
        setState(() => _gerando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }
}

/// Form manual de questão (criação/edição).
class _QuestaoFormSheet extends ConsumerStatefulWidget {
  const _QuestaoFormSheet({required this.cargos, this.questao});

  final List<CatalogItem> cargos;
  final QuestaoModel? questao;

  @override
  ConsumerState<_QuestaoFormSheet> createState() => _QuestaoFormSheetState();
}

class _QuestaoFormSheetState extends ConsumerState<_QuestaoFormSheet> {
  late final TextEditingController _enunciado;
  late final List<TextEditingController> _opcoes;
  int _corretaIdx = 0;
  String? _cargoId;
  String? _nivel;
  bool _saving = false;

  bool get _isEdit => widget.questao != null;

  @override
  void initState() {
    super.initState();
    final q = widget.questao;
    _enunciado = TextEditingController(text: q?.enunciado ?? '');
    final ops = q?.opcoes ?? const [];
    _opcoes = List.generate(
      ops.length >= 2 ? ops.length : 4,
      (i) => TextEditingController(text: i < ops.length ? ops[i] : ''),
    );
    _corretaIdx = q?.corretaIdx ?? 0;
    _cargoId = q?.cargoId;
    _nivel = q?.nivel;
  }

  @override
  void dispose() {
    _enunciado.dispose();
    for (final c in _opcoes) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOpcao() {
    if (_opcoes.length >= 6) return;
    setState(() => _opcoes.add(TextEditingController()));
  }

  void _removeOpcao(int i) {
    if (_opcoes.length <= 2) return;
    setState(() {
      _opcoes.removeAt(i).dispose();
      if (_corretaIdx >= _opcoes.length) _corretaIdx = _opcoes.length - 1;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final enunciado = _enunciado.text.trim();
    final opcoes = _opcoes.map((c) => c.text.trim()).toList();
    if (enunciado.length < 5) {
      _erro('O enunciado precisa ter ao menos 5 caracteres.');
      return;
    }
    if (opcoes.any((o) => o.isEmpty)) {
      _erro('Preencha todas as alternativas (ou remova as vazias).');
      return;
    }
    setState(() => _saving = true);
    try {
      final svc = ref.read(avaliacaoServiceProvider);
      if (_isEdit) {
        await svc.updateQuestao(widget.questao!.id,
            cargoId: _cargoId,
            nivel: _nivel,
            enunciado: enunciado,
            opcoes: opcoes,
            corretaIdx: _corretaIdx);
      } else {
        await svc.createQuestao(
            cargoId: _cargoId,
            nivel: _nivel,
            enunciado: enunciado,
            opcoes: opcoes,
            corretaIdx: _corretaIdx);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _erro('Erro ao salvar: ${friendlyError(e)}');
      }
    }
  }

  void _erro(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Editar questão' : 'Nova questão'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _enunciado,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Enunciado *',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Text('Alternativas (marque a correta)',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            RadioGroup<int>(
              groupValue: _corretaIdx,
              onChanged: (v) => setState(() => _corretaIdx = v ?? 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _opcoes.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Radio<int>(
                            value: i,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _opcoes[i],
                              decoration: InputDecoration(
                                  labelText: 'Alternativa ${i + 1}',
                                  isDense: true),
                            ),
                          ),
                          if (_opcoes.length > 2)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _removeOpcao(i),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_opcoes.length < 6)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addOpcao,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar alternativa'),
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _cargoId,
              decoration: const InputDecoration(labelText: 'Cargo (opcional)'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Nenhum')),
                for (final c in widget.cargos)
                  DropdownMenuItem(value: c.id, child: Text(c.nome)),
              ],
              onChanged: (v) => setState(() => _cargoId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _nivel,
              decoration: const InputDecoration(labelText: 'Nível (opcional)'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Qualquer')),
                for (final e in _niveis.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _nivel = v),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
