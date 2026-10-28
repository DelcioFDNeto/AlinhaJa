import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Ferramenta selecionada na barra do quadro.
///
/// [move] é a única que não desenha: com ela o gesto passa a arrastar e
/// redimensionar anexos em vez de riscar. Por isso ela nunca chega ao banco —
/// `WhiteboardNotifier.addStroke` recusa traço com ferramenta que não pinta, e
/// `fromJson` cai em [pen] diante de qualquer valor desconhecido.
enum WhiteboardTool {
  pen,
  highlighter,
  eraser,
  move;

  /// Se o gesto nesta ferramenta produz traço.
  bool get isDrawing => this != WhiteboardTool.move;
}

/// Um traço do quadro branco.
///
/// Os pontos ficam em coordenadas do quadro (0..[WhiteboardStroke.canvasSize]),
/// não da tela: assim o mesmo desenho aparece igual no celular e no monitor de
/// quem abriu junto.
@immutable
class WhiteboardStroke {
  /// Lado do espaço lógico do quadro. Tudo é normalizado para este quadrado.
  static const double canvasSize = 1000;

  final String id;
  final String whiteboardId;
  final String authorId;
  final List<Offset> points;
  final Color color;
  final double width;
  final WhiteboardTool tool;
  final DateTime createdAt;

  const WhiteboardStroke({
    required this.id,
    required this.whiteboardId,
    required this.authorId,
    required this.points,
    required this.color,
    required this.width,
    required this.tool,
    required this.createdAt,
  });

  factory WhiteboardStroke.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];

    return WhiteboardStroke(
      id: json['id']?.toString() ?? '',
      whiteboardId: json['whiteboard_id']?.toString() ?? '',
      authorId: json['author_id']?.toString() ?? '',
      points: rawPoints is List
          ? rawPoints
              .map(_offsetFromJson)
              .whereType<Offset>()
              .toList(growable: false)
          : const [],
      color: _colorFromHex(json['color']?.toString()),
      width: (json['width'] as num?)?.toDouble() ?? 3,
      // `move` é filtrado junto com os valores desconhecidos: se um traço com
      // essa ferramenta aparecer no banco, ele veio de um cliente com bug e
      // desenhar nada seria pior do que desenhar a caneta.
      tool: WhiteboardTool.values.firstWhere(
        (t) => t.isDrawing && t.name == json['tool']?.toString(),
        orElse: () => WhiteboardTool.pen,
      ),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Payload de insert. O `id` sai daqui: quem cria o traço já escolhe o UUID,
  /// para reconhecer o próprio traço quando ele voltar pelo Realtime e não
  /// desenhar duas vezes.
  Map<String, dynamic> toInsert() => {
        'id': id,
        'whiteboard_id': whiteboardId,
        'author_id': authorId,
        'points': [
          for (final p in points)
            {
              'x': double.parse(p.dx.toStringAsFixed(2)),
              'y': double.parse(p.dy.toStringAsFixed(2)),
            }
        ],
        'color': _hexFromColor(color),
        'width': width,
        'tool': tool.name,
      };

  static Offset? _offsetFromJson(Object? raw) {
    if (raw is! Map) return null;
    final x = (raw['x'] as num?)?.toDouble();
    final y = (raw['y'] as num?)?.toDouble();
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  static Color _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF000000);
    final value = hex.replaceFirst('#', '');
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return const Color(0xFF000000);
    // Aceita RRGGBB e AARRGGBB.
    return Color(value.length <= 6 ? 0xFF000000 | parsed : parsed);
  }

  static String _hexFromColor(Color color) {
    final argb = color.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
}
