import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/features/hr/models/employee_model.dart';
import 'package:alinha_ja/features/hr/services/employee_service.dart';

final employeeServiceProvider =
    Provider<EmployeeService>((_) => const EmployeeService());

/// Filtros da listagem (busca com debounce fica na tela).
class EmployeeFilters {
  final String search;
  final String? status;

  const EmployeeFilters({this.search = '', this.status});

  /// Há algum recorte aplicado.
  ///
  /// Separa "a empresa não tem funcionário nenhum" de "a sua busca não
  /// achou" — os dois casos pedem telas de vazio diferentes.
  bool get temFiltro => search.trim().isNotEmpty || status != null;

  @override
  bool operator ==(Object other) =>
      other is EmployeeFilters &&
      other.search == search &&
      other.status == status;

  @override
  int get hashCode => Object.hash(search, status);
}

final employeeFiltersProvider =
    StateProvider<EmployeeFilters>((_) => const EmployeeFilters());

/// Lista paginada (recriada quando os filtros mudam).
class EmployeeListState {
  final List<EmployeeModel> items;
  final bool loading;
  final bool hasMore;
  final Object? error;

  const EmployeeListState({
    this.items = const [],
    this.loading = false,
    this.hasMore = true,
    this.error,
  });

  EmployeeListState copyWith({
    List<EmployeeModel>? items,
    bool? loading,
    bool? hasMore,
    Object? error,
  }) =>
      EmployeeListState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        hasMore: hasMore ?? this.hasMore,
        error: error,
      );
}

class EmployeeListNotifier extends StateNotifier<EmployeeListState> {
  EmployeeListNotifier(this._service, this._filters)
      : super(const EmployeeListState()) {
    loadMore();
  }

  final EmployeeService _service;
  final EmployeeFilters _filters;
  int _page = 0;

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final novos = await _service.fetchEmployees(
        search: _filters.search,
        status: _filters.status,
        page: _page,
      );
      _page++;
      state = state.copyWith(
        items: [...state.items, ...novos],
        loading: false,
        hasMore: novos.length == EmployeeService.pageSize,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }
}

final employeeListProvider = StateNotifierProvider.autoDispose<
    EmployeeListNotifier, EmployeeListState>((ref) {
  final filters = ref.watch(employeeFiltersProvider);
  return EmployeeListNotifier(ref.watch(employeeServiceProvider), filters);
});

/// Contagem por status (headcount) para o cabeçalho da lista (RH-4.1).
final employeeHeadcountProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  return ref.watch(employeeServiceProvider).fetchStatusCounts();
});

final employeeDetailProvider = FutureProvider.autoDispose
    .family<EmployeeModel, String>((ref, id) {
  return ref.watch(employeeServiceProvider).fetchEmployee(id);
});

/// Vínculo vigente da ficha (null = ficha ainda sem vínculo registrado).
final vinculoProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, funcionarioId) {
  return ref.watch(employeeServiceProvider).fetchVinculo(funcionarioId);
});

/// Estrutura organizacional (filiais/departamentos/cargos) p/ formulários.
final orgStructureProvider = FutureProvider.autoDispose<
    Map<String, List<Map<String, dynamic>>>>((ref) {
  return ref.watch(employeeServiceProvider).fetchOrgStructure();
});

/// F1.2 — Usuário do app vinculado à ficha (null = sem vínculo).
final linkedUserProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, userId) {
  return ref.watch(employeeServiceProvider).fetchUserBrief(userId);
});

/// F1.2 — Usuários vinculáveis (busca do bottom sheet).
final linkableUsersProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, search) {
  return ref.watch(employeeServiceProvider).fetchLinkableUsers(search);
});
