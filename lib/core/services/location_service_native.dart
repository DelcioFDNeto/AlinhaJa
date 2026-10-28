import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Callback de nível superior para o TaskHandler do foreground service.
@pragma('vm:entry-point')
void locationTaskCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

/// TaskHandler que roda em segundo plano coletando localização.
class LocationTaskHandler extends TaskHandler {
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  DateTime _lastMovementTime = DateTime.now();
  bool _isIdle = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('📍 LocationTaskHandler: onStart (starter: ${starter.name})');

    _lastMovementTime = DateTime.now();
    _accelSub = userAccelerometerEventStream().listen((event) {
      final magnitude =
          sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));
      // Se a variação vetorial for significativa (> 1.2 m/s² removida a gravidade pura), registra movimento
      if (magnitude > 1.2) {
        _lastMovementTime = DateTime.now();
        if (_isIdle) {
          debugPrint(
              '🚶‍♂️ [SMART TRACKING] Movimento detectado. Reativando GPS de Alta Precisão.');
          _isIdle = false;
        }
      }
    }, onError: (e) {
      debugPrint('Acelerômetro falhou ou não suportado: $e');
      // Se não há acelerômetro, desativamos o smart tracking para evitar hibernação eterna ou contínua.
      // Atualizamos o lastMovementTime sempre para que ele nunca hiberne se não pudermos acordá-lo,
      // OU deixamos o GPS ligado continuamente (que é o comportamento mais seguro).
      _lastMovementTime = DateTime.now();
    }, cancelOnError: false);
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    try {
      final idleTime = DateTime.now().difference(_lastMovementTime);
      if (idleTime.inMinutes >= 5 && !_isIdle) {
        _isIdle = true;
        debugPrint(
            '🛑 [SMART TRACKING] 5 min inativo. Hibernando GPS e suprimindo pings (Low Battery Mode).');
      }

      if (_isIdle) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'AlinhaJá — Repouso Detectado',
          notificationText: 'Economizando bateria. Aguardando movimento...',
        );
        return; // Cancela requisição de GPS e empurrão para a rede.
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      // Envia dados de volta para o main isolate
      final data = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
        'timestamp': timestamp.toIso8601String(),
      };

      FlutterForegroundTask.sendDataToMain(data);

      FlutterForegroundTask.updateService(
        notificationTitle: 'AlinhaJá — Rastreamento ativo',
        notificationText:
            'Última atualização: ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
      );
    } catch (e) {
      debugPrint('❌ LocationTaskHandler: Erro ao obter posição: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('📍 LocationTaskHandler: onDestroy (isTimeout: $isTimeout)');
    _accelSub?.cancel();
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('📍 LocationTaskHandler: onReceiveData: $data');
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'btn_stop') {
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/settings/location');
  }

  @override
  void onNotificationDismissed() {}
}

/// Serviço de localização que gerencia GPS e foreground service.
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final Battery _battery = Battery();
  bool _isInitialized = false;
  bool _isTracking = false;
  Function(Object)? _taskDataCallback;

  final StreamController<Map<String, dynamic>> _locationStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get locationStream =>
      _locationStreamController.stream;

  bool get isTracking => _isTracking;

  /// Inicializa o foreground task system.
  Future<void> init() async {
    if (_isInitialized) return;

    FlutterForegroundTask.initCommunicationPort();

    void callback(dynamic message) {
      if (message is Map<String, dynamic>) {
        _locationStreamController.add(message);
      } else if (message is Map) {
        _locationStreamController.add(Map<String, dynamic>.from(message));
      }
    }

    FlutterForegroundTask.addTaskDataCallback(callback);
    // Armazena o callback para remoção futura
    _taskDataCallback = callback;

    _isInitialized = true;
    debugPrint('📍 LocationService: Inicializado');
  }

  /// Verifica e solicita permissões de localização.
  Future<bool> requestLocationPermission() async {
    if (kIsWeb) return false;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('❌ Serviço de localização está desativado');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('❌ Permissão de localização negada');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('❌ Permissão de localização permanentemente negada');
      return false;
    }

    // Garante fortemente a permissão de segundo plano via permission_handler
    final bgStatus = await Permission.locationAlways.status;
    if (!bgStatus.isGranted) {
      await Permission.locationAlways.request();
    }

    return true;
  }

  /// Obtém a posição atual (one-shot).
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
      debugPrint('❌ Erro ao obter posição: $e');
      return null;
    }
  }

  /// Obtém o nível atual da bateria.
  Future<int> getBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (e) {
      debugPrint('❌ Erro ao obter nível da bateria: $e');
      return -1;
    }
  }

  /// Obtém informações do dispositivo.
  Map<String, dynamic> getDeviceInfo() {
    return {
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
    };
  }

  /// Inicia o rastreamento em segundo plano. Na web, usa um Timer local.
  Future<bool> startTracking({int intervalMinutes = 5}) async {
    if (_isTracking) return false;

    final hasPermission = await requestLocationPermission();
    if (!hasPermission) return false;

    // Mobile Nativo usa serviço persistente (Foreground Service)
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'alinhaja_location_tracking',
        channelName: 'Rastreamento de Localização',
        channelDescription: 'Rastreamento de localização ativo no AlinhaJá.',
        onlyAlertOnce: true,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          intervalMinutes * 60 * 1000, // ms
        ),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 300,
      notificationTitle: 'AlinhaJá — Rastreamento ativo',
      notificationText: 'Monitorando localização a cada $intervalMinutes min',
      notificationButtons: [
        const NotificationButton(id: 'btn_stop', text: 'Parar'),
      ],
      notificationInitialRoute: '/settings/location',
      callback: locationTaskCallback,
    );

    _isTracking = result is ServiceRequestSuccess;

    if (_isTracking) {
      debugPrint('📍 Rastreamento iniciado (intervalo: ${intervalMinutes}min)');
    } else {
      debugPrint('❌ Falha ao iniciar rastreamento');
    }

    if (_isTracking) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('location_tracking_active', true);
      await prefs.setInt('location_tracking_interval', intervalMinutes);
    }

    return _isTracking;
  }

  /// Para o rastreamento.
  Future<void> stopTracking() async {
    if (_taskDataCallback != null) {
      FlutterForegroundTask.removeTaskDataCallback(_taskDataCallback!);
    }
    await FlutterForegroundTask.stopService();
    _isTracking = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('location_tracking_active', false);

    debugPrint('📍 Rastreamento parado');
  }

  Future<bool> isServiceRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }
}
