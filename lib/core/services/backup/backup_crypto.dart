import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import 'package:alinha_ja/core/constants.dart';

/// Envelope criptográfico de um backup.
///
/// Só o [ciphertext] carrega dado pessoal. [salt], [nonce] e [wrappedDek]
/// são material público do envelope: sozinhos não revelam nada e sem eles
/// nem o próprio titular consegue restaurar. Por isso ficam no banco, ao
/// lado do metadado, e também dentro do arquivo `.fxb`.
@immutable
class BackupEnvelope {
  final Uint8List ciphertext;
  final String saltB64;
  final String nonceB64;
  final String wrappedDekB64;
  final int iteracoes;
  final String sha256Hex;

  const BackupEnvelope({
    required this.ciphertext,
    required this.saltB64,
    required this.nonceB64,
    required this.wrappedDekB64,
    required this.iteracoes,
    required this.sha256Hex,
  });
}

/// Cifra e decifra backups no dispositivo.
///
/// Desenho de chaves:
///
/// ```
/// DEK  = 32 bytes aleatórios, novos a cada snapshot
/// KEK  = PBKDF2-HMAC-SHA256(senha do titular, salt, 210_000)
/// arquivo    = AES-256-GCM(DEK, nonce, conteúdo)
/// wrappedDek = nonce(12) || AES-256-GCM(KEK, nonce, DEK)
/// ```
///
/// A senha nunca sai do aparelho e não é gravada em lugar nenhum — nem em
/// `SharedPreferences`, nem no keychain. O servidor recebe apenas bytes
/// opacos, o que mantém o backup fora do alcance de quem tenha acesso ao
/// banco, ao Storage ou a um dump de qualquer um dos dois.
class BackupCrypto {
  BackupCrypto._();

  /// Assinatura do formato. Permite reconhecer um `.fxb` e recusar cedo um
  /// arquivo trocado, em vez de falhar como erro de decifragem.
  static const List<int> magic = <int>[0x46, 0x58, 0x42, 0x31]; // "FXB1"

  static const int formatoVersao = 1;
  static const int _iteracoesPadrao = 210000; // OWASP PBKDF2-HMAC-SHA256
  static const int _tamanhoChave = 32; // AES-256
  static const int _tamanhoNonce = 12; // GCM
  static const int _tamanhoSalt = 16;
  static const int _tamanhoTag = 128; // bits

  static final Random _rng = Random.secure();

  /// Requisito mínimo de senha do backup.
  ///
  /// Não há segunda barreira: quem obtiver o arquivo tem tempo ilimitado
  /// para tentar quebrá-lo offline. Sem servidor para impor atraso ou
  /// bloqueio, a entropia da senha é a única defesa — daí o mínimo alto.
  static String? validarSenha(String senha) {
    if (senha.length < 12) {
      return 'A senha do backup precisa de pelo menos 12 caracteres.';
    }
    final temLetra = RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(senha);
    final temNumero = RegExp(r'\d').hasMatch(senha);
    final temSimbolo = RegExp(r'[^A-Za-zÀ-ÿ0-9]').hasMatch(senha);
    if (!temLetra || !temNumero || !temSimbolo) {
      return 'Combine letras, números e ao menos um símbolo.';
    }
    return null;
  }

  static Uint8List _bytesAleatorios(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }

  // ── Derivação ──────────────────────────────────────────────

  /// PBKDF2 puro Dart é caro de propósito. Roda fora da thread de UI no
  /// nativo; na web `compute` executa inline (não há isolate), então a
  /// chamada bloqueia — aceitável porque backup é operação pontual.
  static Future<Uint8List> _derivarChave(
    String senha,
    Uint8List salt,
    int iteracoes,
  ) {
    return compute(
      _pbkdf2,
      _Pbkdf2Args(senha: senha, salt: salt, iteracoes: iteracoes),
    );
  }

