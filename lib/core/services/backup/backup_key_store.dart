import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda a senha do backup para que o automático possa rodar sem
/// perguntá-la a cada execução.
///
/// **Só é escrito quando o titular liga o backup automático.** No modo
/// manual a senha existe apenas na memória do processo, durante a operação.
///
/// Onde a senha fica:
///
/// | Plataforma | Cofre                                       |
/// |------------|---------------------------------------------|
/// | Android    | Keystore (`EncryptedSharedPreferences`)     |
/// | iOS/macOS  | Keychain, `first_unlock_this_device`        |
/// | Windows    | DPAPI (`wincred`)                           |
/// | Web        | **não suportado** — ver abaixo              |
///
/// Na web o `flutter_secure_storage` cai para uma chave em `localStorage`,
/// legível por qualquer script na origem. Uma senha de backup ali seria
/// proteção de fachada, então o automático é desabilitado na web e o
/// navegador só faz backup manual.
class BackupKeyStore {
  BackupKeyStore._();

  static const _chave = 'alinhaja_backup_passphrase';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// O automático depende de guardar a senha; onde isso não é seguro, ele
  /// não é oferecido.
  static bool get suportado => !kIsWeb;

  static Future<void> guardar(String senha) async {
    if (!suportado) return;
    await _storage.write(key: _chave, value: senha);
  }

  static Future<String?> ler() async {
    if (!suportado) return null;
    try {
      return await _storage.read(key: _chave);
    } catch (e) {
      debugPrint('[Backup] Cofre indisponível: $e');
      return null;
    }
  }

  /// Apagada ao desligar o automático e em todo logout: a senha não pode
  /// sobreviver à conta que a definiu neste aparelho.
  static Future<void> apagar() async {
    if (!suportado) return;
    try {
      await _storage.delete(key: _chave);
    } catch (e) {
      debugPrint('[Backup] Falha ao limpar o cofre: $e');
    }
  }
}
