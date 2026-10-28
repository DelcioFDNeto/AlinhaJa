import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/features/whiteboard/models/whiteboard_stroke.dart';
import 'package:alinha_ja/features/whiteboard/ui/widgets/whiteboard_painter.dart';

const _board = Rect.fromLTWH(0, 0, 400, 400);

WhiteboardStroke _saved(String id) => WhiteboardStroke(
      id: id,
      whiteboardId: 'b',
      authorId: 'u',
      points: const [Offset(0, 0), Offset(10, 10)],
      color: const Color(0xFF000000),
      width: 3,
      tool: WhiteboardTool.pen,
      createdAt: DateTime.utc(2026, 8, 10),
    );

void main() {
  group('WhiteboardPainter.shouldRepaint', () {
    test('repinta enquanto o traço ao vivo cresce', () {
      // A tela mantém UMA lista e vai adicionando ponto nela (`_current.add`).
      // Comparar as listas por identidade nunca acusa mudança, e o traço só
      // apareceria quando o dedo levantasse — desenhar ficaria "cego".
      final live = <Offset>[const Offset(0, 0)];

      final before = WhiteboardPainter(
        strokes: const [],
        board: _board,
        liveStroke: live,
      );

      live.add(const Offset(5, 5));

      final after = WhiteboardPainter(
        strokes: const [],
        board: _board,
        liveStroke: live,
      );

      expect(after.shouldRepaint(before), isTrue);
    });

    test('repinta quando um traço é gravado ou desfeito', () {
      final one = WhiteboardPainter(strokes: [_saved('a')], board: _board);
      final two = WhiteboardPainter(
        strokes: [_saved('a'), _saved('b')],
        board: _board,
      );

      expect(two.shouldRepaint(one), isTrue);
      expect(one.shouldRepaint(two), isTrue);
    });

    test('repinta ao trocar cor, espessura ou ferramenta', () {
      final pen = WhiteboardPainter(strokes: const [], board: _board);

      expect(
        WhiteboardPainter(
          strokes: const [],
          board: _board,
          liveColor: const Color(0xFFE53935),
        ).shouldRepaint(pen),
        isTrue,
      );
      expect(
        WhiteboardPainter(strokes: const [], board: _board, liveWidth: 8)
            .shouldRepaint(pen),
        isTrue,
      );
      expect(
        WhiteboardPainter(
          strokes: const [],
          board: _board,
          liveTool: WhiteboardTool.eraser,
        ).shouldRepaint(pen),
        isTrue,
      );
    });

    test('não repinta à toa quando nada mudou', () {
      const shared = <Offset>[Offset(1, 1)];
      final a = WhiteboardPainter(
          strokes: const [], board: _board, liveStroke: shared);
      final b = WhiteboardPainter(
          strokes: const [], board: _board, liveStroke: shared);

      expect(b.shouldRepaint(a), isFalse);
    });
  });
}
