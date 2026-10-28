import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/workflow/models/workflow_card_model.dart';
import 'package:alinha_ja/features/workflow/models/workflow_supporting_models.dart';
import 'package:alinha_ja/features/workflow/models/workflow_enums.dart';
import 'package:alinha_ja/features/workflow/models/workflow_helpers.dart';

class WorkflowCardsArgs {
  final String channelId;
  final String? status;
  final WorkflowPriority? priority;
  final String? assignedTo;

  WorkflowCardsArgs({
    required this.channelId,
    this.status,
    this.priority,
    this.assignedTo,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkflowCardsArgs &&
          runtimeType == other.runtimeType &&
          channelId == other.channelId &&
          status == other.status &&
          priority == other.priority &&
          assignedTo == other.assignedTo;

  @override
  int get hashCode =>
      channelId.hashCode ^
      status.hashCode ^
      priority.hashCode ^
      assignedTo.hashCode;
}

class WorkflowState {
  final List<WorkflowCard> cards;
  final List<WorkflowStatusConfig> statusConfig;
  final bool isLoading;
  final String? error;
  final String viewMode;
  final String? filterStatus;
  final String? filterPriority;
  final String? filterAssignedTo;
  final bool? filterMyCards;
  final String searchQuery;
  final List<WorkflowCard> filteredCards;
  final Set<String> selectedCardIds;
  final bool showArchived;
  final Map<String, dynamic> channelMetadata;

  WorkflowState({
    this.cards = const [],
    this.statusConfig = const [],
    this.isLoading = false,
    this.error,
    this.viewMode = 'board',
    this.filterStatus,
    this.filterPriority,
    this.filterAssignedTo,
    this.filterMyCards,
    this.searchQuery = '',
    this.filteredCards = const [],
    this.selectedCardIds = const {},
    this.showArchived = false,
    this.channelMetadata = const {},
  });

  bool get isSelectionMode => selectedCardIds.isNotEmpty;

  String get assignmentMode =>
      channelMetadata['assignment_mode']?.toString() ?? 'operator_pool';

  List<String> get operatorIds {
    final raw = channelMetadata['operator_ids'];
    if (raw is List) {
      return raw
          .map((id) => id.toString())
          .where((id) => id.isNotEmpty)
          .toList();
    }
    return const [];
  }

  String? get defaultOperatorId {
    final raw = channelMetadata['default_operator_id']?.toString();
    if (raw != null && raw.isNotEmpty) return raw;
    if (assignmentMode == 'single_operator' && operatorIds.length == 1) {
      return operatorIds.first;
    }
    return null;
  }

  /// Nomes de etapa marcadas como cancelamento neste canal.
  ///
  /// Presets customizados podem chamar a etapa de "Recusado", "Encerrado" etc.,
  /// então a fonte de verdade é a flag `is_cancelled`; a comparação por nome
  /// sobrevive só como fallback para canais criados antes da migration.
  bool isCancelledStatus(String status) {
    final normalized = status.toLowerCase().trim();
    for (final config in statusConfig) {
      if (config.status.toLowerCase().trim() == normalized) {
        return config.isCancelled;
      }
    }
    return WorkflowStatusConfig.legacyCancelledNames.contains(normalized);
  }

  /// Etapa que encerra o card — concluída ou cancelada.
  ///
  /// Vale a flag `is_final` do banco; `isCancelledStatus` cobre a etapa de
  /// cancelamento, que também encerra sem ser "final" no sentido de sucesso.
  bool isClosedStatus(String status) {
    if (isCancelledStatus(status)) return true;
    final normalized = status.toLowerCase().trim();
    for (final config in statusConfig) {
      if (config.status.toLowerCase().trim() == normalized) {
        return config.isFinal;
      }
    }
    return false;
  }

  /// Card com prazo estourado e ainda em aberto.
  ///
  /// O cálculo de data continua em `isOverdue` (workflow_helpers); o que
  /// falta lá é a etapa, e a etapa é configuração do workspace — o helper
  /// não tem como saber. Sem esta combinação, um card concluído com atraso
  /// segue vermelho para sempre no histórico, que é o que acontece hoje nos
  /// chips das três visões.
  bool isCardOverdue(WorkflowCard card) =>
      isOverdue(card.dueDate) && !isClosedStatus(card.status);

  /// Quantos cards em aberto passaram do prazo. Alimenta o contador da aba.
  int overdueCount() => cards.where(isCardOverdue).length;

  bool canUserClaimCard(String userId, WorkflowCard card) {
    if (card.assignedTo != null) return false;
    if (card.requestedBy == userId) return false;
    if (isCancelledStatus(card.status)) return false;

    final configuredOperators = operatorIds;
    if (configuredOperators.isEmpty) return true;
    return configuredOperators.contains(userId);
  }

  WorkflowState copyWith({
    List<WorkflowCard>? cards,
    List<WorkflowStatusConfig>? statusConfig,
    bool? isLoading,
    String? error,
    String? viewMode,
    String? filterStatus,
    String? filterPriority,
    String? filterAssignedTo,
    bool? filterMyCards,
    String? searchQuery,
    List<WorkflowCard>? filteredCards,
    Set<String>? selectedCardIds,
    bool? showArchived,
    Map<String, dynamic>? channelMetadata,
    bool clearFilters = false,
    bool clearStatus = false,
    bool clearPriority = false,
    bool clearAssignedTo = false,
    bool clearMyCards = false,
    bool clearSelection = false,
  }) {
    return WorkflowState(
      cards: cards ?? this.cards,
      statusConfig: statusConfig ?? this.statusConfig,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      viewMode: viewMode ?? this.viewMode,
      filterStatus: clearFilters || clearStatus
          ? null
          : (filterStatus ?? this.filterStatus),
      filterPriority: clearFilters || clearPriority
          ? null
          : (filterPriority ?? this.filterPriority),
      filterAssignedTo: clearFilters || clearAssignedTo
          ? null
          : (filterAssignedTo ?? this.filterAssignedTo),
      filterMyCards: clearFilters || clearMyCards
          ? null
          : (filterMyCards ?? this.filterMyCards),
      searchQuery: clearFilters ? '' : (searchQuery ?? this.searchQuery),
      filteredCards: filteredCards ?? this.filteredCards,
      selectedCardIds:
          clearSelection ? const {} : (selectedCardIds ?? this.selectedCardIds),
      showArchived: showArchived ?? this.showArchived,
      channelMetadata: channelMetadata ?? this.channelMetadata,
    );
  }

  List<WorkflowCard> getFilteredCards(String? currentUserId) {
    var result = cards
        .where((c) =>
            !isCancelledStatus(c.status) &&
            c.status.toLowerCase() != 'arquivado')
        .toList();

    // Busca textual por título ou descrição
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result
          .where((c) =>
              c.title.toLowerCase().contains(q) ||
              (c.description?.toLowerCase().contains(q) ?? false) ||
              (c.clientName?.toLowerCase().contains(q) ?? false) ||
              (c.supplier?.toLowerCase().contains(q) ?? false) ||
              (c.osNumber?.toLowerCase().contains(q) ?? false) ||
              (c.orderNumber?.toLowerCase().contains(q) ?? false) ||
              (c.plate?.toLowerCase().contains(q) ?? false))
          .toList();
    }

    if (filterStatus != null && filterStatus!.isNotEmpty) {
      result = result.where((c) => c.status == filterStatus).toList();
    }
    if (filterPriority != null && filterPriority!.isNotEmpty) {
      result = result.where((c) {
        final pValue = c.priority.value;
        final pName = c.priority.name.toLowerCase();
        final pLabel = c.priority.label.toLowerCase();
        final filter = filterPriority!.toLowerCase();
        return pValue == filter || pName == filter || pLabel == filter;
      }).toList();
    }
    if (filterAssignedTo != null && filterAssignedTo!.isNotEmpty) {
      result = result.where((c) => c.assignedTo == filterAssignedTo).toList();
    }
    if (filterMyCards == true) {
      result = result
          .where((c) =>
              c.requestedBy == currentUserId || c.assignedTo == currentUserId)
          .toList();
    }

    return result;
  }

  /// Conta cards atribuídos ou criados pelo usuário atual (para badge)
  int myCardsCount(String? currentUserId) {
    if (currentUserId == null) return 0;
    return cards
        .where((c) =>
            !isCancelledStatus(c.status) &&
            (c.requestedBy == currentUserId || c.assignedTo == currentUserId))
        .length;
  }

  String? get initialStatus {
    if (statusConfig.isEmpty) return null;
    for (final config in statusConfig) {
      if (config.isInitial && !config.isCancelled) return config.status;
    }
    for (final config in statusConfig) {
      if (!config.isCancelled) return config.status;
    }
    return statusConfig.first.status;
  }

  Map<String, List<WorkflowCard>> get cardsByStatus {
    final map = <String, List<WorkflowCard>>{};
    for (final config in statusConfig) {
      if (!config.isCancelled &&
          config.status.toLowerCase() != 'arquivado') {
        map[config.status] =
            cards.where((c) => c.status == config.status).toList();
      }
    }
    return map;
  }

  List<WorkflowCard> get pinnedCards => cards.where((c) => c.isPinned).toList();
  List<WorkflowCard> get unpinnedCards =>
      cards.where((c) => !c.isPinned).toList();
}

class WorkflowNotification {
  final String title;
  final String message;
  final bool isUrgent;

