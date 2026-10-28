import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:alinha_ja/core/database/drift_database.dart';
import 'package:alinha_ja/core/services/backup/backup_crypto.dart';
import 'package:alinha_ja/core/services/backup/backup_key_store.dart';
import 'package:alinha_ja/core/services/backup/backup_models.dart';
import 'package:alinha_ja/core/services/backup/backup_repository.dart';
import 'package:alinha_ja/core/services/media_url_resolver.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/web_download_helper.dart';
import 'package:alinha_ja/features/auth/services/device_fingerprint_service.dart';

/// Backup de mensagens e dados do titular.
///
/// Três garantias que o módulo anterior não dava:
///
/// * **Escopo.** Nada sai daqui sem estar atribuído ao titular logado. O
///   espelho local é filtrado por `owner_id` e o backup de conta lê do
///   servidor sob a RLS da própria sessão.
/// * **Cifra.** Todo arquivo gerado — nuvem ou disco — é AES-256-GCM com
///   chave derivada de uma senha que só o titular conhece. Ver
///   [BackupCrypto].
/// * **Rastro.** Criar, restaurar e apagar backup são operações registradas
///   em `audit_log` pelas RPCs, como exige o Art. 37 da LGPD.
class BackupService {
  static const BackupRepository _repo = BackupRepository();

  /// Janela do espelho local. Casa com o que `syncRecentMessages` traz e com
  /// a seção 1.7 da Política de Retenção: o banco local é cache, não arquivo.
  static const Duration janelaEspelhoLocal = Duration(days: 30);

  // ══════════════════════════════════════════════════════════
  //  Dispositivo
  // ══════════════════════════════════════════════════════════

  static String? _deviceIdCache;

  /// Registra (ou atualiza) este aparelho e devolve o id do servidor.
  static Future<String> registrarDispositivo() async {
    final cache = _deviceIdCache;
    if (cache != null) return cache;

    final id = await _repo.registrarDispositivo(
      fingerprint: await DeviceFingerprintService.getFingerprint(),
      nome: await DeviceFingerprintService.getDeviceName(),
      plataforma: _plataforma,
    );
    _deviceIdCache = id;
    return id;
  }

  static String get _plataforma {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'desconhecida';
  }

  static Future<List<BackupDevice>> listarDispositivos() =>
      _repo.listarDispositivos();

  static Future<List<BackupSnapshot>> listarBackups() => _repo.listarSnapshots();

  /// Liga ou desliga o backup automático deste aparelho.
  ///
  /// Ligar exige a [senha]: o automático só existe porque a senha fica no
  /// cofre da plataforma. Desligar apaga a senha do cofre.
  static Future<void> definirBackupAutomatico(
    String deviceId,
    bool ativo, {
    String? senha,
  }) async {
    if (ativo) {
      if (!BackupKeyStore.suportado) {
        throw const BackupArquivoInvalido(
          'O backup automático não está disponível no navegador. '
          'Use o aplicativo instalado ou faça backups manuais.',
        );
      }
      if (senha == null || BackupCrypto.validarSenha(senha) != null) {
        throw const BackupArquivoInvalido(
          'Informe a senha do backup para ativar o modo automático.',
        );
      }
      await BackupKeyStore.guardar(senha);
    } else {
      await BackupKeyStore.apagar();
    }
    await _repo.definirAutoBackup(deviceId, ativo);
  }

