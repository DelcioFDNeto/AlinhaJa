import 'package:web/web.dart' as web;
import 'dart:js_interop';

/// Web-specific implementation of presence listeners using HTML window APIs.
void registerWebPresenceListeners({
  required void Function() onBeforeUnload,
  required void Function() onVisible,
  required void Function() onHidden,
}) {
  web.window.addEventListener(
      'beforeunload',
      ((web.Event _) {
        onBeforeUnload();
      }).toJS);

  web.window.document.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        if (web.window.document.hidden) {
          onHidden();
        } else {
          onVisible();
        }
      }).toJS);
}