  WorkflowNotification(this.title, this.message, {this.isUrgent = false});
}

class WorkflowNotifier extends StateNotifier<WorkflowState> {
  final String channelId;
  StreamSubscription? _cardsRealtimeSubscription;
  StreamSubscription? _statusRealtimeSubscription;
  Timer? _autoRefreshTimer;
  final _notificationController =
      StreamController<WorkflowNotification>.broadcast();

  Stream<WorkflowNotification> get notificationStream =>
      _notificationController.stream;

  WorkflowNotifier(this.channelId) : super(WorkflowState()) {
    loadChannelMetadata();
    loadCards();
    loadStatusConfig();
    _subscribeToRealtimeChanges();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _cardsRealtimeSubscription?.cancel();
    _statusRealtimeSubscription?.cancel();
    _autoRefreshTimer?.cancel();
    _notificationController.close();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      // Refresh silencioso
      loadCards(isSilent: true);
    });
  }

  /// B7: Subscribe to realtime changes on workflow_cards for this channel
  void _subscribeToRealtimeChanges() {
    try {
      _cardsRealtimeSubscription = supabase
          .from('workflow_cards')
          .stream(primaryKey: ['id'])
          .eq('channel_id', channelId)
          .listen(
            (_) {
              loadCards(isSilent: true);
            },
            onError: (error) {
              // Realtime stream can fail on web or when channel is unavailable.
              // Silently degrade — cards still work via manual fetch.
              debugPrint('Workflow Realtime: erro no stream — $error');
            },
          );
      _statusRealtimeSubscription = supabase
          .from('workflow_status_config')
          .stream(primaryKey: ['id'])
          .eq('channel_id', channelId)
          .listen(
            (_) {
              loadStatusConfig();
            },
            onError: (error) {
              debugPrint('Workflow Status Realtime: erro no stream - $error');
            },
          );
    } catch (e) {
      // Stream creation itself can throw on some platforms
      debugPrint('Workflow Realtime: falha ao criar stream — $e');
    }
  }

  Future<void> loadChannelMetadata() async {
    try {
      final response = await supabase
          .from('channels')
          .select('metadata')
          .eq('id', channelId)
          .maybeSingle();

      final metadata = response?['metadata'] is Map
          ? Map<String, dynamic>.from(response?['metadata'] as Map)
          : <String, dynamic>{};
      state = state.copyWith(channelMetadata: metadata);
    } catch (e) {
      debugPrint('Erro ao carregar configuracao do workflow: $e');
    }
  }

  bool _isFetching = false;

  Future<void> loadCards({bool isSilent = false}) async {
    if (_isFetching) return;
    _isFetching = true;
    if (!isSilent) {
      state = state.copyWith(isLoading: true, error: null);
    }
    try {
      final response = await supabase
          .from('workflow_cards')
          .select(
              '*, assigned_user:users!assigned_to(full_name), requester_user:users!requested_by(full_name)')
          .eq('channel_id', channelId)
          .eq('is_archived', state.showArchived)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);

      debugPrint(
          'Cards carregados do DB (archived=${state.showArchived}): ${response.length}');

      final newCards = (response as List)
          .map((json) => WorkflowCard.fromJson(json))
          .toList();

      // Checar notificações de novos eventos comparando com o estado antigo
      if (state.cards.isNotEmpty) {
        final currentUserId = supabase.auth.currentUser?.id;
        for (final newCard in newCards) {
          final oldCard = state.cards
              .cast<WorkflowCard?>()
              .firstWhere((c) => c?.id == newCard.id, orElse: () => null);

          // 1. Foi atribuído a mim agora
          if (newCard.assignedTo == currentUserId &&
              (oldCard == null || oldCard.assignedTo != currentUserId)) {
            _notificationController.add(WorkflowNotification(
              'Card Atribuído a Você',
              newCard.title,
            ));
          }
          // 2. Novo card urgente criado (e não fui eu que criei)
          else if (oldCard == null &&
              (newCard.priority.value == 'urgent' ||
                  newCard.priority.value == 'urgente') &&
              newCard.requestedBy != currentUserId) {
            _notificationController.add(WorkflowNotification(
              'Novo Card Urgente!',
              newCard.title,
              isUrgent: true,
            ));
          }
        }
      }

      state = state.copyWith(cards: newCards, isLoading: false);
      _updateFilteredCards();
    } catch (e) {
      debugPrint('Erro ao carregar cards: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    } finally {
      _isFetching = false;
    }
  }

  void toggleArchived() {
    state = state.copyWith(showArchived: !state.showArchived);
    loadCards();
  }

  Future<void> loadStatusConfig() async {
    try {
      final response = await supabase
          .from('workflow_status_config')
          .select('*')
          .eq('channel_id', channelId)
          .order('status_order', ascending: true);

      final configs = (response as List)
          .map((json) => WorkflowStatusConfig.fromJson(json))
          .toList();

      if (configs.isEmpty) {
        // Fallback robusto nativo para evitar Boards Vazio caso a migration não tenha rodado
        configs.addAll([
          WorkflowStatusConfig(
              id: 'fallback_1',
              channelId: channelId,
              status: 'Solicitação aberta',
              statusOrder: 1,
              color: '#3B82F6',
              icon: 'add_circle'),
          WorkflowStatusConfig(
              id: 'fallback_2',
              channelId: channelId,
              status: 'Em análise',
              statusOrder: 2,
              color: '#F59E0B',
              icon: 'search'),
          WorkflowStatusConfig(
              id: 'fallback_3',
              channelId: channelId,
              status: 'Aguardando Solicitante',
              statusOrder: 3,
              color: '#8B5CF6',
              icon: 'hourglass_empty'),
          WorkflowStatusConfig(
              id: 'fallback_final',
              channelId: channelId,
              status: 'Finalizado',
              statusOrder: 4,
              color: '#10B981',
              icon: 'task_alt',
              isFinal: true),
        ]);
      }

      state = state.copyWith(statusConfig: configs);
    } catch (e) {
      debugPrint('Erro ao carregar config de status: $e');
    }
  }

  Future<void> createCard(WorkflowCard card) async {
    try {
      // Otimismo: Adiciona localmente antes de salvar
      state = state.copyWith(cards: [card, ...state.cards]);
      _updateFilteredCards();

      final res = await supabase
          .from('workflow_cards')
          .insert(card.toJson())
          .select()
          .single();
      // Atualiza o card com o ID real retornado
      final realCard = WorkflowCard.fromJson(res);
      state = state.copyWith(
          cards:
              state.cards.map((c) => c.id == card.id ? realCard : c).toList());
      _updateFilteredCards();
    } catch (e) {
      debugPrint('Erro ao criar card: $e');
      loadCards(); // Fallback
      rethrow;
    }
  }

  Future<void> updateCardStatus(String cardId, String newStatus,
      {String? observations}) async {
    if (!_isAllowedStatus(newStatus)) {
      throw Exception(
          'Status "$newStatus" nao esta configurado neste workflow.');
    }
    _throwIfRequesterOperation(cardId);
    // Permissão: solicitante, responsável, ou qualquer membro do canal pode mover
    // A RLS do Supabase garante a segurança real no backend
    // Removido bloqueio client-side que impedia gestores de operar cards

    // P1: Optimistic local update
    final previousCards = state.cards;
    state = state.copyWith(
      cards: state.cards
          .map((c) => c.id == cardId ? c.copyWith(status: newStatus) : c)
          .toList(),
    );
    _updateFilteredCards();

    try {
      await supabase.rpc('update_workflow_card_status', params: {
        'p_card_id': cardId,
        'p_new_status': newStatus,
        if (observations != null) 'p_observations': observations,
      });
    } catch (e) {
      // Rollback on error
      state = state.copyWith(cards: previousCards);
      _updateFilteredCards();
      debugPrint('Erro ao atualizar status: $e');
      rethrow;
    }
  }

  bool _isAllowedStatus(String status) {
    if (state.isCancelledStatus(status)) return true;
    if (state.statusConfig.isEmpty) return true;
    return state.statusConfig
        .any((s) => s.status.toLowerCase() == status.toLowerCase());
  }

  /// Etapa de cancelamento configurada no canal (se houver).
  String? getCancelledStatus() {
    for (final config in state.statusConfig) {
      if (config.isCancelled) return config.status;
    }
    return null;
  }

  String? getFinalStatus() {
    if (state.statusConfig.isEmpty) return null;

    final finalStatuses = state.statusConfig
        .where((s) => !s.isCancelled && s.isFinal)
        .toList();
    if (finalStatuses.isNotEmpty) return finalStatuses.first.status;

    final activeStatuses =
        state.statusConfig.where((s) => !s.isCancelled).toList();
    if (activeStatuses.isEmpty) return null;
    return activeStatuses.last.status;
  }

  Future<void> completeCard(String cardId, {String? observations}) async {
    final finalStatus = getFinalStatus();
    if (finalStatus == null) {
      throw Exception('Nenhum status final configurado para este workflow.');
    }
    await updateCardStatus(cardId, finalStatus, observations: observations);
  }

  void _updateFilteredCards() {
    final myId = supabase.auth.currentUser?.id;
    state = state.copyWith(filteredCards: state.getFilteredCards(myId));
  }

  Future<void> togglePin(String cardId) async {
    final card = state.cards.firstWhere((c) => c.id == cardId,
        orElse: () => throw Exception('Card não encontrado.'));
    _throwIfRequesterOperation(cardId);
    final newPinned = !card.isPinned;
    // P1: Optimistic local update
    final previousCards = state.cards;
    state = state.copyWith(
      cards: state.cards
          .map((c) => c.id == cardId ? c.copyWith(isPinned: newPinned) : c)
          .toList(),
    );
    try {
      final result = await supabase
          .from('workflow_cards')
          .update({
            'is_pinned': newPinned,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', cardId)
          .select();

      if (result.isEmpty) {
        state = state.copyWith(cards: previousCards);
        throw Exception("Operação negada.");
      }
    } catch (e) {
      state = state.copyWith(cards: previousCards);
      debugPrint('Erro ao fixar card: $e');
      rethrow;
    }
  }

  Future<void> assignCard(String cardId, String? userId) async {
    try {
      _throwIfRequesterOperation(cardId);
      final card = state.cards.firstWhere((c) => c.id == cardId);
      if (userId != null && userId == card.requestedBy) {
        throw Exception(
            'O solicitante nao pode ser responsavel pelo proprio card.');
      }
      final result = await supabase
          .from('workflow_cards')
          .update({
            'assigned_to': userId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', cardId)
          .select();

      if (result.isEmpty) {
        throw Exception("Operação negada.");
      }
      await loadCards();
    } catch (e) {
      debugPrint('Erro ao atribuir card: $e');
      rethrow;
    }
  }

  Future<void> claimCard(String cardId) async {
    try {
      _throwIfRequesterOperation(cardId);
      await supabase.rpc('claim_workflow_card', params: {
        'p_card_id': cardId,
      });
      await loadCards();
    } catch (e) {
      debugPrint('Erro ao assumir card: $e');
      rethrow;
    }
  }

  Future<void> archiveCard(String cardId) async {
    _throwIfRequesterOperation(cardId);
    // P1: Optimistic local update — remove card from UI immediately
    final previousCards = state.cards;
    state = state.copyWith(
      cards: state.cards.where((c) => c.id != cardId).toList(),
    );
    try {
      final result = await supabase
          .from('workflow_cards')
          .update({
            'is_archived': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', cardId)
          .select();

      if (result.isEmpty) {
        state = state.copyWith(cards: previousCards);
        throw Exception(
            "Operação negada. Apenas o responsável, o solicitante original, ou um admin podem arquivar este card.");
      }
    } catch (e) {
      state = state.copyWith(cards: previousCards);
      debugPrint('Erro ao arquivar card: $e');
      rethrow;
    }
  }

  Future<void> deleteCard(String cardId) async {
    try {
      _throwIfRequesterOperation(cardId);
      await supabase.from('workflow_cards').delete().eq('id', cardId);
      await loadCards();
    } catch (e) {
      debugPrint('Erro ao excluir card: $e');
      rethrow;
    }
  }

  void _throwIfRequesterOperation(String cardId) {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) throw Exception('Usuário não autenticado.');

    final matchingCards = state.cards.where((c) => c.id == cardId);
    if (matchingCards.isNotEmpty && matchingCards.first.requestedBy == myId) {
      throw Exception(
          'O solicitante nao pode operar o proprio card. Aguarde a conclusao para interagir.');
    }
  }

  void setViewMode(String mode) {
    state = state.copyWith(viewMode: mode);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    _updateFilteredCards();
  }

  void setFilter(
      {String? status, String? priority, String? assignedTo, bool? myCards}) {
    state = state.copyWith(
      filterStatus: status,
      filterPriority: priority,
      filterAssignedTo: assignedTo,
      filterMyCards: myCards,
    );
    _updateFilteredCards();
  }

  void clearFilters() {
    state = state.copyWith(clearFilters: true);
    _updateFilteredCards();
  }

  /// Obtém o próximo status na sequência configurada.
  String? getNextStatus(String currentStatus) {
    final statuses = state.statusConfig.where((s) => !s.isCancelled).toList();
    final idx = statuses.indexWhere((s) => s.status == currentStatus);
    if (idx < 0 || idx >= statuses.length - 1) return null;
    return statuses[idx + 1].status;
  }

  /// Obtém o status anterior na sequência configurada.
  String? getPreviousStatus(String currentStatus) {
    final statuses = state.statusConfig.where((s) => !s.isCancelled).toList();
    final idx = statuses.indexWhere((s) => s.status == currentStatus);
    if (idx <= 0) return null;
    return statuses[idx - 1].status;
  }

  // ── Bulk Selection ──────────────────────────────────────────

  void toggleCardSelection(String cardId) {
    final updated = Set<String>.from(state.selectedCardIds);
    if (updated.contains(cardId)) {
      updated.remove(cardId);
    } else {
      updated.add(cardId);
    }
    state = state.copyWith(selectedCardIds: updated);
  }

  void selectAllVisible() {
    final myId = supabase.auth.currentUser?.id;
    final visibleIds = state.getFilteredCards(myId).map((c) => c.id).toSet();
    state = state.copyWith(selectedCardIds: visibleIds);
  }

  void clearSelection() {
    state = state.copyWith(clearSelection: true);
  }

  Future<void> bulkUpdateStatus(String newStatus) async {
    final ids = state.selectedCardIds.toList();
    for (final id in ids) {
      try {
        await updateCardStatus(id, newStatus);
      } catch (e) {
        debugPrint('Bulk move falhou para $id: $e');
      }
    }
    state = state.copyWith(clearSelection: true);
  }

  Future<void> bulkArchive() async {
    final ids = state.selectedCardIds.toList();
    for (final id in ids) {
      try {
        await archiveCard(id);
      } catch (e) {
        debugPrint('Bulk archive falhou para $id: $e');
      }
    }
    state = state.copyWith(clearSelection: true);
  }

  Future<List<WorkflowCardHistory>> getCardHistory(String cardId) async {
    try {
      final response = await supabase
          .from('workflow_card_history')
          .select('*, users!user_id(full_name)')
          .eq('card_id', cardId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((json) => WorkflowCardHistory.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Erro ao carregar histórico: $e');
      return [];
    }
  }

  Future<List<WorkflowCardComment>> getCardComments(String cardId) async {
    try {
      final response = await supabase
          .from('workflow_card_comments')
          .select('*, users!user_id(full_name, avatar_url)')
          .eq('card_id', cardId)
          .order('created_at', ascending: true);
      return (response as List).map((json) {
        final map = Map<String, dynamic>.from(json);
        // Mapear dados do join para campos esperados pelo model
        if (map['users'] is Map) {
          map['user_name'] = map['users']['full_name'];
          map['user_avatar'] = map['users']['avatar_url'];
        }
        return WorkflowCardComment.fromJson(map);
      }).toList();
    } catch (e) {
      debugPrint('Erro ao carregar comentários: $e');
      return [];
    }
  }

  /// Comenta no card.
  ///
  /// Solicitante só comenta com o card encerrado — a mesma regra da policy
  /// de INSERT e do campo habilitado na tela. Antes o solicitante era barrado
  /// sempre aqui, e o erro era engolido: o campo limpava e o texto se perdia
  /// sem aviso. Agora a falha sobe para a tela exibir.
  Future<void> addComment(String cardId, String content) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Usuário não autenticado.');

    final card = state.cards.where((c) => c.id == cardId).firstOrNull;
    // Etapa final (is_final), exatamente como a policy — cancelado não conta.
    final isFinal = card != null &&
        state.statusConfig.any((s) => s.status == card.status && s.isFinal);
    if (card != null && card.requestedBy == userId && !isFinal) {
      throw Exception(
          'O solicitante pode comentar depois que o card for concluído.');
    }

    await supabase.from('workflow_card_comments').insert({
      'card_id': cardId,
      'user_id': userId,
      'content': content,
    });
  }
}

final workflowProvider =
    StateNotifierProvider.family<WorkflowNotifier, WorkflowState, String>(
  (ref, channelId) => WorkflowNotifier(channelId),
);