  /// Executa o backup automático se ele estiver ligado, se houver Wi-Fi e se
  /// o último tiver mais de 24 h.
  ///
  /// Chamado pelo [SyncService] a cada reconexão. Silencioso por desenho —
  /// falha de backup automático não deve interromper o uso do aplicativo;
  /// o resultado aparece no histórico e na auditoria.
  static Future<void> executarBackupAutomatico() async {
    if (!BackupKeyStore.suportado) return;
    if (supabase.auth.currentUser == null) return;

    try {
      // Rede limitada não carrega backup: a promessa feita ao titular no
      // opt-in é "só em Wi-Fi", e franquia de dados é dele.
      final rede = await Connectivity().checkConnectivity();
      final emWifi = rede.any((r) =>
          r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
      if (!emWifi) return;

      final senha = await BackupKeyStore.ler();
      if (senha == null || senha.isEmpty) return;

      final fingerprint = await DeviceFingerprintService.getFingerprint();
      final dispositivos = await _repo.listarDispositivos();
      final atual = dispositivos
          .where((d) => d.fingerprint == fingerprint && d.ativo)
          .firstOrNull;

      if (atual == null || !atual.autoBackup) return;

      final ultimo = atual.ultimoBackup;
      if (ultimo != null &&
          DateTime.now().difference(ultimo) < const Duration(hours: 24)) {
        return;
      }

      _deviceIdCache = atual.id;
      await criarBackupNaNuvem(senha: senha, origem: 'automatico');
      debugPrint('[Backup] Backup automático concluído.');
    } catch (e) {
      debugPrint('[Backup] Backup automático não executado: $e');
    }
  }

  /// Revoga um aparelho e apaga todos os backups que vieram dele.
  ///
  /// Se for este aparelho, a senha guardada no cofre também some. Se for
  /// outro — o celular perdido, tipicamente —, o cofre local fica intacto:
  /// revogar o que sumiu não pode desligar o backup de quem está aqui.
  static Future<void> revogarDispositivo(String deviceId) async {
    await _repo.revogarDispositivo(deviceId);
    if (deviceId == _deviceIdCache) {
      _deviceIdCache = null;
      await BackupKeyStore.apagar();
    }
  }

  static Future<void> excluirBackup(String snapshotId) =>
      _repo.excluir(snapshotId);

  // ══════════════════════════════════════════════════════════
  //  Criação
  // ══════════════════════════════════════════════════════════

  /// Gera um backup cifrado e o envia para a nuvem.
  ///
  /// [escopo] `conta` lê do servidor (mensagens, cadastro e mídias);
  /// `dispositivo` empacota só o espelho local — rápido e sem consumo de
  /// rede além do upload.
  ///
  /// [onProgresso] recebe rótulos curtos para exibição.
  static Future<BackupResultado> criarBackupNaNuvem({
    required String senha,
    BackupEscopo escopo = BackupEscopo.conta,
    bool incluirMidias = true,
    String origem = 'manual',
    void Function(String etapa)? onProgresso,
  }) async {
    final erroSenha = BackupCrypto.validarSenha(senha);
    if (erroSenha != null) throw BackupArquivoInvalido(erroSenha);

    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw const BackupArquivoInvalido('Sessão expirada.');

    onProgresso?.call('Registrando dispositivo...');
    final deviceId = await registrarDispositivo();

    onProgresso?.call('Reservando espaço na nuvem...');
    final preparo = await _repo.preparar(
      deviceId: deviceId,
      escopo: escopo,
      origem: origem,
    );

    onProgresso?.call('Coletando dados...');
    final pacote = await _montarPacote(
      uid: uid,
      escopo: escopo,
      incluirMidias: incluirMidias,
      tetoBytes: preparo.politica.tetoMb * 1024 * 1024,
      onProgresso: onProgresso,
    );

    onProgresso?.call('Cifrando...');
    final envelope = await BackupCrypto.cifrar(
      conteudo: pacote.bytes,
      senha: senha,
    );

    // O que sobe é o `.fxb` inteiro (cabeçalho + ciphertext): assim o objeto
    // baixado do Storage é restaurável por si só, sem depender da linha no
    // banco — que pode já ter expirado pela retenção.
    final arquivo = BackupCrypto.empacotar(envelope, {
      'escopo': escopo.valor,
      'criado_em': DateTime.now().toUtc().toIso8601String(),
      'app': 'alinhaja',
    });

    onProgresso?.call('Enviando...');
    await _repo.enviar(preparo.storagePath, arquivo);

    onProgresso?.call('Finalizando...');
    await _repo.confirmar(
      snapshotId: preparo.snapshotId,
      bytes: arquivo.length,
      sha256: envelope.sha256Hex,
      saltB64: envelope.saltB64,
      nonceB64: envelope.nonceB64,
      wrappedDekB64: envelope.wrappedDekB64,
      conteudo: pacote.resumo,
    );

    return BackupResultado(
      snapshotId: preparo.snapshotId,
      bytes: arquivo.length,
      mensagens: pacote.resumo['mensagens'] as int,
      midias: pacote.resumo['midias'] as int,
      midiasIgnoradas: pacote.resumo['midias_ignoradas'] as int,
    );
  }

  /// Gera o mesmo `.fxb` cifrado, mas salvo no dispositivo em vez da nuvem.
  ///
  /// Substitui o antigo `exportMessagesAsZip`, que produzia um ZIP em claro
  /// com o espelho inteiro do aparelho — inclusive conversas de quem havia
  /// usado a conta anterior.
  static Future<String> exportarParaArquivo({
    required String senha,
    BackupEscopo escopo = BackupEscopo.conta,
    bool incluirMidias = false,
    void Function(String etapa)? onProgresso,
  }) async {
    final erroSenha = BackupCrypto.validarSenha(senha);
    if (erroSenha != null) throw BackupArquivoInvalido(erroSenha);

    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw const BackupArquivoInvalido('Sessão expirada.');

    onProgresso?.call('Coletando dados...');
    final pacote = await _montarPacote(
      uid: uid,
      escopo: escopo,
      incluirMidias: incluirMidias,
      tetoBytes: 200 * 1024 * 1024,
      onProgresso: onProgresso,
    );

    onProgresso?.call('Cifrando...');
    final envelope =
        await BackupCrypto.cifrar(conteudo: pacote.bytes, senha: senha);
    final arquivo = BackupCrypto.empacotar(envelope, {
      'escopo': escopo.valor,
      'criado_em': DateTime.now().toUtc().toIso8601String(),
      'app': 'alinhaja',
    });

    final nome =
        'alinhaja_backup_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.fxb';

    if (kIsWeb) {
      triggerFileDownload(
        'data:application/octet-stream;base64,${base64Encode(arquivo)}',
        nome,
      );
      return 'Download iniciado pelo navegador: $nome';
    }

    final dir = await getApplicationDocumentsDirectory();
    final destino = Directory('${dir.path}/backups');
    if (!await destino.exists()) await destino.create(recursive: true);
    final file = File('${destino.path}/$nome');
    await file.writeAsBytes(arquivo);
    return file.path;
  }

  // ══════════════════════════════════════════════════════════
  //  Restauração
  // ══════════════════════════════════════════════════════════

  /// Baixa, decifra e reinsere um backup da nuvem no espelho local.
  ///
  /// Devolve quantas mensagens entraram. Só restaura para a mesma conta: o
  /// `owner_id` é reescrito com o titular logado, então um `.fxb` de outra
  /// pessoa não contamina o espelho de quem restaura.
  static Future<int> restaurarDaNuvem({
    required BackupSnapshot snapshot,
    required String senha,
    void Function(String etapa)? onProgresso,
  }) async {
    onProgresso?.call('Baixando...');
    final bruto = await _repo.baixar(snapshot.storagePath);

    onProgresso?.call('Verificando integridade...');
    final (header, ciphertext) = BackupCrypto.desempacotar(bruto);

    if (!BackupCrypto.integridadeOk(ciphertext, header['sha256'] as String?)) {
      throw const BackupArquivoInvalido(
        'O arquivo baixado não confere com o registro do backup. '
        'Tente novamente ou escolha outro ponto de restauração.',
      );
    }

    onProgresso?.call('Decifrando...');
    final conteudo = await BackupCrypto.decifrar(
      ciphertext: ciphertext,
      saltB64: header['salt'] as String,
      nonceB64: header['nonce'] as String,
      wrappedDekB64: header['dek'] as String,
      senha: senha,
      iteracoes: (header['iter'] as num?)?.toInt() ?? snapshot.kdfIteracoes,
    );

    onProgresso?.call('Restaurando mensagens...');
    final total = await _restaurarNoEspelho(conteudo);

    await _repo.marcarRestaurado(snapshot.id);
    return total;
  }

  /// Restaura a partir de um `.fxb` escolhido pelo titular no disco.
  static Future<int> restaurarDeArquivo({
    required Uint8List arquivo,
    required String senha,
    void Function(String etapa)? onProgresso,
  }) async {
    onProgresso?.call('Lendo arquivo...');
    final (header, ciphertext) = BackupCrypto.desempacotar(arquivo);

    onProgresso?.call('Decifrando...');
    final conteudo = await BackupCrypto.decifrar(
      ciphertext: ciphertext,
      saltB64: header['salt'] as String,
      nonceB64: header['nonce'] as String,
      wrappedDekB64: header['dek'] as String,
      senha: senha,
      iteracoes: (header['iter'] as num?)?.toInt() ?? 210000,
    );

    onProgresso?.call('Restaurando mensagens...');
    return _restaurarNoEspelho(conteudo);
  }

  static Future<int> _restaurarNoEspelho(Uint8List zipBytes) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw const BackupArquivoInvalido('Sessão expirada.');

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final entrada = archive.files
        .where((f) => f.name == 'mensagens.json' && f.isFile)
        .firstOrNull;
    if (entrada == null) return 0;

    final dados = jsonDecode(utf8.decode(entrada.content as List<int>));
    final mensagens = (dados is Map ? dados['mensagens'] : dados) as List? ?? [];

    await driftDb.batch((batch) {
      for (final raw in mensagens) {
        final m = Map<String, dynamic>.from(raw as Map);
        batch.insert(
          driftDb.localMessages,
          LocalMessagesCompanion.insert(
            id: m['id'] as String,
            // Reescrito de propósito: quem restaura vira o dono da linha.
            ownerId: drift.Value(uid),
            chatId: m['chatId'] as String? ?? '',
            senderId: m['senderId'] as String? ?? '',
            content: drift.Value(m['content'] as String?),
            contentType: drift.Value(m['contentType'] as String? ?? 'text'),
            mediaUrl: drift.Value(m['mediaUrl'] as String?),
            metadata: drift.Value(m['metadata'] as String?),
            isChannel: drift.Value(m['isChannel'] as bool? ?? false),
            createdAt: DateTime.tryParse(m['createdAt']?.toString() ?? '') ??
                DateTime.now(),
            syncedAt: drift.Value(DateTime.now()),
          ),
          mode: drift.InsertMode.insertOrReplace,
        );
      }
    });

    return mensagens.length;
  }

