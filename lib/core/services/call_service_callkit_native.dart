import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';

/// Implementação nativa do CallKit (Android/iOS).
import 'dart:async';
import 'package:alinha_ja/core/constants.dart';

/// Implementação nativa do CallKit (Android/iOS).
/// Carregado apenas quando dart.library.io está disponível.

StreamSubscription<CallEvent?>? _callkitSubscription;

void initCallKitListeners(
  Function(Map<dynamic, dynamic>) onAccepted,
  Function(Map<dynamic, dynamic>) onDeclined,
  Function(Map<dynamic, dynamic>) onEnded,
  Function(Map<dynamic, dynamic>) onTimeout,
) {
  _callkitSubscription?.cancel();
  _callkitSubscription = FlutterCallkitIncoming.onEvent.listen((event) {
    if (event == null) return;

    switch (event.event) {
      case Event.actionCallAccept:
        debugPrint('📞 CallKit - Chamada Aceita: ${event.body['id']}');
        onAccepted(event.body);
        break;
      case Event.actionCallDecline:
        debugPrint('📞 CallKit - Chamada Recusada: ${event.body['id']}');
        onDeclined(event.body);
        break;
      case Event.actionCallEnded:
        debugPrint('📞 CallKit - Chamada Encerrada: ${event.body['id']}');
        onEnded(event.body);
        break;
      case Event.actionCallTimeout:
        debugPrint('📞 CallKit - Chamada Expirou: ${event.body['id']}');
        onTimeout(event.body);
        break;
      default:
        break;
    }
  });
}

void showIncomingCall(String callerName, String callerId,
    {bool isVideo = false,
    String avatar = '',
    String? callId,
    String? chatId}) {
  const uuid = Uuid();
  final targetCallId = callId ?? uuid.v4();

  final params = CallKitParams(
    id: targetCallId,
    nameCaller: callerName,
    appName: AppConstants.appName,
    avatar: avatar.isNotEmpty ? avatar : '',
    handle: 'Chamada',
    type: isVideo ? 1 : 0,
    duration: 30000,
    textAccept: 'Atender',
    textDecline: 'Recusar',
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: true,
      subtitle: 'Chamada perdida',
      callbackText: 'Retornar ligação',
    ),
    extra: <String, dynamic>{
      'userId': callerId,
      'chatId': chatId ?? callerId,
      'isVideo': isVideo
    },
    headers: <String, dynamic>{'platform': 'flutter'},
    android: AndroidParams(
      isCustomNotification: false,
      isShowFullLockedScreen: true,
      isShowCallID: false,
      isShowLogo: true,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#000000',
      backgroundUrl: avatar.isNotEmpty ? avatar : '',
      actionColor: '#4CAF50',
      textColor: '#ffffff',
    ),
    ios: IOSParams(
      iconName: 'CallKitLogo',
      handleType: 'generic',
      supportsVideo: isVideo,
      maximumCallGroups: 1,
      maximumCallsPerCallGroup: 1,
      audioSessionMode: 'default',
      audioSessionActive: true,
      audioSessionPreferredSampleRate: 44100.0,
      audioSessionPreferredIOBufferDuration: 0.005,
      supportsDTMF: true,
      supportsHolding: true,
      supportsGrouping: false,
      supportsUngrouping: false,
      ringtonePath: 'system_ringtone_default',
    ),
  );

  FlutterCallkitIncoming.showCallkitIncoming(params);
}

void endAllCalls() {
  FlutterCallkitIncoming.endAllCalls();
}

void disposeCallKitListeners() {
  _callkitSubscription?.cancel();
  _callkitSubscription = null;
}
