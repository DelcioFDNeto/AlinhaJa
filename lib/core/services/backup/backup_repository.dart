import 'dart:typed_data';

import 'package:alinha_ja/core/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backup_models.dart';

/// Acesso ao backup em nuvem.
///
/// Toda escrita passa por RPC `SECURITY DEFINER`: as tabelas
/// `backup_devices` e `backup_snapshots` têm INSERT/UPDATE/DELETE revogados
/// de `authenticated`. Assim o cliente não escolhe o caminho no Storage,
/// não forja vínculo de organização, não burla quota nem deixa de auditar.
class BackupRepository {
  const BackupRepository();

  static const String bucket = 'backups';

  // ── Dispositivos ───────────────────────────────────────────

  Future<String> registrarDispositivo({
    required String fingerprint,
    required String nome,
    required String plataforma,
  }) async {
    final id = await supabase.rpc('backup_register_device', params: {
      'p_fingerprint': fingerprint,
      'p_name': nome,
      'p_platform': plataforma,
    });
    return id as String;
  }

  Future<List<BackupDevice>> listarDispositivos() async {
    final rows = await supabase
        .from('backup_devices')
        .select()
        .order('last_seen_at', ascending: false);
    return (rows as List)
        .map((r) => BackupDevice.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> definirAutoBackup(String deviceId, bool ativo) async {
    await supabase.rpc('backup_set_auto', params: {
      'p_device_id': deviceId,
      'p_ativo': ativo,
    });
  }

  /// Revoga o aparelho e apaga todos os snapshots que vieram dele.
  Future<void> revogarDispositivo(String deviceId) async {
    final res = await supabase
        .rpc('backup_revoke_device', params: {'p_device_id': deviceId});
    await _purgarObjetos(_paths(res, 'removidos'));
  }

  // ── Snapshots ──────────────────────────────────────────────

  Future<List<BackupSnapshot>> listarSnapshots() async {
    final rows = await supabase
        .from('backup_snapshots')
        .select()
        .eq('status', 'concluido')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => BackupSnapshot.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Abre o snapshot no servidor. Devolve o id, o caminho reservado e a
  /// política vigente — inclusive o teto de tamanho, que o serviço usa para
  /// decidir quantas mídias cabem.
  Future<({String snapshotId, String storagePath, BackupPolitica politica})>
      preparar({
    required String deviceId,
    required BackupEscopo escopo,
    required String origem,
  }) async {
    final res = await supabase.rpc('backup_prepare', params: {
      'p_device_id': deviceId,
      'p_escopo': escopo.valor,
      'p_origem': origem,
    });
    final m = Map<String, dynamic>.from(res as Map);
    return (
      snapshotId: m['snapshot_id'] as String,
      storagePath: m['storage_path'] as String,
      politica: BackupPolitica(
        retencaoDias: 0, // não usado no caminho de escrita
        maxPorDispositivo: 0,
        tetoMb: (m['teto_mb'] as num?)?.toInt() ?? 200,
      ),
    );
  }

  Future<void> enviar(String storagePath, Uint8List bytes) async {
    await supabase.storage.from(bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/octet-stream',
            upsert: true,
          ),
        );
  }

  Future<void> confirmar({
    required String snapshotId,
    required int bytes,
    required String sha256,
    required String saltB64,
    required String nonceB64,
    required String wrappedDekB64,
    required Map<String, dynamic> conteudo,
  }) async {
    final res = await supabase.rpc('backup_commit', params: {
      'p_snapshot_id': snapshotId,
      'p_size_bytes': bytes,
      'p_sha256': sha256,
      'p_kdf_salt': saltB64,
      'p_nonce': nonceB64,
      'p_wrapped_dek': wrappedDekB64,
      'p_conteudo': conteudo,
    });
    // Snapshots podados pela quota: a linha e o registro em storage.objects
    // já sumiram no servidor; aqui só completamos o purge físico.
    await _purgarObjetos(_paths(res, 'podados'));
  }

  Future<Uint8List> baixar(String storagePath) async {
    return supabase.storage.from(bucket).download(storagePath);
  }

  Future<void> marcarRestaurado(String snapshotId) async {
    await supabase
        .rpc('backup_mark_restored', params: {'p_snapshot_id': snapshotId});
  }

  Future<void> excluir(String snapshotId) async {
    final path =
        await supabase.rpc('backup_delete', params: {'p_snapshot_id': snapshotId});
    if (path is String && path.isNotEmpty) {
      await _purgarObjetos([path]);
    }
  }

  // ── Governança (admin) ─────────────────────────────────────

  Future<Map<String, dynamic>> visaoAdministrativa() async {
    final res = await supabase.rpc('admin_backup_overview');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> definirPolitica({
    required int dias,
    int? maxPorDispositivo,
    int? tetoMb,
  }) async {
    await supabase.rpc('set_retencao_backup', params: {
      'p_dias': dias,
      'p_max_por_dispositivo': maxPorDispositivo,
      'p_teto_mb': tetoMb,
    });
  }

  // ── Internos ───────────────────────────────────────────────

  List<String> _paths(dynamic res, String chave) {
    if (res is! Map) return const [];
    final lista = res[chave];
    if (lista is! List) return const [];
    return lista.whereType<String>().toList();
  }

  /// O servidor já removeu a linha em `storage.objects`, o que basta para
  /// tornar o arquivo inacessível pela API. Esta chamada faz o purge físico;
  /// se falhar, o objeto fica órfão e inalcançável — não vale derrubar a
  /// operação do titular por isso.
  Future<void> _purgarObjetos(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await supabase.storage.from(bucket).remove(paths);
    } catch (_) {
      // Silencioso por desenho: ver comentário acima.
    }
  }
}
