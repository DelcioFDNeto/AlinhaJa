import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  bool _isInitialized = false;
  bool _isTracking = false;
  Timer? _webTimer;

  final StreamController<Map<String, dynamic>> _locationStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get locationStream =>
      _locationStreamController.stream;

  bool get isTracking => _isTracking;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    debugPrint('📍 LocationService (Web): Inicializado');
  }

  Future<bool> requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('❌ Serviço de localização está desativado (Web)');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('❌ Permissão de localização negada (Web)');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('❌ Permissão permanentemente negada (Web)');
      return false;
    }

    return true;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      debugPrint('❌ Erro ao obter posição (Web): $e');
      return null;
    }
  }

  Future<int> getBatteryLevel() async => -1;

  Map<String, dynamic> getDeviceInfo() {
    return {'platform': 'web'};
  }

  Future<bool> startTracking({int intervalMinutes = 5}) async {
    if (_isTracking) return false;

    final hasPermission = await requestLocationPermission();
    if (!hasPermission) return false;

    _webTimer?.cancel();
    _captureAndSendWebLocation();
    _webTimer = Timer.periodic(Duration(minutes: intervalMinutes), (_) {
      _captureAndSendWebLocation();
    });
    _isTracking = true;
    debugPrint(
        '📍 Rastreamento Web iniciado (intervalo: ${intervalMinutes}min)');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('location_tracking_active', true);
    await prefs.setInt('location_tracking_interval', intervalMinutes);

    return true;
  }

  Future<void> _captureAndSendWebLocation() async {
    try {
      final pos = await getCurrentPosition();
      if (pos == null) return;
      _locationStreamController.add({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
        'altitude': pos.altitude,
        'speed': pos.speed,
        'heading': pos.heading,
      });
    } catch (e) {
      debugPrint('❌ Erro no timer Web: $e');
    }
  }

  Future<void> stopTracking() async {
    _webTimer?.cancel();
    _webTimer = null;
    _isTracking = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('location_tracking_active', false);

    debugPrint('📍 Rastreamento parado (Web)');
  }
}
