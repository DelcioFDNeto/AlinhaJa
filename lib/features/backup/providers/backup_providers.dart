import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/services/backup/backup_key_store.dart';
import 'package:alinha_ja/core/services/backup/backup_models.dart';
import 'package:alinha_ja/core/services/backup/backup_repository.dart';
import 'package:alinha_ja/core/services/backup_service.dart';
import 'package:alinha_ja/features/auth/services/device_fingerprint_service.dart';

/// Backups em nuvem do titular logado, do mais recente para o mais antigo.
final meusBackupsProvider =
    FutureProvider.autoDispose<List<BackupSnapshot>>((ref) async {
  return BackupService.listarBackups();
});

/// Aparelhos que já geraram backup para esta conta.
final meusDispositivosProvider =
    FutureProvider.autoDispose<List<BackupDevice>>((ref) async {
  return BackupService.listarDispositivos();
});

/// O aparelho em uso, já registrado no servidor.
///
/// Registrar no carregamento da tela é intencional: o titular precisa ver
/// "este dispositivo" na lista antes de fazer o primeiro backup, senão não
/// há como ligar o automático nem entender de onde cada snapshot veio.
final dispositivoAtualProvider =
    FutureProvider.autoDispose<BackupDevice?>((ref) async {
  await BackupService.registrarDispositivo();
  final fingerprint = await DeviceFingerprintService.getFingerprint();
  final lista = await BackupService.listarDispositivos();
  for (final d in lista) {
    if (d.fingerprint == fingerprint) return d;
  }
  return null;
});

/// Quantas mensagens do titular estão no espelho local deste aparelho.
final espelhoLocalProvider = FutureProvider.autoDispose<int>((ref) async {
  return BackupService.getLocalMessageCount();
});

/// Se o cofre da plataforma permite guardar a senha do backup automático.
final backupAutomaticoDisponivelProvider =
    Provider<bool>((ref) => BackupKeyStore.suportado);

/// Visão de governança do administrador: política vigente, cobertura e
/// volume por titular. Nunca inclui caminho de arquivo, envelope ou
/// conteúdo — o servidor simplesmente não expõe isso a ninguém.
final visaoAdminBackupProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return const BackupRepository().visaoAdministrativa();
});

/// Recarrega tudo depois de uma operação que muda o estado no servidor.
void recarregarBackup(WidgetRef ref) {
  ref.invalidate(meusBackupsProvider);
  ref.invalidate(meusDispositivosProvider);
  ref.invalidate(dispositivoAtualProvider);
  ref.invalidate(espelhoLocalProvider);
}
