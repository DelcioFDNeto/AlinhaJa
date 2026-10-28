import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/candidate_model.dart';
import 'package:alinha_ja/features/hr/models/pipeline_etapa_model.dart';
import 'package:alinha_ja/features/hr/models/vacancy_model.dart';
import 'package:alinha_ja/features/hr/providers/talent_bank_provider.dart';
import 'package:alinha_ja/features/hr/providers/vacancy_provider.dart';
import 'package:alinha_ja/features/hr/services/talent_bank_service.dart';
import 'package:alinha_ja/features/hr/ui/avaliacoes_tab.dart';
import 'package:alinha_ja/features/hr/ui/catalog_management_sheet.dart';
import 'package:alinha_ja/features/hr/ui/hr_dashboard_tab.dart';
import 'package:alinha_ja/features/hr/ui/vacancies_tab.dart';
import 'package:alinha_ja/features/hr/ui/vacancy_form_sheet.dart';
import 'package:alinha_ja/features/hr/ui/pipeline_stages_sheet.dart';
import 'package:alinha_ja/features/hr/ui/widgets/careers_link_panel.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/features/hr/ui/widgets/responsavel_picker.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';
import 'package:alinha_ja/features/hr/ui/candidate_form_sheet.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_stat_pill.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// F1.1 — Central de Recrutamento: hub do RH com sub-navegação.
/// Pipeline (lista + funil Kanban), Divulgação (link/QR do portal),
/// Vagas (Fase 2) e Ajustes (retenção LGPD).
class TalentBankScreen extends ConsumerStatefulWidget {
  const TalentBankScreen({super.key});

  @override
  ConsumerState<TalentBankScreen> createState() => _TalentBankScreenState();
}

