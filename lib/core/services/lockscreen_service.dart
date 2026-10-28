import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Serviço que se comunica com o código nativo (Android) para controlar a segurança
/// da tela de bloqueio e burlar a proteção de bloqueio *apenas* quando necessário
/// (ex: dentro de uma chamada ativa).
class LockscreenService {
  static const MethodChannel _channel =
      MethodChannel('com.alinha_ja.app/lockscreen');

  /// Define se o aplicativo deve continuar sobrescrevendo a tela de bloqueio do sistema.
  /// Quando [isVisible] for `true`, o app acenderá e sobreporá o lockscreen (útil na tela de chamada).
  /// Quando for `false`, devolverá o controle ao Android, e se a tela já estiver bloqueada, o Lockscreen
  /// normal do SO assumirá a frente se o usuário tentar sair da tela.
  static Future<void> setCallScreenVisible(bool isVisible) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('setLockScreenVisibility', isVisible);
        debugPrint('🔒 Lockscreen Visibility: $isVisible');
      } on PlatformException catch (e) {
        debugPrint('🔒 Erro no setCallScreenVisible: ${e.message}');
      }
    }
  }

  /// Pede para o sistema solicitar a biometria/senha ao usuário (Keyguard Dismiss).
  /// Caso a tela já esteja desbloqueada, retorna imediatamente `true` sem solicitar nada.
  /// Caso o usuário passe biometria, retorna `true`.
  /// Caso o usuário clique em "Cancelar" ou erre muitas vezes a biometria, retorna `false`.
  static Future<bool> requestUnlock() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final success = await _channel.invokeMethod<bool>('requestUnlock');
        return success ?? false;
      } on PlatformException catch (e) {
        debugPrint('🔒 Erro no requestUnlock: ${e.message}');
        return false;
      }
    }
    // Na Web e iOS, assumimos que não há barreiras desta implementação específica
    return true;
  }

  /// Verifica se o dispositivo está com a tela bloqueada pelo Keyguard do Android.
  static Future<bool> isDeviceLocked() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final locked = await _channel.invokeMethod<bool>('isDeviceLocked');
        return locked ?? false;
      } on PlatformException catch (e) {
        debugPrint('🔒 Erro no isDeviceLocked: ${e.message}');
        return false;
      }
    }
    return false;
  }
}
