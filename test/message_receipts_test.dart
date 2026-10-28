import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/core/models/message_receipts.dart';

Map<String, dynamic> _pessoa(String nome, String estado, {String? at}) => {
      'user_id': 'u-$nome',
      'full_name': nome,
      'avatar_url': null,
      'state': estado,
      'at': at,
    };

void main() {
  group('MessageReceiptSummary', () {
    test('lê a resposta do RPC com contagens e destinatários', () {
      final summary = MessageReceiptSummary.fromJson({
        'message_id': 'm1',
        'scope': 'channel',
        'sender_id': 'u-chefe',
        'sent_at': '2026-08-20T15:00:00Z',
        'recipient_count': 3,
        'read_count': 1,
        'delivered_count': 1,
        'pending_count': 1,
        'recipients': [
          _pessoa('Ana', 'read', at: '2026-08-20T15:05:00Z'),
          _pessoa('Bruno', 'delivered', at: '2026-08-20T15:01:00Z'),
          _pessoa('Carla', 'pending'),
        ],
      });

      expect(summary.scope, ReceiptScope.channel);
      expect(summary.recipientCount, 3);
      expect(summary.readCount, 1);
      expect(summary.recipients.length, 3);
      expect(summary.whereState(ReceiptState.read).single.fullName, 'Ana');
      expect(summary.whereState(ReceiptState.pending).single.at, isNull);
      expect(summary.everyoneRead, isFalse);
      expect(summary.isOneToOne, isFalse);
    });

    test('everyoneRead só vale com destinatário e todos lidos', () {
      MessageReceiptSummary build(int total, int lidos) =>
          MessageReceiptSummary.fromJson({
            'message_id': 'm',
            'scope': 'chat',
            'recipient_count': total,
            'read_count': lidos,
            'delivered_count': 0,
            'pending_count': total - lidos,
            'recipients': const [],
          });

      expect(build(4, 4).everyoneRead, isTrue);
      expect(build(4, 3).everyoneRead, isFalse);
      // Conversa sem mais ninguém não é "todos leram" — é ninguém para ler.
      expect(build(0, 0).everyoneRead, isFalse);
    });

    test('DM é reconhecida por ter um destinatário só', () {
      final dm = MessageReceiptSummary.fromJson({
        'message_id': 'm',
        'scope': 'chat',
        'recipient_count': 1,
        'read_count': 1,
        'delivered_count': 0,
        'pending_count': 0,
        'recipients': [_pessoa('Ana', 'read', at: '2026-08-20T15:05:00Z')],
      });

      expect(dm.isOneToOne, isTrue);
    });

    test('resposta incompleta não quebra a folha', () {
      // O RPC sempre devolve o objeto completo, mas a UI abre em cima de
      // dados de rede: um campo faltando não pode virar exceção na tela.
      final vazio = MessageReceiptSummary.fromJson(const {});

      expect(vazio.recipientCount, 0);
      expect(vazio.recipients, isEmpty);
      expect(vazio.scope, ReceiptScope.chat);
      expect(vazio.sentAt, isNull);
    });

    test('estado desconhecido é tratado como pendente', () {
      final r = MessageReceipt.fromJson(_pessoa('Ana', 'quem_sabe'));
      expect(r.state, ReceiptState.pending);
    });

    test('nome vazio vira rótulo genérico em vez de linha em branco', () {
      final r = MessageReceipt.fromJson(const {
        'user_id': 'u1',
        'full_name': '   ',
        'state': 'read',
      });
      expect(r.fullName, 'Usuário');
    });
  });

  group('ReceiptScope', () {
    test('rpcValue casa com o p_scope aceito pela função', () {
      expect(ReceiptScope.chat.rpcValue, 'chat');
      expect(ReceiptScope.channel.rpcValue, 'channel');
    });
  });
}
