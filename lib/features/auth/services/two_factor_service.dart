import 'package:flutter/foundation.dart';
import '../../../core/supabase_client.dart';
import 'device_fingerprint_service.dart';

/// Serviço de Autenticação de Dois Fatores (2FA) por E-mail.
///
/// Coordena a verificação do dispositivo, geração/envio de OTP
/// e gerenciamento de dispositivos confiáveis.
class TwoFactorService {
  // ────────────────────────────────────────────────────────
  // Verificação de Confiança do Dispositivo
  // ────────────────────────────────────────────────────────

  /// Verifica se o dispositivo atual está na lista de confiáveis
  /// (dentro do período de 30 dias).
  /// Retorna `true` se confiável ou se o usuário é ti_admin (isento).
  Future<bool> isDeviceTrusted() async {
    try {
      final fingerprint = await DeviceFingerprintService.getFingerprint();
      final result = await supabase.rpc(
        'check_device_trusted',
        params: {'p_device_fingerprint': fingerprint},
      );
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('[2FA] Error checking device trust: $e');
      return false;
    }
  }

  // ────────────────────────────────────────────────────────
  // Ativação do 2FA por E-mail (opt-in)
  // ────────────────────────────────────────────────────────

  /// Indica se o usuário atual ativou o 2FA por e-mail.
  Future<bool> isEmail2faEnabled() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;
      final row = await supabase
          .from('users')
          .select('email_2fa_enabled')
          .eq('id', userId)
          .maybeSingle();
      return row?['email_2fa_enabled'] as bool? ?? false;
    } catch (e) {
      debugPrint('[2FA] Error reading email 2FA flag: $e');
      return false;
    }
  }

  /// Ativa/desativa o 2FA por e-mail. Ao ativar, o banco registra o
  /// dispositivo atual como confiável e a sessão atual como verificada
  /// (anti-lockout). Desativar exige sessão que já cumpriu o 2FA.
  Future<void> setEmail2faEnabled(bool enabled) async {
    final fingerprint = await DeviceFingerprintService.getFingerprint();
    final deviceName = await DeviceFingerprintService.getDeviceName();
    await supabase.rpc(
      'set_email_2fa_enabled',
      params: {
        'p_enabled': enabled,
        'p_device_fingerprint': fingerprint,
        'p_device_name': deviceName,
      },
    );
  }

  /// Registra a sessão atual como verificada no banco (libera a RLS).
  /// O banco só aceita se o dispositivo for confiável — chamar após
  /// validar o código ou ao logar em dispositivo já confiável.
  Future<bool> registerSessionVerified() async {
    try {
      final fingerprint = await DeviceFingerprintService.getFingerprint();
      final result = await supabase.rpc(
        'register_2fa_session',
        params: {'p_device_fingerprint': fingerprint},
      );
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('[2FA] Error registering 2FA session: $e');
      return false;
    }
  }

  /// Resolve o gate do 2FA por e-mail para a sessão atual:
  /// - 2FA por e-mail desativado → `true` (nada a cumprir);
  /// - ativado e dispositivo confiável → registra a sessão no banco
  ///   e retorna `true`;
  /// - ativado e dispositivo não confiável → `false` (precisa do código).
  Future<bool> emailGateSatisfied() async {
    final enabled = await isEmail2faEnabled();
    if (!enabled) return true;

    final trusted = await isDeviceTrusted();
    if (!trusted) return false;

    await registerSessionVerified();
    return true;
  }

  // ────────────────────────────────────────────────────────
  // Geração e Envio do Código OTP
  // ────────────────────────────────────────────────────────

  /// Solicita o envio de um novo código OTP por e-mail.
  /// A Edge Function `send-2fa-code` gera o código, armazena o hash
  /// e dispara o e-mail. O código nunca é exposto ao client.
  ///
  /// Retorna um mapa com `success`, `masked_email` e `message`.
  Future<Map<String, dynamic>> requestCode() async {
    try {
      final response = await supabase.functions.invoke('send-2fa-code');

      if (response.status != 200) {
        final error = response.data?['error'] ?? 'Erro desconhecido';
        throw Exception(error);
      }

      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      debugPrint('[2FA] Error requesting code: $e');
      rethrow;
    }
  }

  // ────────────────────────────────────────────────────────
  // Verificação do Código OTP
  // ────────────────────────────────────────────────────────

  /// Valida o código digitado pelo usuário.
  /// Se correto, registra automaticamente o dispositivo como confiável
  /// por 30 dias no banco de dados.
  ///
  /// Retorna:
  /// - `'valid'`   → Código correto, dispositivo registrado
  /// - `'invalid'` → Código incorreto
  /// - `'expired'` → Código expirado (>10 min)
  /// - `'blocked'` → Excesso de tentativas (>=5)
  Future<String> verifyCode(String code) async {
    try {
      final fingerprint = await DeviceFingerprintService.getFingerprint();
      final deviceName = await DeviceFingerprintService.getDeviceName();

      final result = await supabase.rpc(
        'verify_2fa_code',
        params: {
          'p_code': code,
          'p_device_fingerprint': fingerprint,
          'p_device_name': deviceName,
        },
      );

      return result as String? ?? 'expired';
    } catch (e) {
      debugPrint('[2FA] Error verifying code: $e');
      rethrow;
    }
  }

  // ────────────────────────────────────────────────────────
  // Gerenciamento de Dispositivos Confiáveis
  // ────────────────────────────────────────────────────────

  /// Lista todos os dispositivos confiáveis do usuário atual.
  Future<List<Map<String, dynamic>>> getTrustedDevices() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final result = await supabase
          .from('user_trusted_devices')
          .select()
          .eq('user_id', userId)
          .order('verified_at', ascending: false);

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('[2FA] Error getting trusted devices: $e');
      return [];
    }
  }

  /// Remove um dispositivo específico da lista de confiáveis.
  Future<void> revokeDevice(String deviceId) async {
    await supabase.rpc(
      'revoke_trusted_device',
      params: {'p_device_id': deviceId},
    );
  }

  /// Remove TODOS os dispositivos confiáveis do usuário.
  /// O usuário precisará verificar novamente em todos os dispositivos.
  Future<void> revokeAllDevices() async {
    await supabase.rpc('revoke_all_trusted_devices');
  }
}
