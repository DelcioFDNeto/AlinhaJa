import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/features/hr/models/employee_model.dart';
import 'package:alinha_ja/features/hr/providers/employee_provider.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/ui/employee_form_sheet.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_stat_pill.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// RH-4.1 — Diretório de funcionários (visão pública da org).
class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 300) {
        ref.read(employeeListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final f = ref.read(employeeFiltersProvider);
      ref.read(employeeFiltersProvider.notifier).state =
          EmployeeFilters(search: value.trim(), status: f.status);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Cadastrar exige gerir funcionários; abrir a ficha, só enxergá-los.
    final canManage = ref.watch(
        rbacCanProvider((module: 'rh_funcionarios', action: 'manage')));
    final canView = ref.watch(
        rbacCanProvider((module: 'rh_funcionarios', action: 'view')));
    final filters = ref.watch(employeeFiltersProvider);
    final list = ref.watch(employeeListProvider);
    final counts = ref.watch(employeeHeadcountProvider).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Funcionários'),
            Opacity(
              opacity: 0.7,
              child: Text('Diretório da organização',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
            ),
          ],
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Novo funcionário'),
            )
          : null,
      body: Column(
        children: [
          _HeadcountSummary(counts: counts),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Buscar por nome ou matrícula…',
                prefixIcon: Icon(Icons.search_rounded),
                filled: true,
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                for (final entry in [
                  const MapEntry<String?, String>(null, 'Todos'),
                  ...EmployeeStatus.labels.entries
                      .map((e) => MapEntry<String?, String>(e.key, e.value)),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: filters.status == entry.key,
                      label: Text(entry.value),
                      onSelected: (_) {
                        ref.read(employeeFiltersProvider.notifier).state =
                            EmployeeFilters(
                                search: filters.search, status: entry.key);
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: list.items.isEmpty && list.loading
                ? const Center(child: CircularProgressIndicator())
                : list.items.isEmpty
                    ? (filters.temFiltro
                        ? HrEmptyState.semResultado(
                            titulo: 'Nenhum funcionário nesta busca',
                            descricao:
                                'Há pessoas cadastradas, mas nenhuma atende '
                                'ao nome/matrícula e à situação '
                                'selecionados.',
                            onLimparFiltros: () => ref
                                    .read(employeeFiltersProvider.notifier)
                                    .state =
                                const EmployeeFilters(),
                          )
                        : HrEmptyState(
                            icone: Icons.badge_outlined,
                            titulo: 'Nenhum funcionário cadastrado',
                            descricao:
                                'O diretório é a base de todo o módulo de '
                                'RH: a ficha de cada pessoa é o que sustenta '
                                'ponto, holerite, férias, documentos e '
                                'desempenho. Comece por aqui.',
                            passos: const [
                              'Cadastre a pessoa com nome, matrícula, '
                                  'admissão e cargo.',
                              'Vincule a ficha ao usuário do app — é esse '
                                  'vínculo que faz o colaborador enxergar os '
                                  'próprios holerites e documentos.',
                              'Com a ficha criada, as demais telas de RH '
                                  'passam a ter em quem lançar.',
                            ],
                            acaoLabel: canManage ? 'Cadastrar funcionário' : null,
                            acaoIcone: Icons.person_add_alt_1,
                            onAcao: canManage ? () => _openForm(context) : null,
                            nota: canManage
                                ? null
                                : 'Só o RH cadastra funcionário. Fale com '
                                    'quem administra o módulo para incluir '
                                    'as pessoas.',
                            estrutura: const HrGhostList(
                              colunas: ['Funcionário', 'Cargo', 'Situação'],
                            ),
                          ))
                    : RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(employeeListProvider);
                          ref.invalidate(employeeHeadcountProvider);
                        },
                        child: ListView.separated(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount:
                              list.items.length + (list.hasMore ? 1 : 0),
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 72),
                          itemBuilder: (context, index) {
                            if (index >= list.items.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                    child: CircularProgressIndicator()),
                              );
                            }
                            return _employeeTile(list.items[index], canView);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _employeeTile(EmployeeModel e, bool canOpen) {
    final theme = Theme.of(context);

    final linha2 = <String>[
      if ((e.matricula ?? '').isNotEmpty) 'Matrícula ${e.matricula}',
      if (e.dataAdmissao != null) _tempoDeCasa(e.dataAdmissao!),
    ].join(' · ');

    return ListTile(
      isThreeLine: linha2.isNotEmpty,
      leading: CircleAvatar(
        backgroundImage: e.fotoUrl != null ? CachedNetworkImageProvider(e.fotoUrl!, maxWidth: 320) : null,
        child: e.fotoUrl == null ? Text(e.initials) : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(e.nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (e.userId != null) ...[
            const SizedBox(width: 8),
            const _AppBadge(),
          ],
          if ((e.vinculoTipo ?? '').isNotEmpty) ...[
            const SizedBox(width: 8),
            _VinculoChip(tipo: e.vinculoTipo!),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.lotacao.isEmpty ? '—' : e.lotacao,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (linha2.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(linha2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.outline)),
            ),
        ],
      ),
      trailing: StatusBadge(
          label: EmployeeStatus.label(e.status),
          role: EmployeeStatus.role(e.status)),
      onTap: canOpen ? () => context.push('/rh/funcionario/${e.id}') : null,
    );
  }

  /// Tempo de casa a partir da data de admissão (ex.: "2a 3m", "5 meses").
  static String _tempoDeCasa(DateTime admissao) {
    final now = DateTime.now();
    var meses = (now.year - admissao.year) * 12 + now.month - admissao.month;
    if (now.day < admissao.day) meses--;
    if (meses < 0) meses = 0;
    final anos = meses ~/ 12;
    final rem = meses % 12;
    if (anos == 0) return '$rem ${rem == 1 ? 'mês' : 'meses'}';
    if (rem == 0) return '$anos ${anos == 1 ? 'ano' : 'anos'} de casa';
    return '${anos}a ${rem}m de casa';
  }

  Future<void> _openForm(BuildContext context) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const EmployeeFormSheet(),
    );
    if (created == true) {
      ref.invalidate(employeeListProvider);
      ref.invalidate(employeeHeadcountProvider);
    }
  }
}

/// Cabeçalho de headcount (RH-4.1): total e distribuição por status.
class _HeadcountSummary extends StatelessWidget {
  const _HeadcountSummary({required this.counts});

  final Map<String, int> counts;

  static const _icons = {
    'ativo': Icons.check_circle,
    'ferias': Icons.beach_access,
    'afastado': Icons.event_busy,
    'desligado': Icons.logout,
  };

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox.shrink();
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    final tokens = context.statusTokens;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          HrStatPill(icon: Icons.groups, label: 'Total', value: '$total'),
          for (final entry in EmployeeStatus.labels.entries)
            HrStatPill(
              icon: _icons[entry.key] ?? Icons.circle,
              label: entry.value,
              value: '${counts[entry.key] ?? 0}',
              color: tokens.color(EmployeeStatus.role(entry.key)),
            ),
        ],
      ),
    );
  }
}

/// F1.2 — Selo "tem app": o funcionário está vinculado a um usuário.
class _AppBadge extends StatelessWidget {
  const _AppBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Vinculado a um usuário do app',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smartphone,
                size: 12, color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 3),
            Text('app',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimaryContainer)),
          ],
        ),
      ),
    );
  }
}

/// Chip do tipo de vínculo (CLT/PJ/Estágio…).
class _VinculoChip extends StatelessWidget {
  const _VinculoChip({required this.tipo});

  final String tipo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        VinculoTipo.label(tipo),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

