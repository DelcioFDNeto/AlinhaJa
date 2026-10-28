import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Serviço responsável por gerar e persistir uma identidade única
/// para o dispositivo atual. Essa identidade é usada para verificar
/// se o dispositivo já foi autenticado via 2FA nos últimos 30 dias.
class DeviceFingerprintService {
  static const _webFingerprintKey = 'alinhaja_device_fingerprint';

  /// Retorna uma string única e consistente para identificar este dispositivo.
  static Future<String> getFingerprint() async {
    if (kIsWeb) {
      return _getWebFingerprint();
    }
    return _getMobileFingerprint();
  }

  /// Retorna um nome amigável para o dispositivo (ex: "Samsung Galaxy S23").
  static Future<String> getDeviceName() async {
    if (kIsWeb) {
      return 'Navegador Web';
    }
    return _getMobileDeviceName();
  }

  // ---- Web ----
  static Future<String> _getWebFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    String? fingerprint = prefs.getString(_webFingerprintKey);
    if (fingerprint == null) {
      fingerprint = const Uuid().v4();
      await prefs.setString(_webFingerprintKey, fingerprint);
    }
    return 'web-$fingerprint';
  }

  // ---- Mobile ----
  static Future<String> _getMobileFingerprint() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = await deviceInfo.androidInfo;
        return 'android-${android.id}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = await deviceInfo.iosInfo;
        final vendorId = ios.identifierForVendor;
        if (vendorId != null && vendorId.isNotEmpty) {
          return 'ios-$vendorId';
        }
      }
    } catch (e) {
      debugPrint('[2FA] Error getting device fingerprint: $e');
    }
    // Fallback: usar UUID persistido (mesmo esquema da web)
    return _getWebFingerprint();
  }

  static Future<String> _getMobileDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = await deviceInfo.androidInfo;
        final brand = android.brand;
        final model = android.model;
        return '${_capitalize(brand)} $model';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = await deviceInfo.iosInfo;
        return ios.name;
      }
    } catch (e) {
      debugPrint('[2FA] Error getting device name: $e');
    }
    return 'Dispositivo Desconhecido';
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}

