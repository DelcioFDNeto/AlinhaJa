// Stub para Web — CallKit não existe no navegador.
// Estas funções são chamadas condicionalmente e são no-ops na Web.

void initCallKitListeners(
  Function(Map<dynamic, dynamic>) onAccepted,
  Function(Map<dynamic, dynamic>) onDeclined,
  Function(Map<dynamic, dynamic>) onEnded,
  Function(Map<dynamic, dynamic>) onTimeout,
) {
  // No-op na Web
}

void showIncomingCall(String callerName, String callerId,
    {bool isVideo = false,
    String avatar = '',
    String? callId,
    String? chatId}) {
  // No-op na Web — usa showWebIncomingCallDialog() diretamente
}

void endAllCalls() {
  // No-op na Web
}
