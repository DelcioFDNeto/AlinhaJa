import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/core/models/message_extras.dart';
import 'package:alinha_ja/features/whiteboard/models/whiteboard_stroke.dart';

void main() {
  group('WhiteboardStroke', () {
    test('serializa e deserializa traço mantendo coordenadas e ferramenta', () {
      final stroke = WhiteboardStroke(
        id: 'stroke-123',
        whiteboardId: 'board-456',
        authorId: 'user-789',
        points: const [Offset(100, 200), Offset(150, 250)],
        color: const Color(0xFF1E88E5),
        width: 4.0,
        tool: WhiteboardTool.pen,
        createdAt: DateTime.utc(2026, 8, 10, 15, 0),
      );

      final map = stroke.toInsert();

      expect(map['id'], 'stroke-123');
      expect(map['whiteboard_id'], 'board-456');
      expect(map['author_id'], 'user-789');
      expect(map['tool'], 'pen');
      expect(map['color'], '#1e88e5');
      expect(map['points'], [
        {'x': 100.0, 'y': 200.0},
        {'x': 150.0, 'y': 250.0},
      ]);

      final restored = WhiteboardStroke.fromJson({
        ...map,
        'created_at': stroke.createdAt.toIso8601String(),
      });

      expect(restored.id, stroke.id);
      expect(restored.points.length, 2);
      expect(restored.points.first.dx, 100.0);
      expect(restored.points.first.dy, 200.0);
      expect(restored.tool, WhiteboardTool.pen);
    });

    test('ferramentas desconhecidas caem no fallback da caneta', () {
      final restored = WhiteboardStroke.fromJson(const {
        'id': 's1',
        'tool': 'unknown_tool',
      });

      expect(restored.tool, WhiteboardTool.pen);
    });
  });

  group('MessageExtras whiteboard', () {
    test('cria e identifica metadata de quadro branco', () {
      final metadata = MessageExtras.whiteboard(
        boardId: 'board-001',
        title: 'Layout da loja',
      );

      expect(metadata.isWhiteboard, isTrue);
      expect(metadata.isStructured, isTrue);
      expect(metadata.whiteboardId, 'board-001');
      expect(metadata.whiteboardTitle, 'Layout da loja');
    });
  });
}
