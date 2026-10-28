import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:alinha_ja/features/whiteboard/models/whiteboard_stroke.dart';

/// O que foi anexado ao quadro.
///
/// `image` é desenhado no quadro e serve de base para o traço por cima;
/// `file` vira um cartão clicável — um PDF não tem como ser rabiscado, mas
/// precisa ficar junto do desenho que fala sobre ele.
enum WhiteboardItemKind { image, file }

/// Uma imagem ou arquivo posicionado no quadro.
///
/// A geometria vive no mesmo espaço lógico dos traços
/// (0..[WhiteboardStroke.canvasSize]), então o anexo fica no mesmo lugar
/// relativo ao desenho em qualquer tamanho de tela.
@immutable
class WhiteboardItem {
  /// Maior lado que um anexo recém-solto ocupa no quadro.
  ///
  /// Cerca de um terço do lado — grande o bastante para se enxergar o que é,
  /// pequeno o bastante para sobrar quadro em volta para desenhar.
  static const double defaultMaxSide = WhiteboardStroke.canvasSize / 3;

  final String id;
  final String whiteboardId;
  final String authorId;
  final WhiteboardItemKind kind;

  /// URL como está gravada no banco. Passa pelo `MediaUrlResolver` antes de
  /// ser exibida — o bucket `chat-media` é privado.
  final String mediaUrl;
  final String? storagePath;
  final String? fileName;
  final String? mimeType;
  final int? sizeBytes;

  /// Canto superior esquerdo, em coordenadas do quadro.
  final Offset position;

  /// Tamanho em coordenadas do quadro.
  final Size size;

  final DateTime createdAt;

  const WhiteboardItem({
    required this.id,
    required this.whiteboardId,
    required this.authorId,
    required this.kind,
    required this.mediaUrl,
    this.storagePath,
    this.fileName,
    this.mimeType,
    this.sizeBytes,
    required this.position,
    required this.size,
    required this.createdAt,
  });

  Rect get rect => position & size;

  bool get isImage => kind == WhiteboardItemKind.image;

  factory WhiteboardItem.fromJson(Map<String, dynamic> json) {
    return WhiteboardItem(
      id: json['id']?.toString() ?? '',
      whiteboardId: json['whiteboard_id']?.toString() ?? '',
      authorId: json['author_id']?.toString() ?? '',
      kind: json['kind']?.toString() == 'file'
          ? WhiteboardItemKind.file
          : WhiteboardItemKind.image,
      mediaUrl: json['media_url']?.toString() ?? '',
      storagePath: json['storage_path']?.toString(),
      fileName: json['file_name']?.toString(),
      mimeType: json['mime_type']?.toString(),
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      position: Offset(
        (json['pos_x'] as num?)?.toDouble() ?? 0,
        (json['pos_y'] as num?)?.toDouble() ?? 0,
      ),
      size: Size(
        (json['width'] as num?)?.toDouble() ?? defaultMaxSide,
        (json['height'] as num?)?.toDouble() ?? defaultMaxSide,
      ),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Payload de insert. Como nos traços, o `id` sai daqui: quem anexa já
  /// escolhe o UUID para reconhecer o próprio item quando ele voltar pelo
  /// Realtime e não desenhar duas vezes.
  Map<String, dynamic> toInsert() => {
        'id': id,
        'whiteboard_id': whiteboardId,
        'author_id': authorId,
        'kind': kind.name,
        'media_url': mediaUrl,
        if (storagePath != null) 'storage_path': storagePath,
        if (fileName != null) 'file_name': fileName,
        if (mimeType != null) 'mime_type': mimeType,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
        'pos_x': _round(position.dx),
        'pos_y': _round(position.dy),
        'width': _round(size.width),
        'height': _round(size.height),
      };

  /// Payload de UPDATE de arrasto/redimensionamento.
  ///
  /// Só geometria — o resto é devolvido ao valor antigo pelo trigger
  /// `trg_wb_items_geometry_only`, então mandar mais campos seria ruído.
  Map<String, dynamic> toGeometryUpdate() => {
        'pos_x': _round(position.dx),
        'pos_y': _round(position.dy),
        'width': _round(size.width),
        'height': _round(size.height),
      };

  WhiteboardItem copyWith({Offset? position, Size? size}) => WhiteboardItem(
        id: id,
        whiteboardId: whiteboardId,
        authorId: authorId,
        kind: kind,
        mediaUrl: mediaUrl,
        storagePath: storagePath,
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        position: position ?? this.position,
        size: size ?? this.size,
        createdAt: createdAt,
      );

  /// Encaixa um anexo de [source] pixels dentro de [defaultMaxSide] mantendo
  /// a proporção, e o centraliza no quadro.
  ///
  /// Sem isso um print de 3000px entraria ocupando o quadro inteiro e um
  /// ícone de 64px ficaria invisível.
  static ({Offset position, Size size}) fitToBoard(Size source) {
    const canvas = WhiteboardStroke.canvasSize;

    final safeSource = (source.width <= 0 || source.height <= 0)
        ? const Size(4, 3)
        : source;

    final scale = defaultMaxSide /
        (safeSource.width > safeSource.height
            ? safeSource.width
            : safeSource.height);

    final size = Size(safeSource.width * scale, safeSource.height * scale);
    return (
      position: Offset(
        (canvas - size.width) / 2,
        (canvas - size.height) / 2,
      ),
      size: size,
    );
  }

  static double _round(double value) =>
      double.parse(value.toStringAsFixed(2));
}
