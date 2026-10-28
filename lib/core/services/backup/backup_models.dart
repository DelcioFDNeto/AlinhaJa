import 'package:flutter/foundation.dart';

/// Alcance do que entra no snapshot.
enum BackupEscopo {
  /// Tudo que o titular possui no servidor: mensagens, cadastro, mídias.
  conta('conta'),

  /// Só o espelho local deste aparelho — rápido e sem custo de rede.
  dispositivo('dispositivo');

  const BackupEscopo(this.valor);
  final String valor;

  static BackupEscopo doValor(String? v) =>
      v == 'dispositivo' ? BackupEscopo.dispositivo : BackupEscopo.conta;

  String get rotulo => switch (this) {
        BackupEscopo.conta => 'Conta completa',
        BackupEscopo.dispositivo => 'Este dispositivo',
      };
}

/// Aparelho habilitado a gerar backup para a conta.
@immutable
class BackupDevice {
  final String id;
  final String fingerprint;
  final String nome;
  final String plataforma;
  final bool autoBackup;
  final DateTime? ultimoAcesso;
  final DateTime? ultimoBackup;
  final DateTime? revogadoEm;

  const BackupDevice({
    required this.id,
    required this.fingerprint,
    required this.nome,
    required this.plataforma,
    required this.autoBackup,
    this.ultimoAcesso,
    this.ultimoBackup,
    this.revogadoEm,
  });

  bool get ativo => revogadoEm == null;

  factory BackupDevice.fromMap(Map<String, dynamic> m) => BackupDevice(
        id: m['id'] as String,
        fingerprint: m['fingerprint'] as String? ?? '',
        nome: m['device_name'] as String? ?? 'Dispositivo',
        plataforma: m['platform'] as String? ?? 'desconhecida',
        autoBackup: m['auto_backup'] as bool? ?? false,
        ultimoAcesso: _data(m['last_seen_at']),
        ultimoBackup: _data(m['last_backup_at']),
        revogadoEm: _data(m['revoked_at']),
      );
}

/// Metadado de um backup em nuvem. Não carrega conteúdo: o que está aqui
/// descreve o envelope e o volume, nunca o dado cifrado.
@immutable
class BackupSnapshot {
  final String id;
  final String? deviceId;
  final BackupEscopo escopo;
  final String origem; // 'manual' | 'automatico'
  final String status; // 'pendente' | 'concluido' | 'falhou'
  final String storagePath;
  final int sizeBytes;
  final String? sha256;
  final String? kdfSalt;
  final String? nonce;
  final String? wrappedDek;
  final int kdfIteracoes;
  final Map<String, dynamic> conteudo;
  final DateTime criadoEm;
  final DateTime? concluidoEm;
  final DateTime? ultimoRestore;
  final DateTime expiraEm;

  const BackupSnapshot({
    required this.id,
    required this.deviceId,
    required this.escopo,
    required this.origem,
    required this.status,
    required this.storagePath,
    required this.sizeBytes,
    required this.kdfIteracoes,
    required this.conteudo,
    required this.criadoEm,
    required this.expiraEm,
    this.sha256,
    this.kdfSalt,
    this.nonce,
    this.wrappedDek,
    this.concluidoEm,
    this.ultimoRestore,
  });

  bool get concluido => status == 'concluido';

  int get mensagens => (conteudo['mensagens'] as num?)?.toInt() ?? 0;
  int get midias => (conteudo['midias'] as num?)?.toInt() ?? 0;
  int get midiasIgnoradas => (conteudo['midias_ignoradas'] as num?)?.toInt() ?? 0;

  /// Quantos dias faltam para o expurgo automático da política de retenção.
  int get diasParaExpirar =>
      expiraEm.difference(DateTime.now()).inDays.clamp(0, 100000);

  String get tamanhoLegivel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory BackupSnapshot.fromMap(Map<String, dynamic> m) => BackupSnapshot(
        id: m['id'] as String,
        deviceId: m['device_id'] as String?,
        escopo: BackupEscopo.doValor(m['escopo'] as String?),
        origem: m['origem'] as String? ?? 'manual',
        status: m['status'] as String? ?? 'pendente',
        storagePath: m['storage_path'] as String? ?? '',
        sizeBytes: (m['size_bytes'] as num?)?.toInt() ?? 0,
        sha256: m['sha256'] as String?,
        kdfSalt: m['kdf_salt'] as String?,
        nonce: m['nonce'] as String?,
        wrappedDek: m['wrapped_dek'] as String?,
        kdfIteracoes: (m['kdf_iteracoes'] as num?)?.toInt() ?? 210000,
        conteudo: Map<String, dynamic>.from(
            (m['conteudo'] as Map?) ?? const <String, dynamic>{}),
        criadoEm: _data(m['created_at']) ?? DateTime.now(),
        concluidoEm: _data(m['concluido_em']),
        ultimoRestore: _data(m['ultimo_restore_em']),
        expiraEm: _data(m['expires_at']) ?? DateTime.now(),
      );
}

/// Política de backup vigente na organização, devolvida pelo `backup_prepare`.
@immutable
class BackupPolitica {
  final int retencaoDias;
  final int maxPorDispositivo;
  final int tetoMb;

  const BackupPolitica({
    required this.retencaoDias,
    required this.maxPorDispositivo,
    required this.tetoMb,
  });

  factory BackupPolitica.fromMap(Map<String, dynamic> m) => BackupPolitica(
        retencaoDias: (m['retencao_dias'] as num?)?.toInt() ?? 90,
        maxPorDispositivo: (m['max_dispositivo'] as num?)?.toInt() ?? 5,
        tetoMb: (m['teto_mb'] as num?)?.toInt() ?? 200,
      );
}

/// Resultado de um backup concluído, para exibir ao titular.
@immutable
class BackupResultado {
  final String snapshotId;
  final int bytes;
  final int mensagens;
  final int midias;
  final int midiasIgnoradas;

  const BackupResultado({
    required this.snapshotId,
    required this.bytes,
    required this.mensagens,
    required this.midias,
    required this.midiasIgnoradas,
  });
}

DateTime? _data(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  return DateTime.tryParse(v.toString())?.toLocal();
}