  // ══════════════════════════════════════════════════════════
  //  Montagem do pacote
  // ══════════════════════════════════════════════════════════

  static Future<_Pacote> _montarPacote({
    required String uid,
    required BackupEscopo escopo,
    required bool incluirMidias,
    required int tetoBytes,
    void Function(String etapa)? onProgresso,
  }) async {
    final archive = Archive();

    final mensagens = escopo == BackupEscopo.dispositivo
        ? await _mensagensDoEspelho(uid)
        : await _mensagensDoServidor(uid);

    _adicionar(archive, 'mensagens.json',
        jsonEncode({'mensagens': mensagens, 'total': mensagens.length}));

    var midiasIncluidas = 0;
    var midiasIgnoradas = 0;
    var bytesMidia = 0;

    if (escopo == BackupEscopo.conta) {
      onProgresso?.call('Coletando cadastro...');
      try {
        final meus = await supabase.rpc('export_my_data');
        _adicionar(archive, 'dados_titular.json', jsonEncode(meus));
      } catch (e) {
        debugPrint('[Backup] export_my_data indisponível: $e');
      }
    }

    if (incluirMidias) {
      onProgresso?.call('Baixando mídias...');
      final urls = mensagens
          .map((m) => m['mediaUrl'] as String?)
          .whereType<String>()
          .where((u) => u.isNotEmpty)
          .toSet()
          .toList();

      for (final url in urls) {
        // Teto por snapshot: a mídia entra enquanto couber. O que não coube
        // é contado e informado — backup que silencia o que ficou de fora
        // dá ao titular uma garantia que não tem.
        if (bytesMidia >= tetoBytes) {
          midiasIgnoradas++;
          continue;
        }
        final bytes = await _baixarMidia(url);
        if (bytes == null || bytesMidia + bytes.length > tetoBytes) {
          midiasIgnoradas++;
          continue;
        }
        _adicionarBytes(archive, 'midias/${_nomeDeArquivo(url)}', bytes);
        bytesMidia += bytes.length;
        midiasIncluidas++;
      }
    }

    final resumo = <String, dynamic>{
      'mensagens': mensagens.length,
      'midias': midiasIncluidas,
      'midias_ignoradas': midiasIgnoradas,
      'bytes_midia': bytesMidia,
      'escopo': escopo.valor,
      'formato': BackupCrypto.formatoVersao,
    };

    _adicionar(
      archive,
      'manifest.json',
      const JsonEncoder.withIndent('  ').convert({
        ...resumo,
        'gerado_em': DateTime.now().toUtc().toIso8601String(),
        'titular': uid,
      }),
    );

    final zip = ZipEncoder().encode(archive);
    return _Pacote(bytes: Uint8List.fromList(zip), resumo: resumo);
  }

