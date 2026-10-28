import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/services/location_service.dart';
import 'package:alinha_ja/features/location/data/location_repository.dart';

// ── Providers ──────────────────────────────────────────────────────────────

final locationRepositoryProvider = Provider((_) => const LocationRepository());

/// Estado do serviço de rastreamento (ativo/inativo).
final locationTrackingActiveProvider = StateProvider<bool>((ref) => false);

/// Último estado da localização capturada.
final lastKnownLocationProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

/// Provider que busca as últimas localizações de todos os usuários (admin).
final latestLocationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.read(locationRepositoryProvider);
  return await repo.getLatestLocations();
});

/// Provider que busca o histórico de um usuário específico.
final userLocationHistoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, userId) async {
  final repo = ref.read(locationRepositoryProvider);
  return await repo.getUserLocationHistory(userId: userId);
});

/// Estado do consentimento GPS do usuário logado (LGPD).
final gpsConsentProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final repo = ref.read(locationRepositoryProvider);
  return await repo.getConsentStatus();
});

/// Panorama de consentimento de todos os usuários (admin only).
final gpsConsentOverviewProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.read(locationRepositoryProvider);
  return await repo.getConsentOverview();
});

/// Controlador do serviço de localização.
final locationControllerProvider =
    Provider<LocationController>((ref) => LocationController(ref));

class LocationController {
  final Ref _ref;

  LocationController(this._ref);

  StreamSubscription<Map<String, dynamic>>? _locationSub;

  /// Inicializa o listener de dados vindos do service.
  void initDataListener() {
    _locationSub?.cancel();
    _locationSub = LocationService().locationStream.listen(_onReceiveTaskData);
  }

  /// Remove o listener.
  void disposeDataListener() {
    _locationSub?.cancel();
    _locationSub = null;
  }

  /// Callback que recebe dados do service.
  void _onReceiveTaskData(Map<String, dynamic> data) async {
    _ref.read(lastKnownLocationProvider.notifier).state = data;

    // Envia para o Supabase
    final repo = _ref.read(locationRepositoryProvider);
    try {
      await repo.insertLocation(
        latitude: (data['latitude'] as num).toDouble(),
        longitude: (data['longitude'] as num).toDouble(),
        accuracy: (data['accuracy'] as num?)?.toDouble(),
        altitude: (data['altitude'] as num?)?.toDouble(),
        speed: (data['speed'] as num?)?.toDouble(),
        heading: (data['heading'] as num?)?.toDouble(),
        deviceInfo: LocationService().getDeviceInfo(),
        batteryLevel: await LocationService().getBatteryLevel(),
      );
    } catch (e) {
      debugPrint('❌ LocationController: Erro ao salvar localização: $e');
    }
  }

  /// Inicia o rastreamento.
  Future<bool> startTracking({int intervalMinutes = 5}) async {
    final success = await LocationService().startTracking(
      intervalMinutes: intervalMinutes,
    );

    if (success) {
      _ref.read(locationTrackingActiveProvider.notifier).state = true;
      initDataListener();
    }

    return success;
  }

  /// Para o rastreamento.
  Future<void> stopTracking() async {
    await LocationService().stopTracking();
    _ref.read(locationTrackingActiveProvider.notifier).state = false;
    disposeDataListener();
  }

  /// Captura e envia uma localização manualmente (one-shot).
  Future<void> captureAndSendNow() async {
    final position = await LocationService().getCurrentPosition();
    if (position == null) return;

    final repo = _ref.read(locationRepositoryProvider);
    await repo.insertLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
      deviceInfo: LocationService().getDeviceInfo(),
      batteryLevel: await LocationService().getBatteryLevel(),
    );

    _ref.read(lastKnownLocationProvider.notifier).state = {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
    };
  }
}
