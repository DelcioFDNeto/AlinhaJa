import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/features/hr/models/pipeline_etapa_model.dart';
import 'package:alinha_ja/features/hr/providers/talent_bank_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-14 / Fase 5 — Gestão das etapas do pipeline (aba Ajustes).
/// Renomear/recolorir qualquer etapa; criar, reordenar e excluir as
/// intermediárias. Entrada, Contratado e Descartado são fixas (o banco
/// protege slug/tipo e bloqueia exclusão de etapa com candidatos).
class PipelineStagesSheet extends ConsumerStatefulWidget {
  const PipelineStagesSheet({super.key});

  @override
  ConsumerState<PipelineStagesSheet> createState() =>
      _PipelineStagesSheetState();
}

class _PipelineStagesSheetState extends ConsumerState<PipelineStagesSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(rbacCanProvider((module: 'rh_banco_talentos', action: 'manage')));
    final configAsync = ref.watch(pipelineConfigProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Scaffold(
        appBar: AppBar(
          title: const Text('Etapas do pipeline'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        floatingActionButton: isAdmin &&
                (configAsync.valueOrNull?.customizada ?? false)
            ? FloatingActionButton.extended(
                onPressed: _busy ? null : _novaEtapa,
                icon: const Icon(Icons.add),
                label: const Text('Nova etapa'),
              )
            : null,
        body: configAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erro ao carregar etapas.\n${friendlyError(e)}')),
          data: (config) => _buildBody(config, isAdmin),
        ),
      ),
    );
  }

  Widget _buildBody(PipelineConfig config, bool isAdmin) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        if (!config.customizada) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Funil padrão em uso',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'Sua organização usa as etapas padrão. Personalize para '
                    'renomear, reordenar ou criar etapas próprias.',
                    style: TextStyle(
                        fontSize: 13, color: theme.colorScheme.outline),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _personalizar,
                      icon: const Icon(Icons.tune),
                      label: const Text('Personalizar etapas'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (final e in config.etapas)
          _EtapaTile(
            etapa: e,
            editable: isAdmin && config.customizada && !_busy,
            isFirstNormal: _normais(config).isNotEmpty &&
                _normais(config).first.id == e.id,
            isLastNormal: _normais(config).isNotEmpty &&
                _normais(config).last.id == e.id,
            onEdit: () => _editarEtapa(e),
            onDelete: () => _excluirEtapa(e),
            onMoveUp: () => _mover(config, e, -1),
            onMoveDown: () => _mover(config, e, 1),
          ),
      ],
    );
  }

  List<PipelineEtapa> _normais(PipelineConfig c) =>
      [for (final e in c.etapas) if (e.isNormal) e];

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(pipelineConfigProvider);
      ref.invalidate(talentStatusCountsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Semeia o funil padrão no banco (a partir daí a org edita à vontade).
  Future<void> _personalizar() => _run(() async {
        await ref.read(talentBankServiceProvider).seedPipelinePadrao();
      });

  Future<void> _novaEtapa() async {
    final config = ref.read(pipelineConfigProvider).valueOrNull;
    if (config == null) return;
    final result = await _EtapaFormSheet.show(context);
    if (result == null) return;
    await _run(() async {
      final svc = ref.read(talentBankServiceProvider);
      final slug = _slugify(result.nome, config);
      // Nova etapa entra ao fim das intermediárias; contratado é empurrado.
      final normais = _normais(config);
      final ordem = 2 + normais.length;
      await svc.updatePipelineEtapa(config.contratado.id, ordem: ordem + 1);
      await svc.createPipelineEtapa(
          slug: slug, nome: result.nome, ordem: ordem, roleCor: result.roleCor);
    });
  }

  Future<void> _editarEtapa(PipelineEtapa e) async {
    final result = await _EtapaFormSheet.show(context, etapa: e);
    if (result == null) return;
    await _run(() async {
      await ref.read(talentBankServiceProvider).updatePipelineEtapa(e.id,
          nome: result.nome, roleCor: result.roleCor);
    });
  }

  Future<void> _excluirEtapa(PipelineEtapa e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir etapa?'),
        content: Text('A etapa "${e.nome}" será removida do funil. '
            'Só é possível excluir etapas sem candidatos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref.read(talentBankServiceProvider).deletePipelineEtapa(e.id);
    });
  }

  /// Sobe/desce uma etapa intermediária trocando a `ordem` com a vizinha.
  Future<void> _mover(PipelineConfig config, PipelineEtapa e, int dir) async {
    final normais = _normais(config);
    final i = normais.indexWhere((n) => n.id == e.id);
    final j = i + dir;
    if (i < 0 || j < 0 || j >= normais.length) return;
    final outra = normais[j];
    await _run(() async {
      final svc = ref.read(talentBankServiceProvider);
      await svc.updatePipelineEtapa(e.id, ordem: outra.ordem);
      await svc.updatePipelineEtapa(outra.id, ordem: e.ordem);
    });
  }

  /// Slug a partir do nome (sem acentos, minúsculas, `_`), único na org.
  String _slugify(String nome, PipelineConfig config) {
    const mapa = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const puro = 'aaaaaeeeeiiiiooooouuuucn';
    var s = nome.trim().toLowerCase();
    for (var i = 0; i < mapa.length; i++) {
      s = s.replaceAll(mapa[i], puro[i]);
    }
    s = s
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (s.length < 2) s = 'etapa';
    if (s.length > 36) s = s.substring(0, 36);
    final existentes = {for (final e in config.etapas) e.slug};
    var slug = s;
    var n = 2;
    while (existentes.contains(slug)) {
      slug = '${s}_$n';
      n++;
    }
    return slug;
  }
}

