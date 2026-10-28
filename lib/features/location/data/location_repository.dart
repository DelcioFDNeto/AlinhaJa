import 'package:flutter/foundation.dart';
import 'package:alinha_ja/core/supabase_client.dart';

/// Repositório que gerencia dados de localização no Supabase.
class LocationRepository {
  const LocationRepository();

  /// Insere uma nova localização no banco.
  Future<void> insertLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? heading,
    Map<String, dynamic>? deviceInfo,
    int? batteryLevel,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    await supabase.from('user_locations').insert({
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'device_info': deviceInfo,
      'battery_level': batteryLevel,
    });
  }

  /// Busca a última localização de todos os usuários rastreados (admin only).
  Future<List<Map<String, dynamic>>> getLatestLocations() async {
    try {
      final response = await supabase.rpc('get_latest_user_locations');
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('❌ Erro ao buscar localizações: $e');
      return [];
    }
  }

  /// Busca o histórico de localização de um usuário específico.
  Future<List<Map<String, dynamic>>> getUserLocationHistory({
    required String userId,
    int limit = 50,
  }) async {
    try {
      final response = await supabase
          .from('user_locations')
          .select('*')
          .eq('user_id', userId)
          .order('recorded_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('❌ Erro ao buscar histórico: $e');
      return [];
    }
  }

  /// Lê as configurações de rastreamento de um usuário.
  Future<Map<String, dynamic>?> getTrackingSettings(String userId) async {
    try {
      final response = await supabase
          .from('location_tracking_settings')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('❌ Erro ao buscar configurações de rastreamento: $e');
      return null;
    }
  }

  /// Atualiza (upsert) as configurações de rastreamento de um usuário.
  Future<void> upsertTrackingSettings({
    required String targetUserId,
    required bool isEnabled,
    int intervalMinutes = 5,
  }) async {
    final callerUserId = supabase.auth.currentUser?.id;
    if (callerUserId == null) return;

    await supabase.from('location_tracking_settings').upsert({
      'user_id': targetUserId,
      'is_enabled': isEnabled,
      'interval_minutes': intervalMinutes,
      'enabled_by': callerUserId,
      'enabled_at': isEnabled ? DateTime.now().toUtc().toIso8601String() : null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Busca o panorama de consentimento de todos os usuários (admin only).
  Future<List<Map<String, dynamic>>> getConsentOverview() async {
    try {
      final response = await supabase.rpc('admin_gps_consent_overview');
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('❌ Erro ao buscar panorama de consentimento GPS: $e');
      return [];
    }
  }

  /// Deleta localizações antigas (admin: limpeza manual).
  Future<int> cleanupOldLocations() async {
    try {
      final result = await supabase.rpc('cleanup_old_locations');
      return result as int? ?? 0;
    } catch (e) {
      debugPrint('❌ Erro ao limpar localizações antigas: $e');
      return 0;
    }
  }

  // ── Consentimento GPS (LGPD) ─────────────────────────────────

  /// Consulta o status de consentimento do usuário logado.
  Future<Map<String, dynamic>?> getConsentStatus() async {
    try {
      final result = await supabase.rpc('gps_my_consent_status');
      final list = result as List?;
      if (list == null || list.isEmpty) return null;
      return Map<String, dynamic>.from(list.first as Map);
    } catch (e) {
      debugPrint('❌ Erro ao consultar consentimento GPS: $e');
      return null;
    }
  }

  /// Registra o consentimento do titular (LGPD Art. 6º).
  Future<void> grantConsent({
    String version = 'v1',
    String finalidade =
        'Acompanhamento de equipe em atividade externa durante a jornada de trabalho',
  }) async {
    await supabase.rpc('gps_grant_consent', params: {
      'p_version': version,
      'p_finalidade': finalidade,
    });
  }

  /// Revoga o consentimento e desliga o rastreamento.
  Future<void> revokeConsent() async {
    await supabase.rpc('gps_revoke_consent');
  }

  /// Apaga todo o histórico de localização do titular (Art. 18, VI).
  Future<int> deleteMyLocations() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return 0;
      final result = await supabase
          .from('user_locations')
          .delete()
          .eq('user_id', userId)
          .select('id');
      return (result as List).length;
    } catch (e) {
      debugPrint('❌ Erro ao apagar histórico de localização: $e');
      return 0;
    }
  }
}