  /// Mensagens do espelho local — apenas as do titular logado.
  static Future<List<Map<String, dynamic>>> _mensagensDoEspelho(
      String uid) async {
    final rows = await (driftDb.select(driftDb.localMessages)
          ..where((t) => t.ownerId.equals(uid)))
        .get();
    return rows
        .map((m) => <String, dynamic>{
              'id': m.id,
              'chatId': m.chatId,
              'senderId': m.senderId,
              'content': m.content,
              'contentType': m.contentType,
              'mediaUrl': m.mediaUrl,
              'metadata': m.metadata,
              'isChannel': m.isChannel,
              'createdAt': m.createdAt.toIso8601String(),
              'syncedAt': m.syncedAt?.toIso8601String(),
            })
        .toList();
  }

  /// Mensagens direto do servidor, sob a RLS da sessão: o backup de conta
  /// não depende do que por acaso está em cache neste aparelho.
  static Future<List<Map<String, dynamic>>> _mensagensDoServidor(
      String uid) async {
    final out = <Map<String, dynamic>>[];

    // Paginado: sem isso a resposta é truncada silenciosamente no limite do
    // PostgREST e o titular receberia um "backup completo" pela metade — a
    // pior falha possível num backup, porque só aparece na restauração.
    const pagina = 1000;

    Future<void> puxar(String tabela, String colunaChat, bool canal) async {
      var offset = 0;
      while (true) {
        final res = await supabase
            .from(tabela)
            .select()
            .order('created_at', ascending: false)
            .range(offset, offset + pagina - 1);

        final lote = res as List;
        for (final raw in lote) {
          final m = Map<String, dynamic>.from(raw as Map);
          out.add({
            'id': m['id'],
            'chatId': m[colunaChat],
            'senderId': m['sender_id'],
            'content': m['content'],
            'contentType': m['content_type'] ?? 'text',
            'mediaUrl': m['media_url'],
            'metadata':
                m['metadata'] != null ? jsonEncode(m['metadata']) : null,
            'isChannel': canal,
            'createdAt': m['created_at'],
          });
        }

        if (lote.length < pagina) break;
        offset += pagina;
      }
    }

    await puxar('messages', 'chat_id', false);
    await puxar('channel_messages', 'channel_id', true);
    return out;
  }

