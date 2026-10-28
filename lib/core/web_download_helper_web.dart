import 'package:web/web.dart' as web;

void triggerFileDownload(String url, String filename) {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
}
