import 'package:web/web.dart' as web;
import 'dart:js_interop';

@JS('clearFlutterCaches')
external void _clearFlutterCaches();

void clearWebCacheAndReload() {
  try {
    _clearFlutterCaches();
    web.window.location.reload();
  } catch (e) {
    // Silencioso
  }
}

/// Recarrega a página sem limpar o cache do shell (usado ao trocar de empresa).
void reloadApp() {
  try {
    web.window.location.reload();
  } catch (e) {
    // Silencioso
  }
}
