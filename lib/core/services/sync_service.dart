import 'dart:async';
import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/services/offline_cache_service.dart';
import 'package:alinha_ja/core/services/backup_service.dart';
import 'package:alinha_ja/core/services/media_cache_manager.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const int _maxRetries = 5;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;
  bool _isConnected = false;

  void init() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((results) => _onConnectivity(results));

    // Tentar primeira sincronização ao inicializar
    Connectivity().checkConnectivity().then(_onConnectivity);

    MediaCacheManager.runStorageCleanup();
  }

  /// Sincroniza só na VOLTA da conexão (offline → online). Trocar de Wi-Fi
  /// para 4G também emite evento "online"; antes cada troca rebaixava o
  /// espelho de 30 dias de mensagens, competindo com o chat pela rede. O
  /// primeiro evento e o `checkConnectivity` do boot também não duplicam.
  void _onConnectivity(List<ConnectivityResult> results) {
    final isOnline = !results.every((r) => r == ConnectivityResult.none);
    final cameOnline = isOnline && !_isConnected;
    _isConnected = isOnline;
    if (!cameOnline) return;

    syncPendingOperations();
    BackupService.syncRecentMessages();
    // Opt-in, só em Wi-Fi e no máximo uma vez por dia — as três
    // condições são verificadas dentro do próprio método.
    BackupService.executarBackupAutomatico();
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  bool get isConnected => _isConnected;

  Future<void> syncPendingOperations() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final pendingOps = OfflineCacheService.getPendingOperations();
      if (pendingOps.isEmpty) {
        _isSyncing = false;
        return;
      }

      log('🔄 [SyncService] Sincronizando ${pendingOps.length} operações pendentes...');

      for (final op in pendingOps) {
        final tempId = op['temp_id'] as String?;
        if (tempId == null) {
          await OfflineCacheService.removeOperation(
              DateTime.now().millisecondsSinceEpoch.toString());
          continue;
        }

        final type = op['type'];
        final payload = op['payload'] as Map<String, dynamic>?;

        if (payload == null) {
          await OfflineCacheService.removeOperation(tempId);
          continue;
        }

        try {
          if (type == 'insert_message') {
            await _syncInsertMessage(payload);
          } else if (type == 'insert_channel_message') {
            await _syncInsertChannelMessage(payload);
          } else {
            log('⚠️ [SyncService] Operação de tipo desconhecido ($type) ignorada silenciosamente.');
          }
          // Remove from queue upon success (ou após ignorar op desconhecida)
          await OfflineCacheService.removeOperation(tempId);
          log('✅ [SyncService] Operação $tempId resolvida (sincronizada ou ignorada).');
        } catch (e) {
          final retryCount = (op['retry_count'] as int?) ?? 0;
          if (retryCount >= _maxRetries) {
            log('❌ [SyncService] Operação $tempId excedeu $_maxRetries tentativas. Removendo da fila.');
            await OfflineCacheService.removeOperation(tempId);
          } else {
            log('⚠️ [SyncService] Falha ao sincronizar operação $tempId (tentativa ${retryCount + 1}/$_maxRetries): $e');
            await OfflineCacheService.updateOperation(
              tempId,
              {'retry_count': retryCount + 1},
            );
          }
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncInsertMessage(Map<String, dynamic> payload) async {
    await supabase.from('messages').insert(payload);
  }

  Future<void> _syncInsertChannelMessage(Map<String, dynamic> payload) async {
    await supabase.from('channel_messages').insert(payload);
  }
}