class _TalentBankScreenState extends ConsumerState<TalentBankScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  late final TabController _tab;
  Timer? _debounce;
  bool _board = false;

  /// Seleção múltipla para ações em massa (RH-13). Vazio = modo normal.
  final Set<String> _selected = {};

  /// SLA: candidatos parados há mais dias que isto ganham alerta visual.
  static const _slaDias = 7;

  static final _money = NumberFormat.currency(
      locale: 'pt_BR', symbol: r'R$ ', decimalDigits: 0);

  bool get _selectionMode => _selected.isNotEmpty;

  /// Gerir o Banco de Talentos (RBAC): cadastrar, mover etapa, atribuir.
  bool get _podeGerir => ref.watch(rbacCanProvider((module: 'rh_banco_talentos', action: 'manage')));

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _clearSelection() => setState(() => _selected.clear());

  @override
  void initState() {
    super.initState();
    // FAB e ações do AppBar só fazem sentido em abas específicas.
    _tab = TabController(length: 6, vsync: this)
      ..addListener(() => setState(() {}));
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 300) {
        ref.read(talentListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tab.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // Debounce de 300ms (S028)
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(talentFiltersProvider.notifier).update(
            (f) => f.copyWith(search: value.trim()),
          );
    });
  }

  void _toggleBoard() {
    setState(() => _board = !_board);
    // No funil todas as etapas aparecem — o filtro de status atrapalharia.
    if (_board && ref.read(talentFiltersProvider).status != null) {
      ref.read(talentFiltersProvider.notifier).update(
            (f) => f.copyWith(status: () => null),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissoes = ref.watch(myPermissionsProvider);

    // S018/S019 — acesso restrito com mensagem clara (perfil sem o módulo).
    if (permissoes.hasValue &&
        !ref.watch(rbacCanProvider(
            (module: 'rh_banco_talentos', action: 'view')))) {
      return Scaffold(
        appBar: AppBar(title: const Text('Central de Recrutamento')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 56, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text('Acesso restrito ao RH',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Este módulo é exclusivo da equipe de Recursos Humanos. '
                  'Solicite acesso ao administrador do sistema.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final onPipeline = _tab.index == 1;
    final onVagas = _tab.index == 3;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Central de Recrutamento'),
            Opacity(
              opacity: 0.7,
              child: Text('Atrair, selecionar e contratar',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
            ),
          ],
        ),
        actions: [
          if (onPipeline)
            IconButton(
              tooltip: _board ? 'Ver lista' : 'Ver funil',
              icon: Icon(_board ? Icons.view_list : Icons.view_column),
              onPressed: _toggleBoard,
            ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Visão Geral'),
            Tab(text: 'Pipeline'),
            Tab(text: 'Divulgação'),
            Tab(text: 'Vagas'),
            Tab(text: 'Avaliações'),
            Tab(text: 'Ajustes'),
          ],
        ),
      ),
      floatingActionButton: !_podeGerir
          ? null
          : onPipeline
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Novo candidato'),
            )
          : onVagas
              ? FloatingActionButton.extended(
                  onPressed: () => _openVagaForm(context),
                  icon: const Icon(Icons.post_add),
                  label: const Text('Nova vaga'),
                )
              : null,
      body: TabBarView(
        controller: _tab,
        children: [
          HrDashboardTab(
              onVerCandidato: (id) => context.push('/rh/candidato/$id')),
          _buildPipelineTab(),
          const CareersLinkPanel(),
          VacanciesTab(onVerCandidatos: _onVerCandidatos),
          const AvaliacoesTab(),
          const _AjustesTab(),
        ],
      ),
    );
  }

  /// Aba Pipeline — comportamento original do Banco de Talentos
  /// (lista filtrável + funil Kanban) preservado.
  Widget _buildPipelineTab() {
    final filters = ref.watch(talentFiltersProvider);
    final counts = ref.watch(talentStatusCountsProvider).valueOrNull ?? const {};
    final user = ref.watch(currentUserProvider).valueOrNull;
    // Etapas da org (RH-14); enquanto carrega, usa o funil padrão.
    final pipe =
        ref.watch(pipelineConfigProvider).valueOrNull ?? PipelineConfig.padrao();
    // No modo funil a lista plana não é usada — evita uma query redundante.
    final list = _board ? null : ref.watch(talentListProvider);

    return Column(
      children: [
        _FunnelSummary(counts: counts, pipe: pipe),
        if (filters.vagaId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.work_outline, size: 18),
                label: Text('Vaga: ${filters.vagaTitulo ?? 'selecionada'}'),
                onDeleted: _clearVagaFilter,
              ),
            ),
          ),
        if (user != null && !_board)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                avatar: const Icon(Icons.person_pin_circle_outlined, size: 18),
                label: const Text('Meus candidatos'),
                selected: filters.responsavelId == user.id,
                onSelected: (sel) {
                  ref.read(talentFiltersProvider.notifier).update((f) =>
                      f.copyWith(
                          responsavelId: () => sel ? user.id : null));
                },
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Buscar por nome, e-mail ou cargo…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
            ),
          ),
        ),
        if (!_board)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _statusChip(null, 'Todos',
                    counts.values.fold<int>(0, (a, b) => a + b), filters),
                for (final e in pipe.etapas)
                  _statusChip(e.slug, e.nome, counts[e.slug] ?? 0, filters),
              ],
            ),
          ),
        Expanded(
          child: _board
              ? _buildBoard(pipe, counts, filters.search.isNotEmpty)
              : _buildList(list!, pipe),
        ),
        if (_selectionMode && !_board) _buildBulkBar(),
      ],
    );
  }

  /// Barra de ações em massa (RH-13) — aparece com seleção ativa.
  Widget _buildBulkBar() {
    final theme = Theme.of(context);
    final pipe =
        ref.watch(pipelineConfigProvider).valueOrNull ?? PipelineConfig.padrao();
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancelar seleção',
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
              Text('${_selected.length} selecionado(s)',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_podeGerir)
              TextButton.icon(
                onPressed: _bulkAtribuir,
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Atribuir'),
              ),
              if (_podeGerir)
              PopupMenuButton<String>(
                tooltip: 'Mover etapa',
                onSelected: _bulkMover,
                itemBuilder: (_) => [
                  for (final e in pipe.funil)
                    PopupMenuItem(value: e.slug, child: Text(e.nome)),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                      value: pipe.descartado.slug,
                      child: const Text('Descartar')),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.swap_horiz, size: 18),
                    SizedBox(width: 4),
                    Text('Mover'),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _bulkAtribuir() async {
    final ids = _selected.toList();
    final messenger = ScaffoldMessenger.of(context);
    final userId = await _pickResponsavel(context);
    if (userId == null) return; // cancelou (inclui a opção "remover" = '')
    try {
      final n = await ref
          .read(talentBankServiceProvider)
          .atribuirResponsavel(ids, userId.isEmpty ? null : userId);
      _clearSelection();
      ref.invalidate(talentListProvider);
      messenger.showSnackBar(
          SnackBar(content: Text('$n candidato(s) atualizado(s).')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
    }
  }

  Future<void> _bulkMover(String status) async {
    final ids = _selected.toList();
    final messenger = ScaffoldMessenger.of(context);
    final pipe =
        ref.read(pipelineConfigProvider).valueOrNull ?? PipelineConfig.padrao();
    try {
      final n = await ref
          .read(talentBankServiceProvider)
          .bulkUpdateStatus(ids, status);
      _clearSelection();
      ref.invalidate(talentListProvider);
      ref.invalidate(talentStatusCountsProvider);
      messenger.showSnackBar(SnackBar(
          content: Text(n == ids.length
              ? '$n candidato(s) → ${pipe.label(status)}'
              : '$n de ${ids.length} movido(s) (transições inválidas ignoradas).')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
    }
  }

  /// Seletor de responsável (bottom sheet). Retorna o id do usuário,
  /// string vazia para "remover responsável", ou null se cancelado.
  Future<String?> _pickResponsavel(BuildContext context) =>
      ResponsavelPicker.show(context);

  Widget _statusChip(
      String? status, String label, int count, TalentFilters filters) {
    final selected = filters.status == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        label: Text(count > 0 ? '$label ($count)' : label),
        onSelected: (_) {
          ref.read(talentFiltersProvider.notifier).update(
                (f) => f.copyWith(status: () => status),
              );
        },
      ),
    );
  }

  // ── Visão em lista ──────────────────────────────────────────────
  Widget _buildList(TalentListState list, PipelineConfig pipe) {
    final theme = Theme.of(context);

    if (list.error != null && list.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Erro ao carregar candidatos.\n${list.error}',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error)),
        ),
      );
    }
    if (list.items.isEmpty && list.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.items.isEmpty) {
      final filters = ref.read(talentFiltersProvider);

      if (filters.temFiltro) {
        return HrEmptyState.semResultado(
          titulo: 'Nenhum candidato neste recorte',
          descricao:
              'Há candidatos no banco, mas nenhum deles atende aos filtros '
              'de busca, etapa, vaga ou responsável que estão ativos.',
          onLimparFiltros: () {
            _searchController.clear();
            ref.read(talentFiltersProvider.notifier).state =
                const TalentFilters();
          },
        );
      }

      return HrEmptyState(
        icone: Icons.folder_shared_outlined,
        titulo: 'Banco de talentos vazio',
        descricao:
            'O banco guarda todo mundo que já se candidatou — inclusive '
            'quem não foi aproveitado na época. É dele que sai o funil de '
            'seleção, e é nele que se procura quando abre vaga parecida.',
        passos: const [
          'Publique uma vaga na aba Vagas: quem se candidatar pela página '
              'de carreiras entra aqui sozinho.',
          'Ou cadastre à mão em "Novo candidato" — dá para anexar o '
              'currículo e deixar a IA preencher os campos.',
          'Arraste o candidato pelas etapas do funil (triagem, entrevista, '
              'proposta) até a contratação.',
          'Ao contratar, converta o candidato em funcionário — a ficha '
              'nasce com os dados que ele já preencheu.',
        ],
        acaoLabel: 'Cadastrar candidato',
        acaoIcone: Icons.person_add_alt_1,
        onAcao: () => _openForm(context),
        estrutura: HrGhostBoard(
          colunas: [for (final e in pipe.etapas) e.nome],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(talentListProvider);
        ref.invalidate(talentStatusCountsProvider);
      },
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        itemCount: list.items.length + (list.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= list.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final c = list.items[index];
          final selected = _selected.contains(c.id);
          return _CandidateCard(
            candidate: c,
            money: _money,
            pipe: pipe,
            slaDias: _slaDias,
            selected: selected,
            selectionMode: _selectionMode,
            onTap: () => _selectionMode
                ? _toggleSelect(c.id)
                : context.push('/rh/candidato/${c.id}'),
            onLongPress: () => _toggleSelect(c.id),
          );
        },
      ),
    );
  }

  // ── Visão em funil (Kanban) com paginação por etapa ─────────────
  Widget _buildBoard(
      PipelineConfig pipe, Map<String, int> counts, bool searchActive) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final etapa in pipe.funil)
              _BoardColumn(
                etapa: etapa,
                pipe: pipe,
                total: counts[etapa.slug] ?? 0,
                searchActive: searchActive,
                height: constraints.maxHeight - 20,
                money: _money,
                onMove: _moveCandidate,
                onTapCard: (id) => context.push('/rh/candidato/$id'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveCandidate(CandidateModel c, String novoStatus) async {
    final from = c.status;
    final messenger = ScaffoldMessenger.of(context);
    final pipe =
        ref.read(pipelineConfigProvider).valueOrNull ?? PipelineConfig.padrao();
    // Feedback imediato: some da coluna de origem antes do round-trip.
    ref.read(boardColumnProvider(from).notifier).removeById(c.id);
    try {
      await ref
          .read(talentBankServiceProvider)
          .updateStatus(c.id, novoStatus);
      ref.invalidate(boardColumnProvider(novoStatus));
      ref.invalidate(talentStatusCountsProvider);
      ref.invalidate(talentListProvider);
      messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('${c.nome} → ${pipe.label(novoStatus)}')));
    } catch (e) {
      ref.invalidate(boardColumnProvider(from)); // restaura a origem
      messenger.showSnackBar(
          SnackBar(content: Text('Não foi possível mover: ${friendlyError(e)}')));
    }
  }

  Future<void> _openForm(BuildContext context) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CandidateFormSheet(),
    );
    if (created == true) {
      ref.invalidate(talentListProvider);
      ref.invalidate(talentStatusCountsProvider);
    }
  }

  Future<void> _openVagaForm(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const VacancyFormSheet(),
    );
    if (saved == true) ref.invalidate(vagasProvider);
  }

  /// Vindo da aba Vagas: filtra o pipeline pela vaga e volta para lá.
  void _onVerCandidatos(VagaModel vaga) {
    ref.read(talentFiltersProvider.notifier).update(
          (f) => f.copyWith(
            vagaId: () => vaga.id,
            vagaTitulo: () => vaga.titulo,
            status: () => null,
          ),
        );
    setState(() => _board = false);
    _tab.animateTo(1);
  }

  void _clearVagaFilter() {
    ref.read(talentFiltersProvider.notifier).update(
          (f) => f.copyWith(vagaId: () => null, vagaTitulo: () => null),
        );
  }

}

