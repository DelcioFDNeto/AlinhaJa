import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/features/workflow/models/workflow_card_model.dart';
import 'package:alinha_ja/features/workflow/models/workflow_enums.dart';
import 'package:alinha_ja/features/workflow/providers/my_operation_provider.dart';

/// Cobre o agrupamento da caixa de entrada transversal ("Minha operação").
///
/// `groupMyCards` é pura de propósito: a consulta ao Supabase fica no provider
/// e a regra de urgência — que é o que erra na prática — fica testável.
MyCard _card({
  required String id,
  DateTime? dueDate,
  bool isClosed = false,
  String status = 'em_andamento',
  String channelName = 'Faturamento',
}) {
  final now = DateTime(2026, 8, 21);
  return MyCard(
    card: WorkflowCard(
      id: id,
      channelId: 'ch1',
      cardType: WorkflowCardType.generic,
      title: 'Card $id',
      status: status,
      dueDate: dueDate,
      createdAt: now,
      updatedAt: now,
    ),
    channelId: 'ch1',
    channelName: channelName,
    isClosed: isClosed,
  );
}

void main() {
  final hoje = DateTime.now();
  final ontem = hoje.subtract(const Duration(days: 1));
  final amanha = hoje.add(const Duration(days: 3));

  group('groupMyCards', () {
    test('separa atraso, hoje, próximos e sem prazo', () {
      final grouped = groupMyCards([
        _card(id: 'a', dueDate: ontem),
        _card(id: 'b', dueDate: hoje),
        _card(id: 'c', dueDate: amanha),
        _card(id: 'd'),
      ]);

      expect(grouped[OperationBucket.atrasados]!.single.card.id, 'a');
      expect(grouped[OperationBucket.hoje]!.single.card.id, 'b');
      expect(grouped[OperationBucket.proximos]!.single.card.id, 'c');
      expect(grouped[OperationBucket.semPrazo]!.single.card.id, 'd');
    });

    test('card encerrado sai do funil mesmo vencido', () {
      final grouped = groupMyCards([
        _card(id: 'fechado', dueDate: ontem, isClosed: true),
      ]);

      expect(grouped[OperationBucket.atrasados], isNull);
      expect(grouped[OperationBucket.concluidos]!.single.card.id, 'fechado');
    });

    test('vencer hoje não conta como atraso', () {
      final grouped = groupMyCards([_card(id: 'x', dueDate: hoje)]);
      expect(grouped[OperationBucket.atrasados], isNull);
      expect(grouped[OperationBucket.hoje], hasLength(1));
    });

    test('lista vazia não inventa grupo', () {
      expect(groupMyCards(const []), isEmpty);
    });

    test('preserva a ordem recebida dentro do grupo', () {
      final grouped = groupMyCards([
        _card(id: 'p1', dueDate: ontem),
        _card(id: 'p2', dueDate: ontem.subtract(const Duration(days: 4))),
      ]);

      expect(
        grouped[OperationBucket.atrasados]!.map((c) => c.card.id).toList(),
        ['p1', 'p2'],
      );
    });
  });

  group('MyCard.isOverdueNow', () {
    test('vencido e aberto está em atraso', () {
      expect(_card(id: 'a', dueDate: ontem).isOverdueNow, isTrue);
    });

    test('vencido mas encerrado não cobra prazo', () {
      expect(
        _card(id: 'a', dueDate: ontem, isClosed: true).isOverdueNow,
        isFalse,
      );
    });

    test('sem prazo nunca está em atraso', () {
      expect(_card(id: 'a').isOverdueNow, isFalse);
    });
  });

  group('OperationBucket', () {
    test('todo grupo tem rótulo próprio', () {
      final labels = OperationBucket.values.map((b) => b.label).toSet();
      expect(labels, hasLength(OperationBucket.values.length));
      expect(labels.any((l) => l.trim().isEmpty), isFalse);
    });
  });
}
