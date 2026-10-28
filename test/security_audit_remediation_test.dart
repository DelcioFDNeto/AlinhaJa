import 'package:flutter_test/flutter_test.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/services/backup/backup_crypto.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';

void main() {
  group('Security Audit & LGPD Compliance Tests', () {
    test('MiroTalk API key não deve conter o segredo padrão inseguro', () {
      expect(AppConstants.mirotalkApiKey, isNot(equals('mirotalksfu_default_secret')));
    });

    test('Validação de senha forte para backup (entropia mínima contra ataque offline)', () {
      // Senha curta (< 12)
      expect(
        BackupCrypto.validarSenha('Abc!12345'),
        contains('12 caracteres'),
      );

      // Sem símbolo
      expect(
        BackupCrypto.validarSenha('Abcdefgh12345'),
        contains('Combine letras, números e ao menos um símbolo'),
      );

      // Sem número
      expect(
        BackupCrypto.validarSenha('Abcdefghijkl!'),
        contains('Combine letras, números e ao menos um símbolo'),
      );

      // Sem letra
      expect(
        BackupCrypto.validarSenha('123456789012!'),
        contains('Combine letras, números e ao menos um símbolo'),
      );

      // Válida
      expect(
        BackupCrypto.validarSenha('MinhaSenhaForte@2026'),
        isNull,
      );
    });

    test('LGPD: Mascaramento de CPF em UserModel protege privacidade do titular', () {
      const user = UserModel(
        id: 'user-test-1',
        email: 'colaborador@empresa.com.br',
        fullName: 'Colaborador Teste',
        cpf: '12345678901',
      );

      // Formato esperado: ***.***.789-01
      expect(user.cpfMasked, equals('***.***.789-01'));
      expect(user.cpfMasked, isNot(contains('123456')));
    });

    test('LGPD: Mascaramento lida com CPF já formatado ou inválido', () {
      const userFormatted = UserModel(
        id: 'user-test-2',
        email: 'colaborador2@empresa.com.br',
        fullName: 'Colaborador 2',
        cpf: '123.456.789-01',
      );
      expect(userFormatted.cpfMasked, equals('***.***.789-01'));

      const userNull = UserModel(
        id: 'user-test-3',
        email: 'colaborador3@empresa.com.br',
        fullName: 'Colaborador 3',
        cpf: null,
      );
      expect(userNull.cpfMasked, equals(''));
    });
  });
}
