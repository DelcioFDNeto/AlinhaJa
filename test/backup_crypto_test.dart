import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:alinha_ja/core/services/backup/backup_crypto.dart';

void main() {
  const senha = 'Senha-De-Backup#2026';

  // 210 000 iterações levam segundos em Dart puro; os testes usam um valor
  // baixo para não estourar o tempo. O que se verifica aqui é a corretude do
  // envelope, não o custo da derivação.
  const iter = 1000;

  Uint8List conteudo() => Uint8List.fromList(
        utf8.encode(jsonEncode({
          'mensagens': [
            {'id': 'a1', 'content': 'Confidencial: proposta revisada'},
            {'id': 'a2', 'content': 'Reunião às 14h'},
          ],
        })),
      );

  group('validação de senha', () {
    test('recusa senha curta', () {
      expect(BackupCrypto.validarSenha('Ab#1'), isNotNull);
    });

    test('recusa senha sem símbolo', () {
      expect(BackupCrypto.validarSenha('senhalonga123'), isNotNull);
    });

    test('aceita senha com letra, número e símbolo', () {
      expect(BackupCrypto.validarSenha(senha), isNull);
    });
  });

  group('ciclo cifrar/decifrar', () {
    test('devolve exatamente o conteúdo original', () async {
      final original = conteudo();

      final env = await BackupCrypto.cifrar(
        conteudo: original,
        senha: senha,
        iteracoes: iter,
      );

      final aberto = await BackupCrypto.decifrar(
        ciphertext: env.ciphertext,
        saltB64: env.saltB64,
        nonceB64: env.nonceB64,
        wrappedDekB64: env.wrappedDekB64,
        senha: senha,
        iteracoes: iter,
      );

      expect(aberto, equals(original));
    });

    test('o ciphertext não contém o texto em claro', () async {
      final env = await BackupCrypto.cifrar(
        conteudo: conteudo(),
        senha: senha,
        iteracoes: iter,
      );

      expect(
        latin1.decode(env.ciphertext, allowInvalid: true),
        isNot(contains('Confidencial')),
      );
    });

    test('dois backups do mesmo conteúdo geram cifras diferentes', () async {
      // DEK, salt e nonce novos a cada snapshot: sem isso, comparar dois
      // arquivos revelaria que o conteúdo não mudou.
      final a = await BackupCrypto.cifrar(
          conteudo: conteudo(), senha: senha, iteracoes: iter);
      final b = await BackupCrypto.cifrar(
          conteudo: conteudo(), senha: senha, iteracoes: iter);

      expect(a.ciphertext, isNot(equals(b.ciphertext)));
      expect(a.saltB64, isNot(equals(b.saltB64)));
      expect(a.wrappedDekB64, isNot(equals(b.wrappedDekB64)));
    });

    test('senha errada não abre o envelope', () async {
      final env = await BackupCrypto.cifrar(
          conteudo: conteudo(), senha: senha, iteracoes: iter);

      expect(
        () => BackupCrypto.decifrar(
          ciphertext: env.ciphertext,
          saltB64: env.saltB64,
          nonceB64: env.nonceB64,
          wrappedDekB64: env.wrappedDekB64,
          senha: 'Outra-Senha#2026',
          iteracoes: iter,
        ),
        throwsA(isA<BackupSenhaIncorreta>()),
      );
    });

    test('ciphertext adulterado é rejeitado pela tag do GCM', () async {
      final env = await BackupCrypto.cifrar(
          conteudo: conteudo(), senha: senha, iteracoes: iter);

      final adulterado = Uint8List.fromList(env.ciphertext);
      adulterado[0] = adulterado[0] ^ 0xFF;

      expect(
        () => BackupCrypto.decifrar(
          ciphertext: adulterado,
          saltB64: env.saltB64,
          nonceB64: env.nonceB64,
          wrappedDekB64: env.wrappedDekB64,
          senha: senha,
          iteracoes: iter,
        ),
        throwsA(isA<BackupArquivoInvalido>()),
      );
    });
  });

  group('integridade', () {
    test('confere o sha256 registrado no commit', () async {
      final env = await BackupCrypto.cifrar(
          conteudo: conteudo(), senha: senha, iteracoes: iter);

      expect(BackupCrypto.integridadeOk(env.ciphertext, env.sha256Hex), isTrue);

      final truncado =
          Uint8List.sublistView(env.ciphertext, 0, env.ciphertext.length - 4);
      expect(BackupCrypto.integridadeOk(truncado, env.sha256Hex), isFalse);
    });
  });

  group('arquivo .fxb', () {
    test('empacota e desempacota preservando o envelope', () async {
      final env = await BackupCrypto.cifrar(
          conteudo: conteudo(), senha: senha, iteracoes: iter);

      final arquivo = BackupCrypto.empacotar(env, {'escopo': 'conta'});
      final (header, ciphertext) = BackupCrypto.desempacotar(arquivo);

      expect(header['alg'], 'AES-256-GCM');
      expect(header['escopo'], 'conta');
      expect(header['salt'], env.saltB64);
      expect(header['dek'], env.wrappedDekB64);
      expect(ciphertext, equals(env.ciphertext));
    });

    test('arquivo restaura sem depender do registro no banco', () async {
      final original = conteudo();
      final env = await BackupCrypto.cifrar(
          conteudo: original, senha: senha, iteracoes: iter);
      final arquivo = BackupCrypto.empacotar(env, {'escopo': 'conta'});

      final (header, ciphertext) = BackupCrypto.desempacotar(arquivo);
      final aberto = await BackupCrypto.decifrar(
        ciphertext: ciphertext,
        saltB64: header['salt'] as String,
        nonceB64: header['nonce'] as String,
        wrappedDekB64: header['dek'] as String,
        senha: senha,
        iteracoes: header['iter'] as int,
      );

      expect(aberto, equals(original));
    });

    test('recusa arquivo que não é .fxb', () {
      final lixo = Uint8List.fromList(utf8.encode('PK zip qualquer'));
      expect(
        () => BackupCrypto.desempacotar(lixo),
        throwsA(isA<BackupArquivoInvalido>()),
      );
    });

    test('recusa formato de versão futura', () async {
      final env = await BackupCrypto.cifrar(
          conteudo: conteudo(), senha: senha, iteracoes: iter);
      final arquivo = BackupCrypto.empacotar(env, {'v': 99});

      expect(
        () => BackupCrypto.desempacotar(arquivo),
        throwsA(isA<BackupArquivoInvalido>()),
      );
    });
  });
}