  static Uint8List _pbkdf2(_Pbkdf2Args args) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(args.salt, args.iteracoes, _tamanhoChave));
    return derivator.process(
      Uint8List.fromList(utf8.encode(args.senha)),
    );
  }

  // ── AES-256-GCM ────────────────────────────────────────────

  static Uint8List _gcm({
    required bool cifrar,
    required Uint8List chave,
    required Uint8List nonce,
    required Uint8List dados,
  }) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        cifrar,
        AEADParameters(
          KeyParameter(chave),
          _tamanhoTag,
          nonce,
          Uint8List(0),
        ),
      );
    return cipher.process(dados);
  }

  // ── Cifrar ─────────────────────────────────────────────────

  /// Cifra [conteudo] e devolve o envelope pronto para upload.
  static Future<BackupEnvelope> cifrar({
    required Uint8List conteudo,
    required String senha,
    int iteracoes = _iteracoesPadrao,
  }) async {
    final salt = _bytesAleatorios(_tamanhoSalt);
    final nonce = _bytesAleatorios(_tamanhoNonce);
    final nonceWrap = _bytesAleatorios(_tamanhoNonce);
    final dek = _bytesAleatorios(_tamanhoChave);

    final kek = await _derivarChave(senha, salt, iteracoes);

    final ciphertext =
        _gcm(cifrar: true, chave: dek, nonce: nonce, dados: conteudo);

    // O nonce do wrap viaja colado ao DEK cifrado: assim o envelope da
    // chave é autocontido e o schema guarda um campo só.
    final dekCifrado =
        _gcm(cifrar: true, chave: kek, nonce: nonceWrap, dados: dek);
    final wrapped = Uint8List(nonceWrap.length + dekCifrado.length)
      ..setAll(0, nonceWrap)
      ..setAll(nonceWrap.length, dekCifrado);

    return BackupEnvelope(
      ciphertext: ciphertext,
      saltB64: base64Encode(salt),
      nonceB64: base64Encode(nonce),
      wrappedDekB64: base64Encode(wrapped),
      iteracoes: iteracoes,
      sha256Hex: sha256.convert(ciphertext).toString(),
    );
  }

  // ── Decifrar ───────────────────────────────────────────────

  /// Abre o envelope. Lança [BackupSenhaIncorreta] quando a senha não bate
  /// — o que, em AES-GCM, é indistinguível de arquivo adulterado: a tag de
  /// autenticação falha nos dois casos.
  static Future<Uint8List> decifrar({
    required Uint8List ciphertext,
    required String saltB64,
    required String nonceB64,
    required String wrappedDekB64,
    required String senha,
    int iteracoes = _iteracoesPadrao,
  }) async {
    final salt = base64Decode(saltB64);
    final nonce = base64Decode(nonceB64);
    final wrapped = base64Decode(wrappedDekB64);

    if (wrapped.length <= _tamanhoNonce) {
      throw const BackupArquivoInvalido('Envelope de chave truncado.');
    }

    final kek = await _derivarChave(senha, salt, iteracoes);
    final nonceWrap = Uint8List.sublistView(wrapped, 0, _tamanhoNonce);
    final dekCifrado = Uint8List.sublistView(wrapped, _tamanhoNonce);

    late final Uint8List dek;
    try {
      dek = _gcm(
        cifrar: false,
        chave: kek,
        nonce: nonceWrap,
        dados: dekCifrado,
      );
    } catch (_) {
      throw const BackupSenhaIncorreta();
    }

    try {
      return _gcm(cifrar: false, chave: dek, nonce: nonce, dados: ciphertext);
    } catch (_) {
      throw const BackupArquivoInvalido(
        'O arquivo de backup está corrompido ou foi alterado.',
      );
    }
  }

  /// Confere o hash do que foi baixado contra o registrado no commit.
  ///
  /// A tag do GCM já garante autenticidade; isto detecta antes, e com
  /// mensagem clara, o download truncado — falha bem mais comum.
  static bool integridadeOk(Uint8List ciphertext, String? sha256Esperado) {
    if (sha256Esperado == null || sha256Esperado.isEmpty) return true;
    return sha256.convert(ciphertext).toString() == sha256Esperado;
  }

  // ── Arquivo .fxb ───────────────────────────────────────────

  /// Empacota o envelope num arquivo autodescritivo.
  ///
  /// O cabeçalho repete salt, nonce e DEK envelopado para que um `.fxb`
  /// guardado em pendrive possa ser restaurado mesmo que o registro em
  /// nuvem já tenha expirado.
  static Uint8List empacotar(
    BackupEnvelope envelope,
    Map<String, dynamic> cabecalhoExtra,
  ) {
    final header = <String, dynamic>{
      'v': formatoVersao,
      'alg': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iter': envelope.iteracoes,
      'salt': envelope.saltB64,
      'nonce': envelope.nonceB64,
      'dek': envelope.wrappedDekB64,
      'sha256': envelope.sha256Hex,
      ...cabecalhoExtra,
    };

    final headerBytes = utf8.encode(jsonEncode(header));
    final out = BytesBuilder(copy: false)
      ..add(magic)
      ..add((ByteData(4)..setUint32(0, headerBytes.length)).buffer.asUint8List())
      ..add(headerBytes)
      ..add(envelope.ciphertext);
    return out.toBytes();
  }

  /// Lê um `.fxb` e devolve `(cabeçalho, ciphertext)`.
  static (Map<String, dynamic>, Uint8List) desempacotar(Uint8List arquivo) {
    if (arquivo.length < magic.length + 4) {
      throw const BackupArquivoInvalido('Arquivo pequeno demais para um backup.');
    }
    for (var i = 0; i < magic.length; i++) {
      if (arquivo[i] != magic[i]) {
        throw const BackupArquivoInvalido(
          'Este arquivo não é um backup do ${AppConstants.appName} (.fxb).',
        );
      }
    }

    final headerLen = ByteData.sublistView(arquivo, magic.length, magic.length + 4)
        .getUint32(0);
    final inicio = magic.length + 4;
    if (headerLen <= 0 || inicio + headerLen > arquivo.length) {
      throw const BackupArquivoInvalido('Cabeçalho do backup corrompido.');
    }

    final header = jsonDecode(
      utf8.decode(Uint8List.sublistView(arquivo, inicio, inicio + headerLen)),
    ) as Map<String, dynamic>;

    if ((header['v'] as int? ?? 0) > formatoVersao) {
      throw const BackupArquivoInvalido(
        'Backup gerado por uma versão mais nova do aplicativo. Atualize para restaurar.',
      );
    }

    return (header, Uint8List.sublistView(arquivo, inicio + headerLen));
  }
}

class _Pbkdf2Args {
  final String senha;
  final Uint8List salt;
  final int iteracoes;
  const _Pbkdf2Args({
    required this.senha,
    required this.salt,
    required this.iteracoes,
  });
}

class BackupSenhaIncorreta implements Exception {
  const BackupSenhaIncorreta();
  @override
  String toString() =>
      'Senha do backup incorreta (ou o arquivo foi alterado após a criação).';
}

class BackupArquivoInvalido implements Exception {
  final String mensagem;
  const BackupArquivoInvalido(this.mensagem);
  @override
  String toString() => mensagem;
}
