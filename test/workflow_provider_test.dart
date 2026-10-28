import 'package:flutter_test/flutter_test.dart';
import 'package:alinha_ja/features/workflow/models/workflow_card_model.dart';
import 'package:alinha_ja/features/workflow/models/workflow_supporting_models.dart';
import 'package:alinha_ja/features/workflow/models/workflow_enums.dart';
import 'package:alinha_ja/features/workflow/providers/workflow_provider.dart';

void main() {
  group('WorkflowState', () {
    test('should have default values', () {
      final state = WorkflowState();

      expect(state.cards, isEmpty);
      expect(state.statusConfig, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.viewMode, equals('board'));
      expect(state.filterStatus, isNull);
      expect(state.filterPriority, isNull);
      expect(state.filterAssignedTo, isNull);
      expect(state.filterMyCards, isNull);
    });

    test('copyWith should create new state with updated values', () {
      final state = WorkflowState();
      final newState = state.copyWith(isLoading: true, viewMode: 'list');

      expect(newState.isLoading, isTrue);
      expect(newState.viewMode, equals('list'));
      expect(state.isLoading, isFalse);
    });

    test('copyWith with clearFilters should reset all filters', () {
      final state = WorkflowState(
        filterStatus: 'open',
        filterPriority: 'high',
        filterMyCards: true,
      );
      final newState = state.copyWith(clearFilters: true);

      expect(newState.filterStatus, isNull);
      expect(newState.filterPriority, isNull);
      expect(newState.filterMyCards, isNull);
    });

    test('filteredCards should filter by status', () {
      final card1 = WorkflowCard(
        id: 'card-1',
        channelId: 'ch-1',
        cardType: WorkflowCardType.generic,
        title: 'Card 1',
        status: 'open',
        priority: WorkflowPriority.low,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final card2 = WorkflowCard(
        id: 'card-2',
        channelId: 'ch-1',
        cardType: WorkflowCardType.generic,
        title: 'Card 2',
        status: 'closed',
        priority: WorkflowPriority.high,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final state = WorkflowState(
        cards: [card1, card2],
        filterStatus: 'open',
      );

      expect(state.getFilteredCards(null).length, equals(1));
      expect(state.getFilteredCards(null).first.id, equals('card-1'));
    });

    test('filteredCards should filter by priority', () {
      final card1 = WorkflowCard(
        id: 'card-1',
        channelId: 'ch-1',
        cardType: WorkflowCardType.generic,
        title: 'Card 1',
        status: 'open',
        priority: WorkflowPriority.low,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final card2 = WorkflowCard(
        id: 'card-2',
        channelId: 'ch-1',
        cardType: WorkflowCardType.generic,
        title: 'Card 2',
        status: 'open',
        priority: WorkflowPriority.high,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final state = WorkflowState(
        cards: [card1, card2],
        filterPriority: 'high',
      );

      expect(state.getFilteredCards(null).length, equals(1));
      expect(state.getFilteredCards(null).first.priority,
          equals(WorkflowPriority.high));
    });

    test('cardsByStatus should group cards by status', () {
      final config1 = WorkflowStatusConfig(
        id: 'cfg-1',
        channelId: 'ch-1',
        status: 'open',
        statusOrder: 1,
        color: '#3B82F6',
        icon: 'add_circle',
      );
      final config2 = WorkflowStatusConfig(
        id: 'cfg-2',
        channelId: 'ch-1',
        status: 'closed',
        statusOrder: 2,
        color: '#10B981',
        icon: 'task_alt',
      );

      final card1 = WorkflowCard(
        id: 'card-1',
        channelId: 'ch-1',
        cardType: WorkflowCardType.generic,
        title: 'Card 1',
        status: 'open',
        priority: WorkflowPriority.low,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final card2 = WorkflowCard(
        id: 'card-2',
        channelId: 'ch-1',
        cardType: WorkflowCardType.generic,
        title: 'Card 2',
        status: 'closed',
        priority: WorkflowPriority.high,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final state = WorkflowState(
        cards: [card1, card2],
        statusConfig: [config1, config2],
      );

      expect(state.cardsByStatus['open']?.length, equals(1));
      expect(state.cardsByStatus['closed']?.length, equals(1));
    });

    test('pinnedCards should return only pinned cards', () {
      final card1 = WorkflowCard(
        id: 'card-1',
        channelId: 'ch-1',
        cardType: WorkflowCardType.generic,
        title: 'Card 1',
        status: 'open',
        priority: WorkflowPriority.low,
        isPinned: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final card2 = WorkflowCard(
        id: 'card-2',
        channelId: 'ch-1',
        cardType: WorkflowCardType.generic,
        title: 'Card 2',
        status: 'open',
        priority: WorkflowPriority.high,
        isPinned: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final state = WorkflowState(cards: [card1, card2]);

      expect(state.pinnedCards.length, equals(1));
      expect(state.pinnedCards.first.id, equals('card-1'));
    });

    test('initialStatus should return first status config', () {
      final config1 = WorkflowStatusConfig(
        id: 'cfg-1',
        channelId: 'ch-1',
        status: 'open',
        statusOrder: 1,
        color: '#3B82F6',
        icon: 'add_circle',
      );
      final config2 = WorkflowStatusConfig(
        id: 'cfg-2',
        channelId: 'ch-1',
        status: 'closed',
        statusOrder: 2,
        color: '#10B981',
        icon: 'task_alt',
      );

      final state = WorkflowState(statusConfig: [config1, config2]);

      expect(state.initialStatus, equals('open'));
    });
  });

  group('WorkflowCardsArgs', () {
    test('should correctly compare equal args', () {
      final args1 = WorkflowCardsArgs(channelId: 'ch-123');
      final args2 = WorkflowCardsArgs(channelId: 'ch-123');

      expect(args1, equals(args2));
      expect(args1.hashCode, equals(args2.hashCode));
    });

    test('should differentiate args with different filters', () {
      final args1 = WorkflowCardsArgs(
          channelId: 'ch-123', priority: WorkflowPriority.high);
      final args2 = WorkflowCardsArgs(
          channelId: 'ch-123', priority: WorkflowPriority.low);

      expect(args1, isNot(equals(args2)));
    });
  });
}