/// Card de candidato na visão em lista — layout de ATS com faixa lateral
/// colorida por etapa, avatar com anel, chips de metadados e selos de
/// score/status. Substitui o antigo ListTile plano por algo com mais cara
/// de pipeline de recrutamento.
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.money,
    required this.pipe,
    required this.onTap,
    required this.slaDias,
    this.selected = false,
    this.selectionMode = false,
    this.onLongPress,
  });

  final CandidateModel candidate;
  final NumberFormat money;
  final PipelineConfig pipe;
  final VoidCallback onTap;
  final int slaDias;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final c = candidate;
    final statusColor = tokens.color(pipe.role(c.status));
    final resumo = c.resumoExecutivo?.trim();
    final hasResumo = resumo != null && resumo.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      color: selected ? tokens.highlight.withValues(alpha: 0.10) : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: tokens.highlight, width: 2))
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Faixa lateral que sinaliza a etapa do funil de relance.
              Container(width: 4, color: statusColor),
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? tokens.highlight : theme.colorScheme.outline,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _avatar(statusColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _info(theme, tokens, resumo, hasResumo),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (c.scoreCompletude != null)
                            _ScorePill(score: c.scoreCompletude!),
                          const SizedBox(height: 6),
                          StatusBadge(
                              label: pipe.label(c.status),
                              role: pipe.role(c.status)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(Color statusColor) {
    final c = candidate;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border:
            Border.all(color: statusColor.withValues(alpha: 0.45), width: 2),
      ),
      child: CircleAvatar(
        radius: 22,
        backgroundColor: statusColor.withValues(alpha: 0.15),
        backgroundImage: c.fotoUrl != null ? CachedNetworkImageProvider(c.fotoUrl!, maxWidth: 320) : null,
        child: c.fotoUrl == null
            ? Text(c.initials,
                style: TextStyle(
                    color: statusColor, fontWeight: FontWeight.w700))
            : null,
      ),
    );
  }

  Widget _info(ThemeData theme, AlinhaStatusTokens tokens, String? resumo,
      bool hasResumo) {
    final c = candidate;
    final emProcesso = pipe.emProcesso(c.status);
    final dias = c.diasNaEtapa;
    final atrasado = emProcesso && dias != null && dias >= slaDias;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(c.nome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if ((c.cargoPretendido ?? '').isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(c.cargoPretendido!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (c.localidade.isNotEmpty)
              _MetaChip(icon: Icons.place, label: c.localidade),
            if (c.pretensaoSalarial != null)
              _MetaChip(
                  icon: Icons.payments,
                  label: money.format(c.pretensaoSalarial)),
            _MetaChip(
                icon: _fonteIcon(c.fonte),
                label: CandidateSource.label(c.fonte)),
            if ((c.responsavelNome ?? '').isNotEmpty)
              _MetaChip(
                  icon: Icons.person_outline, label: c.responsavelNome!),
            if (atrasado)
              _MetaChip(
                  icon: Icons.hourglass_bottom,
                  label: 'Parado há $dias d',
                  color: tokens.warning),
          ],
        ),
        if (hasResumo) ...[
          const SizedBox(height: 8),
          Text(resumo!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  height: 1.3,
                  color: theme.colorScheme.outline)),
        ],
      ],
    );
  }

  static IconData _fonteIcon(String fonte) {
    switch (fonte) {
      case 'portal':
        return Icons.public;
      case 'indicacao':
        return Icons.people;
      default:
        return Icons.upload_file;
    }
  }
}