  static Future<Uint8List?> _baixarMidia(String url) async {
    try {
      // `messages.media_url` guarda a URL pública histórica, mas o bucket
      // chat-media é privado: sem assinar, o download volta 400. O resolver
      // aplica a policy de membership, então a mídia que o titular não pode
      // ver também não entra no backup dele.
      final assinada = await MediaUrlResolver.resolve(url);
      final resp = await http
          .get(Uri.parse(assinada))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;
      return resp.bodyBytes;
    } catch (e) {
      debugPrint('[Backup] Falha ao baixar mídia: $e');
      return null;
    }
  }

  static String _nomeDeArquivo(String url) {
    final semQuery = url.split('?').first;
    final nome = semQuery.split('/').last;
    return nome.isEmpty ? 'arquivo.bin' : nome;
  }

  static void _adicionar(Archive archive, String nome, String conteudo) =>
      _adicionarBytes(archive, nome, Uint8List.fromList(utf8.encode(conteudo)));

  static void _adicionarBytes(Archive archive, String nome, Uint8List bytes) =>
      archive.addFile(ArchiveFile(nome, bytes.length, bytes));

  // ══════════════════════════════════════════════════════════
  //  Espelho local
  // ══════════════════════════════════════════════════════════

  /// Sincroniza as mensagens recentes do Supabase para o espelho local.
  ///
  /// Duas correções em relação à versão anterior: cada linha passa a ser
  /// atribuída ao titular logado, e o que ficou de outras contas ou saiu da
  /// janela de retenção é apagado a cada execução.
  ///
  /// Baixa 30 dias de mensagens: roda no máximo a cada
  /// [_intervaloMinimoEspelho] e nunca em paralelo, para não competir com o
  /// chat pela rede em conexão instável.
  static Future<void> syncRecentMessages() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final ultima = _ultimoEspelhoTitular == uid ? _ultimoEspelho : null;
    if (_espelhando ||
        (ultima != null &&
            DateTime.now().difference(ultima) < _intervaloMinimoEspelho)) {
      return;
    }
    _espelhando = true;

