import 'package:geolocator/geolocator.dart';
import 'dart:async';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  bool get isTracking => false;
  Future<void> init() async {}
  Future<bool> startTracking({int intervalMinutes = 5}) async => false;
  Future<void> stopTracking() async {}
  Future<Position?> getCurrentPosition() async => null;
  Future<int> getBatteryLevel() async => -1;
  Map<String, dynamic> getDeviceInfo() => {};

  Stream<Map<String, dynamic>> get locationStream => const Stream.empty();
}