/// Chip compacto de metadado (localidade, pretensão, fonte…) usado no card.
/// [color] tinge o chip (ex.: alerta de SLA); default é neutro.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tinted = color != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tinted
            ? color!.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color ?? theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: tinted ? FontWeight.w600 : FontWeight.w400,
                  color: color ?? theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Coluna do funil (Kanban) com paginação própria e alvo de arrastar.
class _BoardColumn extends ConsumerStatefulWidget {
  const _BoardColumn({
    required this.etapa,
    required this.pipe,
    required this.total,
    required this.searchActive,
    required this.height,
    required this.money,
    required this.onMove,
    required this.onTapCard,
  });

  final PipelineEtapa etapa;
  final PipelineConfig pipe;
  final int total;
  final bool searchActive;
  final double height;
  final NumberFormat money;
  final Future<void> Function(CandidateModel, String) onMove;
  final void Function(String id) onTapCard;

  @override
  ConsumerState<_BoardColumn> createState() => _BoardColumnState();
}

class _BoardColumnState extends ConsumerState<_BoardColumn> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.position.pixels >
          _controller.position.maxScrollExtent - 200) {
        ref.read(boardColumnProvider(widget.etapa.slug).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(boardColumnProvider(widget.etapa.slug));
    final color = context.statusTokens.color(widget.etapa.role);

    // Sob busca ativa o total global não vale; mostra o que foi carregado.
    final headerCount = widget.searchActive
        ? '${state.items.length}${state.hasMore ? '+' : ''}'
        : '${widget.total}';

    return DragTarget<CandidateModel>(
      onWillAcceptWithDetails: (d) => widget.pipe
          .transicoesDe(d.data.status)
          .contains(widget.etapa.slug),
      onAcceptWithDetails: (d) => widget.onMove(d.data, widget.etapa.slug),
      builder: (context, candidate, rejected) {
        final hi = candidate.isNotEmpty;
        return Container(
          width: 264,
          height: widget.height > 0 ? widget.height : null,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: hi
                ? color.withValues(alpha: 0.12)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hi ? color : theme.colorScheme.outlineVariant,
              width: hi ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(widget.etapa.nome,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text(headerCount,
                        style: TextStyle(
                            color: theme.colorScheme.outline,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Expanded(child: _body(state, color, theme)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BoardColumnState state, Color color, ThemeData theme) {
    if (state.items.isEmpty && state.loading) {
      return const Center(
        child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (state.items.isEmpty) {
      return Center(
        child: Text('Arraste para cá',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
      );
    }
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: state.items.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= state.items.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        return _draggableCard(state.items[i], color);
      },
    );
  }

  Widget _draggableCard(CandidateModel c, Color color) {
    final card = _BoardCard(
      candidate: c,
      money: widget.money,
      onTap: () => widget.onTapCard(c.id),
    );
    return LongPressDraggable<CandidateModel>(
      data: c,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
            width: 240, child: Opacity(opacity: 0.9, child: card)),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.candidate,
    required this.money,
    required this.onTap,
  });

  final CandidateModel candidate;
  final NumberFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = candidate;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundImage:
                        c.fotoUrl != null ? CachedNetworkImageProvider(c.fotoUrl!, maxWidth: 320) : null,
                    child: c.fotoUrl == null
                        ? Text(c.initials, style: const TextStyle(fontSize: 12))
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(c.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (c.scoreCompletude != null)
                    _ScorePill(score: c.scoreCompletude!),
                ],
              ),
              if ((c.cargoPretendido ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(c.cargoPretendido!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: theme.colorScheme.outline)),
              ],
              if (c.pretensaoSalarial != null) ...[
                const SizedBox(height: 4),
                Text(money.format(c.pretensaoSalarial),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Faixa de métricas do funil (RH-1.1 / S041): total, em processo,
/// contratados e taxa de conversão. Dá à tela cara de dashboard de ATS.
class _FunnelSummary extends StatelessWidget {
  const _FunnelSummary({required this.counts, required this.pipe});

  final Map<String, int> counts;
  final PipelineConfig pipe;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();
    final contratado = counts[pipe.contratado.slug] ?? 0;
    final descartado = counts[pipe.descartado.slug] ?? 0;
    final emProcesso = total - contratado - descartado;
    final conv = ((contratado * 100) / total).round();

    final tokens = context.statusTokens;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          HrStatPill(
              icon: Icons.groups,
              label: 'Candidatos',
              value: '$total',
              color: tokens.highlight),
          HrStatPill(
              icon: Icons.hourglass_bottom,
              label: 'Em processo',
              value: '$emProcesso',
              color: tokens.warning),
          HrStatPill(
              icon: Icons.verified,
              label: 'Contratados',
              value: '$contratado',
              color: tokens.success),
          HrStatPill(
              icon: Icons.trending_up,
              label: 'Conversão',
              value: '$conv%',
              color: tokens.progress),
        ],
      ),
    );
  }
}

/// Aba Ajustes — política de retenção LGPD (S011) e catálogo de
/// Áreas/Cargos (RH-9). Cresce nas próximas fases (etapas customizáveis…).
class _AjustesTab extends ConsumerStatefulWidget {
  const _AjustesTab();

  @override
  ConsumerState<_AjustesTab> createState() => _AjustesTabState();
}

class _AjustesTabState extends ConsumerState<_AjustesTab> {
  static const _opcoes = [6, 12, 18, 24, 36, 48];
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = ref.watch(rbacCanProvider((module: 'rh_banco_talentos', action: 'manage')));
    final config = ref.watch(portalConfigProvider);

    return config.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro ao carregar ajustes.\n${friendlyError(e)}')),
      data: (org) {
        final settings = org['settings'];
        final atual = settings is Map
            ? int.tryParse('${settings['candidato_retencao_meses'] ?? ''}') ??
                24
            : 24;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Retenção de candidatos (LGPD)',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Candidatos não contratados são anonimizados '
                      'automaticamente após este período.',
                      style: TextStyle(
                          fontSize: 13, color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _opcoes.contains(atual) ? atual : null,
                      decoration: const InputDecoration(
                        labelText: 'Período de retenção',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final m in _opcoes)
                          DropdownMenuItem(
                              value: m,
                              child: Text(m >= 12
                                  ? '${m ~/ 12} ano${m >= 24 ? 's' : ''}'
                                      '${m % 12 != 0 ? ' e ${m % 12} meses' : ''}'
                                  : '$m meses')),
                      ],
                      onChanged: isAdmin && !_saving
                          ? (v) => v != null ? _salvar(v) : null
                          : null,
                    ),
                    if (!isAdmin) ...[
                      const SizedBox(height: 8),
                      Text('Somente administradores do RH podem alterar.',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Etapas do pipeline (RH-14) ──────────────────────
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.view_column_outlined,
                    color: theme.colorScheme.primary),
                title: const Text('Etapas do pipeline'),
                subtitle: Text(
                  'Renomeie, reordene e crie etapas do funil de seleção.',
                  style: TextStyle(
                      fontSize: 13, color: theme.colorScheme.outline),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const PipelineStagesSheet(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Catálogo de Áreas e Cargos (RH-9) ───────────────
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.category_outlined,
                    color: theme.colorScheme.primary),
                title: const Text('Catálogo de Áreas e Cargos'),
                subtitle: Text(
                  'Organize áreas e cargos usados em vagas e filtros.',
                  style: TextStyle(
                      fontSize: 13, color: theme.colorScheme.outline),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const CatalogManagementSheet(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _salvar(int meses) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(talentBankServiceProvider).setRetencaoCandidatos(meses);
      ref.invalidate(portalConfigProvider);
      messenger.showSnackBar(const SnackBar(
          content: Text('Política de retenção atualizada.')));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Erro ao salvar: ${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Score de completude do perfil (0–100) — verde/laranja/vermelho.
class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final tokens = context.statusTokens;
    final color = score >= 70
        ? tokens.success
        : score >= 40
            ? tokens.warning
            : tokens.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$score%',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

