import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/core/models/announcement_spec.dart';
import 'package:alinha_ja/core/models/message_extras.dart';

void main() {
  group('AnnouncementSpec', () {
    test('faz round-trip completo pelo metadata', () {
      final validUntil = DateTime(2026, 9, 1, 23, 59, 59);
      final spec = AnnouncementSpec(
        priority: AnnouncementPriority.urgent,
        validUntil: validUntil,
        pinned: true,
        requiresAck: true,
        audience: const AnnouncementAudience(
          departments: [AudienceTarget(id: 'dep-1', name: 'Financeiro')],
          branches: [AudienceTarget(id: 'fil-2', name: 'Matriz')],
        ),
        attachment: const AnnouncementAttachment(
          url: 'https://exemplo/politica.pdf',
          name: 'politica.pdf',
          sizeBytes: 2048,
        ),
        action: const AnnouncementAction(
          kind: AnnouncementActionKind.link,
          label: 'Ler política',
          value: 'https://exemplo/politica',
        ),
      );

      final restored = AnnouncementSpec.fromMetadata(spec.toMetadata());

      expect(restored.priority, AnnouncementPriority.urgent);
      expect(restored.validUntil, validUntil);
      expect(restored.pinned, isTrue);
      expect(restored.requiresAck, isTrue);
      expect(restored.audience.departments.single.name, 'Financeiro');
      expect(restored.audience.branches.single.name, 'Matriz');
      expect(restored.attachment?.name, 'politica.pdf');
      expect(restored.attachment?.readableSize, '2.0 KB');
      expect(restored.action?.label, 'Ler política');
    });

    test('validade usa valid_until, nunca expires_at', () {
      final metadata = AnnouncementSpec(
        priority: AnnouncementPriority.info,
        validUntil: DateTime(2026, 12, 31),
      ).toMetadata();

      // `expires_at` já significou "apague esta mensagem" no recurso de
      // mensagem temporária; reaproveitar a chave faria o anúncio sumir.
      expect(metadata.containsKey('valid_until'), isTrue);
      expect(metadata.containsKey('expires_at'), isFalse);
    });

    test('anúncio antigo sem prioridade não quebra e vira Importante', () {
      final legacy = <String, dynamic>{'type': 'announcement'};
      final spec = AnnouncementSpec.fromMetadata(legacy);

      expect(spec.priority, AnnouncementPriority.important);
      expect(spec.requiresAck, isFalse);
      expect(spec.audience.isEveryone, isTrue);
      expect(spec.isExpired, isFalse);
    });

    test('expirado é decidido pela data, não por flag', () {
      final past = AnnouncementSpec(
        validUntil: DateTime.now().subtract(const Duration(days: 1)),
      );
      final future = AnnouncementSpec(
        validUntil: DateTime.now().add(const Duration(days: 1)),
      );

      expect(past.isExpired, isTrue);
      expect(future.isExpired, isFalse);
      expect(const AnnouncementSpec().isExpired, isFalse);
    });

    test('público vazio é "todos" e não grava chave', () {
      final metadata = const AnnouncementSpec().toMetadata();

      expect(metadata.containsKey('audience'), isFalse);
      expect(const AnnouncementAudience().isEveryone, isTrue);
    });

    test('ação sem rótulo é descartada na leitura', () {
      expect(
        AnnouncementAction.fromMap({'kind': 'link', 'label': ''}),
        isNull,
      );
      expect(AnnouncementAction.fromMap({'kind': 'none'}), isNull);
      expect(AnnouncementAction.fromMap(null), isNull);
    });

    test('cada prioridade tem aparência própria', () {
      final colors = <int>{};
      for (final priority in AnnouncementPriority.values) {
        final style = announcementPriorities[priority]!;
        expect(style.label, isNotEmpty);
        colors.add(style.color.toARGB32());
      }
      // Prioridades que compartilham cor não comunicam nada.
      expect(colors.length, AnnouncementPriority.values.length);
    });
  });

  group('Quadro branco no metadata', () {
    test('card reconhece o quadro e guarda id e título', () {
      final metadata = MessageExtras.whiteboard(
        boardId: 'board-1',
        title: 'Layout da loja',
      );

      expect(metadata.isWhiteboard, isTrue);
      expect(metadata.isStructured, isTrue);
      expect(metadata.whiteboardId, 'board-1');
      expect(metadata.whiteboardTitle, 'Layout da loja');
    });

    test('anúncio não é confundido com card estruturado', () {
      final metadata = const AnnouncementSpec().toMetadata();

      // Anúncio tem bolha própria; se entrasse em isStructured, o
      // StructuredMessageCard tentaria desenhá-lo e cairia no texto puro.
      expect(metadata.isStructured, isFalse);
    });
  });
}