/// Linha de uma etapa: bolinha na cor do papel, nome e ações.
class _EtapaTile extends StatelessWidget {
  const _EtapaTile({
    required this.etapa,
    required this.editable,
    required this.isFirstNormal,
    required this.isLastNormal,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final PipelineEtapa etapa;
  final bool editable;
  final bool isFirstNormal;
  final bool isLastNormal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  static const _tipoLabels = {
    'entrada': 'Etapa de entrada',
    'contratado': 'Terminal — contratação',
    'descartado': 'Terminal — descarte',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = context.statusTokens.color(etapa.role);
    final tipoLabel = _tipoLabels[etapa.tipo];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text(etapa.nome,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: tipoLabel != null
            ? Text(tipoLabel,
                style:
                    TextStyle(fontSize: 12, color: theme.colorScheme.outline))
            : null,
        trailing: !editable
            ? (tipoLabel != null
                ? Icon(Icons.lock_outline,
                    size: 18, color: theme.colorScheme.outline)
                : null)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (etapa.isNormal) ...[
                    IconButton(
                      tooltip: 'Subir',
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      onPressed: isFirstNormal ? null : onMoveUp,
                    ),
                    IconButton(
                      tooltip: 'Descer',
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      onPressed: isLastNormal ? null : onMoveDown,
                    ),
                  ],
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: onEdit,
                  ),
                  if (etapa.isNormal)
                    IconButton(
                      tooltip: 'Excluir',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: onDelete,
                    )
                  else
                    Icon(Icons.lock_outline,
                        size: 18, color: theme.colorScheme.outline),
                ],
              ),
      ),
    );
  }
}

class _EtapaFormResult {
  final String nome;
  final String roleCor;
  const _EtapaFormResult(this.nome, this.roleCor);
}

/// Form de etapa — nome + papel de cor (tokens white-label, nunca cor crua).
class _EtapaFormSheet extends StatefulWidget {
  const _EtapaFormSheet({this.etapa});

  final PipelineEtapa? etapa;

  static Future<_EtapaFormResult?> show(BuildContext context,
      {PipelineEtapa? etapa}) {
    return showModalBottomSheet<_EtapaFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EtapaFormSheet(etapa: etapa),
    );
  }

  @override
  State<_EtapaFormSheet> createState() => _EtapaFormSheetState();
}

class _EtapaFormSheetState extends State<_EtapaFormSheet> {
  late final TextEditingController _nome =
      TextEditingController(text: widget.etapa?.nome ?? '');
  late String _role = widget.etapa?.roleCor ?? 'info';

  static const _roleLabels = {
    StatusRole.info: 'Azul',
    StatusRole.warning: 'Laranja',
    StatusRole.highlight: 'Roxo',
    StatusRole.progress: 'Teal',
    StatusRole.success: 'Verde',
    StatusRole.pending: 'Âmbar',
    StatusRole.danger: 'Vermelho',
    StatusRole.neutral: 'Cinza',
  };

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.etapa == null ? 'Nova etapa' : 'Editar etapa',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nome,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome da etapa'),
          ),
          const SizedBox(height: 8),
          Text('Cor no funil', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _roleLabels.entries)
                ChoiceChip(
                  selected: _role == entry.key.name,
                  avatar: CircleAvatar(
                      backgroundColor: tokens.color(entry.key), radius: 7),
                  label: Text(entry.value),
                  onSelected: (_) =>
                      setState(() => _role = entry.key.name),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final nome = _nome.text.trim();
              if (nome.length < 2) return;
              Navigator.pop(context, _EtapaFormResult(nome, _role));
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
