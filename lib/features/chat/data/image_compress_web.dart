import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:async';

Future<Uint8List> compressImageWeb(
  Uint8List bytes, {
  int quality = 80,
  int maxWidth = 1200,
}) async {
  final jsBytes = bytes.toJS;
  final blob = web.Blob([jsBytes].toJS);
  final url = web.URL.createObjectURL(blob);

  final img = web.HTMLImageElement();
  final completer = Completer<void>();

  img.onload = ((web.Event _) {
    completer.complete();
  }).toJS;
  img.onerror = ((web.Event _) {
    completer.completeError(Exception('Erro ao carregar imagem no HTML.'));
  }).toJS;
  img.src = url;
  await completer.future;

  // Calcular dimensões mantendo aspect ratio
  double scale = 1.0;
  if (img.naturalWidth > maxWidth) {
    scale = maxWidth / img.naturalWidth;
  }
  final w = (img.naturalWidth * scale).round();
  final h = (img.naturalHeight * scale).round();

  final canvas = web.HTMLCanvasElement();
  canvas.width = w;
  canvas.height = h;
  final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  context.drawImage(img, 0, 0, w.toDouble(), h.toDouble());

  final webpBlobCompleter = Completer<web.Blob>();
  canvas.toBlob(
    ((web.Blob? resultBlob) {
      if (resultBlob != null) {
        webpBlobCompleter.complete(resultBlob);
      } else {
        webpBlobCompleter
            .completeError(Exception('Erro ao converter canvas para blob'));
      }
    }).toJS,
    'image/webp',
    (quality / 100).toJS,
  );
  final webpBlob = await webpBlobCompleter.future;

  final reader = web.FileReader();
  final readerCompleter = Completer<void>();
  reader.onloadend = ((web.Event _) {
    readerCompleter.complete();
  }).toJS;
  reader.readAsArrayBuffer(webpBlob);
  await readerCompleter.future;

  web.URL.revokeObjectURL(url);

  final resultBuffer = reader.result as JSArrayBuffer;
  return resultBuffer.toDart.asUint8List();
}