    try {
      final agora = DateTime.now().toUtc();
      final corte = agora.subtract(janelaEspelhoLocal);

      // As duas consultas são independentes: em paralelo.
      final consultas = await Future.wait([
        supabase
            .from('messages')
            .select()
            .gte('created_at', corte.toIso8601String()),
        supabase
            .from('channel_messages')
            .select()
            .gte('created_at', corte.toIso8601String()),
      ]);
      final res = consultas[0];
      final resCanais = consultas[1];

      await driftDb.batch((batch) {
        for (final raw in res as List) {
          batch.insert(driftDb.localMessages, _companion(raw, uid, agora, false),
              mode: drift.InsertMode.insertOrReplace);
        }
        for (final raw in resCanais as List) {
          batch.insert(driftDb.localMessages, _companion(raw, uid, agora, true),
              mode: drift.InsertMode.insertOrReplace);
        }
      });

      await purgarEspelhoLocal(manterTitular: uid);
      _ultimoEspelho = DateTime.now();
      _ultimoEspelhoTitular = uid;
      debugPrint('[Backup] Espelho local sincronizado.');
    } catch (e) {
      debugPrint('[Backup] Erro ao sincronizar mensagens: $e');
    } finally {
      _espelhando = false;
    }
  }

  static const Duration _intervaloMinimoEspelho = Duration(minutes: 15);
  static DateTime? _ultimoEspelho;
  static String? _ultimoEspelhoTitular;
  static bool _espelhando = false;

  static LocalMessagesCompanion _companion(
      dynamic raw, String uid, DateTime agora, bool canal) {
    final m = Map<String, dynamic>.from(raw as Map);
    return LocalMessagesCompanion.insert(
      id: m['id'] as String,
      ownerId: drift.Value(uid),
      chatId: (canal ? m['channel_id'] : m['chat_id']) as String,
      senderId: m['sender_id'] as String,
      content: drift.Value(m['content'] as String?),
      contentType: drift.Value(m['content_type'] as String? ?? 'text'),
      mediaUrl: drift.Value(m['media_url'] as String?),
      metadata: drift.Value(
          m['metadata'] != null ? jsonEncode(m['metadata']) : null),
      isChannel: drift.Value(canal),
      createdAt: DateTime.parse(m['created_at'] as String),
      syncedAt: drift.Value(agora),
    );
  }

  /// Apaga do espelho o que não pertence a [manterTitular] e o que passou da
  /// janela de retenção.
  ///
  /// Chamado no login (com o novo titular), no logout (sem titular, apaga
  /// tudo) e ao fim de cada sincronização.
  static Future<void> purgarEspelhoLocal({String? manterTitular}) async {
    try {
      if (manterTitular == null) {
        await driftDb.delete(driftDb.localMessages).go();
        return;
      }

      await (driftDb.delete(driftDb.localMessages)
            ..where((t) => t.ownerId.equals(manterTitular).not()))
          .go();

      final corte = DateTime.now().toUtc().subtract(janelaEspelhoLocal);
      await (driftDb.delete(driftDb.localMessages)
            ..where((t) => t.createdAt.isSmallerThanValue(corte)))
          .go();
    } catch (e) {
      debugPrint('[Backup] Erro ao purgar espelho local: $e');
    }
  }

  /// Limpa tudo que a conta deixou neste aparelho: espelho de mensagens e
  /// cache de mídia. Executado no logout — a seção 1.7 da Política de
  /// Retenção promete que o banco local dura "até sair da conta".
  static Future<void> limparDadosDoDispositivo() async {
    _deviceIdCache = null;
    // A senha do backup automático é da conta que a definiu: não pode ficar
    // no cofre à disposição de quem entrar depois neste aparelho.
    await BackupKeyStore.apagar();
    await purgarEspelhoLocal();
    try {
      final itens = await driftDb.select(driftDb.mediaCache).get();
      if (!kIsWeb) {
        for (final item in itens) {
          final path = item.localPath;
          if (path == null) continue;
          final f = File(path);
          if (await f.exists()) await f.delete();
        }
      }
      await driftDb.delete(driftDb.mediaCache).go();
    } catch (e) {
      debugPrint('[Backup] Erro ao limpar cache de mídia: $e');
    }
  }

  /// Quantas mensagens do titular logado estão no espelho local.
  static Future<int> getLocalMessageCount() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return 0;
      final contagem = driftDb.localMessages.id.count();
      final query = driftDb.selectOnly(driftDb.localMessages)
        ..addColumns([contagem])
        ..where(driftDb.localMessages.ownerId.equals(uid));
      return await query.map((row) => row.read(contagem)).getSingle() ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

class _Pacote {
  final Uint8List bytes;
  final Map<String, dynamic> resumo;
  const _Pacote({required this.bytes, required this.resumo});
}
