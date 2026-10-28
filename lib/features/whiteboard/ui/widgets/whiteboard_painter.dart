import 'package:flutter/material.dart';

import 'package:alinha_ja/features/whiteboard/models/whiteboard_stroke.dart';

/// Renderiza os traços salvos e o traço ao vivo.
///
/// Tudo é transposto de coordenadas do quadro (0..1000) para o [board] Rect na
/// tela.
class WhiteboardPainter extends CustomPainter {
  final List<WhiteboardStroke> strokes;
  final Rect board;

  /// Pinta a folha branca atrás dos traços.
  ///
  /// A tela do quadro desliga isto porque precisa dos anexos ENTRE o fundo e
  /// os traços — com o fundo aqui, a folha branca cobriria as imagens.
  final bool paintBackground;

  final List<Offset> liveStroke;
  final Color liveColor;
  final double liveWidth;
  final WhiteboardTool liveTool;

  /// Quantos pontos o traço ao vivo tinha quando este painter foi criado.
  ///
  /// A tela mantém uma única lista e vai adicionando ponto nela a cada
  /// movimento do dedo. Como o painter antigo e o novo apontam para o mesmo
  /// objeto já mutado, nenhuma comparação feita na hora do [shouldRepaint]
  /// — nem por identidade, nem por tamanho — consegue ver a diferença. Guardar
  /// a contagem no momento da construção é o que dá ao painter uma memória do
  /// estado anterior.
  final int _liveCount;

  WhiteboardPainter({
    required this.strokes,
    required this.board,
    this.paintBackground = true,
    this.liveStroke = const [],
    this.liveColor = const Color(0xFF1A1A1A),
    this.liveWidth = 3,
    this.liveTool = WhiteboardTool.pen,
  }) : _liveCount = liveStroke.length;

  @override
  void paint(Canvas canvas, Size size) {
    if (paintBackground) {
      // Fundo do quadro: branco com borda suave e sombra de folha.
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(board, bgPaint);

      final borderPaint = Paint()
        ..color = const Color(0xFFE5E5EA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRect(board, borderPaint);
    }

    // Salva o estado e limita o desenho ao quadrado do quadro.
    canvas.save();
    canvas.clipRect(board);

    // Camada própria para a tinta. A borracha apaga com BlendMode.clear, que
    // só faz sentido dentro de uma camada: aqui ela tira a tinta e devolve o
    // que estava embaixo — a folha branca, ou a imagem anexada. Pintar de
    // branco por cima (o jeito antigo) daria o mesmo resultado no quadro
    // vazio e cobriria o anexo com um retângulo branco.
    canvas.saveLayer(board, Paint());

    final scale = board.width / WhiteboardStroke.canvasSize;

    for (final stroke in strokes) {
      _drawStroke(
        canvas: canvas,
        points: stroke.points,
        color: stroke.color,
        width: stroke.width,
        tool: stroke.tool,
        scale: scale,
      );
    }

    if (liveStroke.length >= 2) {
      _drawStroke(
        canvas: canvas,
        points: liveStroke,
        color: liveColor,
        width: liveWidth,
        tool: liveTool,
        scale: scale,
      );
    }

    canvas.restore(); // saveLayer
    canvas.restore(); // clipRect
  }

  void _drawStroke({
    required Canvas canvas,
    required List<Offset> points,
    required Color color,
    required double width,
    required WhiteboardTool tool,
    required double scale,
  }) {
    if (points.length < 2) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (tool) {
      case WhiteboardTool.pen:
        paint
          ..color = color
          ..strokeWidth = width * scale;

      case WhiteboardTool.highlighter:
        paint
          ..color = color.withValues(alpha: 0.35)
          ..strokeWidth = width * 4 * scale;

      case WhiteboardTool.eraser:
        paint
          ..blendMode = BlendMode.clear
          ..color = Colors.white
          ..strokeWidth = width * 5 * scale;

      // A ferramenta de mover nunca vira traço (o notifier recusa e o
      // `fromJson` filtra), então chegar aqui significa dado corrompido: cai
      // na caneta em vez de sumir com a linha.
      case WhiteboardTool.move:
        paint
          ..color = color
          ..strokeWidth = width * scale;
    }

    final path = Path();
    final first = _toCanvas(points.first, scale);
    path.moveTo(first.dx, first.dy);

    for (var i = 1; i < points.length; i++) {
      final pt = _toCanvas(points[i], scale);
      path.lineTo(pt.dx, pt.dy);
    }

    canvas.drawPath(path, paint);
  }

  Offset _toCanvas(Offset point, double scale) {
    return Offset(
      board.left + point.dx * scale,
      board.top + point.dy * scale,
    );
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) {
    // O traço ao vivo é comparado pela contagem capturada na construção
    // (ver [_liveCount]) — a lista em si é a mesma instância dos dois lados.
    //
    // `strokes` vem do provider como lista nova a cada estado, então a
    // comparação por identidade funciona e ainda pega troca de conteúdo com o
    // mesmo tamanho (desfazer + receber traço de outra pessoa no mesmo frame).
    return oldDelegate.strokes != strokes ||
        oldDelegate.board != board ||
        oldDelegate.paintBackground != paintBackground ||
        oldDelegate._liveCount != _liveCount ||
        oldDelegate.liveColor != liveColor ||
        oldDelegate.liveWidth != liveWidth ||
        oldDelegate.liveTool != liveTool;
  }
}
