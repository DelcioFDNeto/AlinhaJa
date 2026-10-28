import 'dart:async';
import 'package:flutter/foundation.dart';

class RealtimePollingService {
  static final RealtimePollingService instance =
      RealtimePollingService._internal();
  RealtimePollingService._internal();

  Timer? _pollTimer;
  bool _isRealtimeConnected = true;
  int _pollIntervalSeconds = 30;
  Function()? onRealtimeStatusChanged;
  Function()? onPollNeeded;

  bool get isRealtimeConnected => _isRealtimeConnected;

  void init() {
    _startMonitoring();
  }

  void _startMonitoring() {
    // Inicia o polling de verificação
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: _pollIntervalSeconds), (_) {
      _checkConnection();
    });
  }

  void _checkConnection() {
    if (!_isRealtimeConnected) {
      onPollNeeded?.call();
    }
  }

  /// Chamar quando o app detectar que Realtime falhou
  void triggerRealtimeFailure() {
    if (_isRealtimeConnected) {
      _isRealtimeConnected = false;
      onRealtimeStatusChanged?.call();
      debugPrint('📡 Realtime: Fallback para polling ativado');
    }
  }

  /// Chamar quando o app detectar que Realtime voltou
  void triggerRealtimeRecovery() {
    if (!_isRealtimeConnected) {
      _isRealtimeConnected = true;
      onRealtimeStatusChanged?.call();
      debugPrint('📡 Realtime: Conexão restaurada');
    }
  }

  /// Poll manual quando Realtime está offline
  void triggerManualPoll() {
    debugPrint('📡 Realtime: Poll manual acionado');
    onPollNeeded?.call();
  }

  /// Ajustar intervalo de polling
  void setPollInterval(int seconds) {
    _pollIntervalSeconds = seconds;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: _pollIntervalSeconds), (_) {
      if (!_isRealtimeConnected) {
        onPollNeeded?.call();
      }
    });
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}

/// inicializar o serviço no main.dart
/// RealtimePollingService.instance.init();
