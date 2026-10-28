import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/two_factor_service.dart';

/// Provider singleton do serviço de 2FA.
final twoFactorServiceProvider = Provider<TwoFactorService>((_) {
  return TwoFactorService();
});

/// Provider que verifica se o dispositivo atual é confiável.
/// Retorna `true` se o dispositivo foi verificado nos últimos 30 dias
/// ou se o usuário é ti_admin (isento).
final deviceTrustedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final service = ref.read(twoFactorServiceProvider);
  return service.isDeviceTrusted();
});

/// Provider que lista todos os dispositivos confiáveis do usuário.
final trustedDevicesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final service = ref.read(twoFactorServiceProvider);
  return service.getTrustedDevices();
});
