import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/features/hr/models/candidate_model.dart';
import 'package:alinha_ja/features/hr/models/pipeline_etapa_model.dart';
import 'package:alinha_ja/features/hr/services/talent_bank_service.dart';

final talentBankServiceProvider =
    Provider<TalentBankService>((_) => const TalentBankService());

/// Filtros ativos da listagem (busca com debounce fica na tela).
final talentFiltersProvider =
    StateProvider<TalentFilters>((_) => const TalentFilters());

/// Contagem por status (S041). Invalidate após mudanças.
final talentStatusCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  return ref.watch(talentBankServiceProvider).fetchStatusCounts();
});

/// Lista paginada de candidatos com "carregar mais".
class TalentListState {
  final List<CandidateModel> items;
  final bool loading;
  final bool hasMore;
  final Object? error;

  const TalentListState({
    this.items = const [],
    this.loading = false,
    this.hasMore = true,
    this.error,
  });

  TalentListState copyWith({
    List<CandidateModel>? items,
    bool? loading,
    bool? hasMore,
    Object? error,
  }) =>
      TalentListState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        hasMore: hasMore ?? this.hasMore,
        error: error,
      );
}

class TalentListNotifier extends StateNotifier<TalentListState> {
  TalentListNotifier(this._service, this._filters)
      : super(const TalentListState()) {
    loadMore();
  }

  final TalentBankService _service;
  final TalentFilters _filters;
  int _page = 0;

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final novos = await _service.fetchCandidates(_filters, _page);
      _page++;
      state = state.copyWith(
        items: [...state.items, ...novos],
        loading: false,
        hasMore: novos.length == TalentBankService.pageSize,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }
}

/// Recriado automaticamente sempre que os filtros mudam.
final talentListProvider = StateNotifierProvider.autoDispose<TalentListNotifier,
    TalentListState>((ref) {
  final filters = ref.watch(talentFiltersProvider);
  return TalentListNotifier(ref.watch(talentBankServiceProvider), filters);
});

/// Estado de uma coluna do funil (Kanban), com paginação independente
/// por etapa (S027). Cada status carrega e pagina os seus candidatos.
class BoardColumnState {
  final List<CandidateModel> items;
  final bool loading;
  final bool hasMore;
  final Object? error;

  const BoardColumnState({
    this.items = const [],
    this.loading = false,
    this.hasMore = true,
    this.error,
  });

  BoardColumnState copyWith({
    List<CandidateModel>? items,
    bool? loading,
    bool? hasMore,
    Object? error,
  }) =>
      BoardColumnState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        hasMore: hasMore ?? this.hasMore,
        error: error,
      );
}

class BoardColumnNotifier extends StateNotifier<BoardColumnState> {
  BoardColumnNotifier(this._service, this._filters, this._status)
      : super(const BoardColumnState()) {
    loadMore();
  }

  final TalentBankService _service;
  final TalentFilters _filters;
  final String _status;
  int _page = 0;

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final novos = await _service.fetchCandidates(
          _filters.copyWith(status: () => _status), _page);
      _page++;
      state = state.copyWith(
        items: [...state.items, ...novos],
        loading: false,
        hasMore: novos.length == TalentBankService.pageSize,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  /// Remoção otimista ao arrastar o card para outra etapa.
  void removeById(String id) {
    state =
        state.copyWith(items: state.items.where((c) => c.id != id).toList());
  }
}

/// Coluna do funil por status. Recriada quando os filtros (busca/área…)
/// mudam; o status de cada coluna é a chave da family.
final boardColumnProvider = StateNotifierProvider.autoDispose
    .family<BoardColumnNotifier, BoardColumnState, String>((ref, status) {
  final filters = ref.watch(talentFiltersProvider);
  return BoardColumnNotifier(
      ref.watch(talentBankServiceProvider), filters, status);
});

/// Mensagens RH ↔ candidato (RH-2.8).
final candidateMessagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, candidatoId) {
  return ref.watch(talentBankServiceProvider).listMessages(candidatoId);
});

/// Ficha completa de um candidato.
final candidateDetailProvider = FutureProvider.autoDispose
    .family<CandidateDetail, String>((ref, candidatoId) {
  return ref.watch(talentBankServiceProvider).fetchDetail(candidatoId);
});

/// Último erro de extração de IA do candidato (para diagnóstico na ficha).
final candidateExtractionErrorProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, candidatoId) {
  return ref.watch(talentBankServiceProvider).lastExtractionError(candidatoId);
});

/// F1.1 — Configuração da página de carreiras (slug, toggle, textos).
final portalConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.watch(talentBankServiceProvider).fetchPortalConfig();
});

/// F1.1 — Métricas de divulgação do portal (inscrições/conversão).
final metricasDivulgacaoProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  return ref.watch(talentBankServiceProvider).fetchMetricasDivulgacao();
});

/// RH-14 — Etapas do funil da org. Sem autoDispose de propósito:
/// é configuração de módulo, estável durante a sessão; invalidar
/// após edições na gestão de etapas.
final pipelineConfigProvider = FutureProvider<PipelineConfig>((ref) async {
  final rows =
      await ref.watch(talentBankServiceProvider).fetchPipelineEtapas();
  return PipelineConfig.fromRows(rows);
});

/// RH-13 — Usuários da org para o seletor de responsável.
final orgUsersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(talentBankServiceProvider).fetchOrgUsers();
});
