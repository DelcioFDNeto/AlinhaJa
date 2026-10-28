import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/features/whiteboard/models/whiteboard_item.dart';
import 'package:alinha_ja/features/whiteboard/models/whiteboard_stroke.dart';
import 'package:alinha_ja/features/whiteboard/ui/widgets/whiteboard_painter.dart';

WhiteboardItem _item({
  Offset position = const Offset(100, 200),
  Size size = const Size(300, 200),
  WhiteboardItemKind kind = WhiteboardItemKind.image,
}) =>
    WhiteboardItem(
      id: 'item-1',
      whiteboardId: 'board-1',
      authorId: 'user-1',
      kind: kind,
      mediaUrl: 'https://exemplo/chat-media/chats/abc/foto.webp',
      storagePath: 'chats/abc/foto.webp',
      fileName: 'foto.webp',
      mimeType: 'image/webp',
      sizeBytes: 1234,
      position: position,
      size: size,
      createdAt: DateTime.utc(2026, 8, 20, 12),
    );

void main() {
  group('WhiteboardItem', () {
    test('serializa e deserializa mantendo geometria e arquivo', () {
      final map = _item().toInsert();

      expect(map['id'], 'item-1');
      expect(map['whiteboard_id'], 'board-1');
      expect(map['kind'], 'image');
      expect(map['storage_path'], 'chats/abc/foto.webp');
      expect(map['pos_x'], 100.0);
      expect(map['pos_y'], 200.0);
      expect(map['width'], 300.0);
      expect(map['height'], 200.0);

      final restored = WhiteboardItem.fromJson({
        ...map,
        'author_id': 'user-1',
        'created_at': DateTime.utc(2026, 8, 20, 12).toIso8601String(),
      });

      expect(restored.position, const Offset(100, 200));
      expect(restored.size, const Size(300, 200));
      expect(restored.kind, WhiteboardItemKind.image);
      expect(restored.isImage, isTrue);
    });

    test('kind desconhecido cai em imagem', () {
      final restored = WhiteboardItem.fromJson(const {
        'id': 'x',
        'kind': 'video-3d',
        'media_url': 'https://exemplo/x.png',
      });

      expect(restored.kind, WhiteboardItemKind.image);
    });

    test('toGeometryUpdate manda só o que o trigger deixa mudar', () {
      // `trg_wb_items_geometry_only` devolve todo o resto ao valor antigo:
      // mandar media_url/author_id aqui seria ruído silenciosamente ignorado.
      final update = _item().toGeometryUpdate();

      expect(update.keys.toSet(), {'pos_x', 'pos_y', 'width', 'height'});
    });

    test('fitToBoard encaixa mantendo a proporção e centraliza', () {
      // Print grande e deitado: o lado maior vira defaultMaxSide, e o menor
      // acompanha a proporção — nada de esticar a imagem no quadro.
      final wide = WhiteboardItem.fitToBoard(const Size(3000, 1500));

      expect(wide.size.width, closeTo(WhiteboardItem.defaultMaxSide, 0.01));
      expect(wide.size.height, closeTo(WhiteboardItem.defaultMaxSide / 2, 0.01));

      final centro = wide.position.dx + wide.size.width / 2;
      expect(centro, closeTo(WhiteboardStroke.canvasSize / 2, 0.01));
    });

    test('fitToBoard não divide por zero em arquivo sem dimensão', () {
      // Um decoder que falhou devolve Size.zero; sem a guarda, o scale vira
      // infinito e o anexo somiria do quadro.
      final fallback = WhiteboardItem.fitToBoard(Size.zero);

      expect(fallback.size.width, greaterThan(0));
      expect(fallback.size.height, greaterThan(0));
      expect(fallback.size.width.isFinite, isTrue);
    });
  });

  group('WhiteboardTool.move', () {
    test('não é ferramenta de desenho', () {
      expect(WhiteboardTool.move.isDrawing, isFalse);
      expect(WhiteboardTool.pen.isDrawing, isTrue);
      expect(WhiteboardTool.highlighter.isDrawing, isTrue);
      expect(WhiteboardTool.eraser.isDrawing, isTrue);
    });

    test('traço gravado com "move" volta como caneta', () {
      // Só um cliente com bug gravaria isso. Cair na caneta preserva a linha;
      // deixar `move` passar faria o painter não desenhar nada.
      final restored = WhiteboardStroke.fromJson(const {
        'id': 's1',
        'tool': 'move',
      });

      expect(restored.tool, WhiteboardTool.pen);
    });
  });

  group('WhiteboardPainter com anexos', () {
    const board = Rect.fromLTWH(0, 0, 400, 400);

    test('repinta ao ligar/desligar o fundo', () {
      // A tela desenha a folha como widget para os anexos ficarem entre ela e
      // a tinta; o painter precisa saber quando esse contrato muda.
      final comFundo = WhiteboardPainter(strokes: const [], board: board);
      final semFundo = WhiteboardPainter(
        strokes: const [],
        board: board,
        paintBackground: false,
      );

      expect(semFundo.shouldRepaint(comFundo), isTrue);
    });
  });
}
