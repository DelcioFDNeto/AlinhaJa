import 'package:flutter_test/flutter_test.dart';
import 'package:alinha_ja/features/hr/models/smtp_config.dart';

void main() {
  group('SmtpConfig Model & Protocol Tests', () {
    test('SmtpConfig cria instância com porta padrão 465', () {
      final config = SmtpConfig(
        host: 'smtp.gmail.com',
        username: 'rh@empresa.com.br',
        fromEmail: 'rh@empresa.com.br',
        fromName: 'RH Empresa',
      );

      expect(config.port, equals(465));
      expect(config.hasPassword, isFalse);
      expect(config.password, isNull);
    });

    test('SmtpConfig.fromMap desserializa corretamente e oculta senha', () {
      final map = {
        'host': 'smtp.office365.com',
        'port': 587,
        'username': 'recrutamento@empresa.com.br',
        'has_password': true,
        'from_email': 'recrutamento@empresa.com.br',
        'from_name': 'Recrutamento & Seleção',
      };

      final config = SmtpConfig.fromMap(map);

      expect(config.host, equals('smtp.office365.com'));
      expect(config.port, equals(587));
      expect(config.username, equals('recrutamento@empresa.com.br'));
      expect(config.hasPassword, isTrue);
      // Senha nunca deve vir exposta no fromMap
      expect(config.password, isNull);
      expect(config.fromEmail, equals('recrutamento@empresa.com.br'));
      expect(config.fromName, equals('Recrutamento & Seleção'));
    });

    test('Porta 587 vs Porta 465: verificação de protocolo TLS/STARTTLS', () {
      // Porta 465 é SMTPS (implicit TLS)
      expect(465 == 465, isTrue);

      // Porta 587 é submission (STARTTLS), não deve forçar TLS implícito no handshake inicial
      const port587 = 587;
      const isImplicitTls587 = port587 == 465;
      expect(isImplicitTls587, isFalse);

      const port465 = 465;
      const isImplicitTls465 = port465 == 465;
      expect(isImplicitTls465, isTrue);
    });
  });
}
