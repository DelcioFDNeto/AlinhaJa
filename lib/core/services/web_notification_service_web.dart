import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

final Map<String, web.Notification> _activeNotifications = {};

void showWebNotification(String title, String body, {String? tag}) {
  if (web.Notification.permission == 'granted') {
    _createNotification(title, body, tag);
  } else if (web.Notification.permission != 'denied') {
    web.Notification.requestPermission().toDart.then((permission) {
      if (permission.toDart == 'granted') {
        _createNotification(title, body, tag);
      }
    });
  }
}

void _createNotification(String title, String body, String? tag) {
  final options = web.NotificationOptions(
    body: body,
    tag: tag ?? 'alinhaja_call',
    requireInteraction: true,
  );
  final notification = web.Notification(title, options);
  if (tag != null) {
    _activeNotifications[tag] = notification;
  }
}

void closeWebNotification(String tag) {
  final notification = _activeNotifications.remove(tag);
  notification?.close();
}

/// Ver `WebNotificationService.showPushIfUnfocused`. A formatação é a mesma
/// do service worker (`web/notification-format.js`), exposta pelo index.html.
bool showPushIfUnfocused(Map<String, dynamic> data) {
  try {
    if (!web.window.has('alinhajaShowPushNotification')) return false;
    final result = web.window.callMethod<JSAny?>(
        'alinhajaShowPushNotification'.toJS, jsonEncode(data).toJS);
    return (result as JSBoolean?)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}
