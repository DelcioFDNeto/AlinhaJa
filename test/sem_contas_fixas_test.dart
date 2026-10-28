import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// O AlinhaJá é white-label: roda em servidores de clientes e pode ser
/// distribuído ou adquirido por outras empresas. Nenhuma instalação pode
/// nascer com conta do fornecedor, senha conhecida ou dados de outro
/// cliente — e o Fluxy, exclusivo da Shineray, não pode vazar para cá.
///
/// Tudo mora em SQL e scripts, que não rodam no `flutter test`: os testes
/// prendem no repositório o invariante de cada correção.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Só o código: descarta linhas inteiras de comentário.
  String code(String texto) => texto
      .split('\n')
      .where((l) => !RegExp(r'^\s*(//|--)').hasMatch(l))
      .join('\n');

  List<File> sql(String dir) => Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  /// Arquivos que vão para o produto: código, banco, scripts e Web.
  /// `docs/`, `CONTEXT.md` e `test/` ficam de fora — registram a história.
  List<File> produto() {
    const raizes = ['lib', 'supabase', 'scripts', 'web'];
    const extensoes = ['.dart', '.sql', '.ts', '.js', '.json', '.html', '.md',
        '.toml', '.yaml', '.sh'];
    final arquivos = <File>[
      for (final r in raizes)
        ...Directory(r).listSync(recursive: true).whereType<File>(),
      ...Directory('.').listSync().whereType<File>(),
    ];
    return arquivos
        .where((f) => extensoes.any(f.path.endsWith))
        .where((f) => !f.path.contains('node_modules'))
        .where((f) => !f.path.endsWith('CONTEXT.md'))
        .toList();
  }

  group('Cadastro de usuários', () {
    test('nenhuma versão de handle_new_user promove por e-mail fixo', () {
      for (final f in [
        ...sql('supabase/migrations'),
        ...sql('supabase/migrations_old'),
      ]) {
        expect(code(read(f.path)), isNot(contains("NEW.email = '")),
            reason: '${f.path}: promoção por e-mail fixo é conta mestre');
      }
    });

    test('a versão vigente é a que removeu a conta mestre', () {
      final definem = sql('supabase/migrations')
          .where((f) => read(f.path).contains('FUNCTION public.handle_new_user'))
          .map((f) => f.path)
          .toList();
      expect(definem.last, endsWith('20261028120000_remove_conta_mestre_handle_new_user.sql'));
      final vigente = code(read(definem.last));
      expect(vigente, contains("v_role user_role_level := 'member'"));
      expect(vigente, contains('v_is_active BOOLEAN := false'));
      expect(vigente, isNot(contains("->> 'role_level'")));
      expect(vigente, isNot(contains("->> 'is_active'")));
    });

    test('o primeiro administrador é definido na instalação, com auditoria', () {
      final script = code(read('supabase/scripts/promover_super_admin.sql'));
      expect(script, contains("role_level = 'super_admin'"));
      expect(script, contains('INSERT INTO public.audit_log'));
      expect(script, contains('ON_ERROR_STOP on'));
      expect(read('docs/RUNBOOK-INSTALACAO-DUBAIRRO.md'),
          contains('promover_super_admin.sql'));
    });
  });

  group('Credenciais', () {
    test('a conta de sistema não tem senha escrita no código', () {
      final seed = code(read(
          'supabase/migrations/20260427150000_seed_system_user.sql'));
      expect(seed, contains('crypt(gen_random_uuid()::text'));
      expect(RegExp(r"crypt\('[^']+'").hasMatch(seed), isFalse);
    });

    test('senha padrão é trocada só se a conta ainda estiver bloqueada', () {
      final m = code(read(
          'supabase/migrations/20261028120100_senha_conta_sistema.sql'));
      expect(m, contains('banned_until > NOW()'));
      expect(m, contains('crypt(gen_random_uuid()::text'));
    });

    test('nenhuma conexão de banco com senha embutida', () {
      final url = RegExp(r'postgres(ql)?://[^:\s/]+:[^@\s<>]+@');
      for (final f in produto()) {
        expect(url.hasMatch(read(f.path)), isFalse,
            reason: '${f.path}: use variável de ambiente');
      }
    });
  });

  test('nenhum dado da Shineray no produto white-label', () {
    // E-mails corporativos, senha provisória padrão e conta master do Fluxy.
    final proibidos = RegExp(r'@shineraybysabel|shineray25|shiadmti',
        caseSensitive: false);
    for (final f in produto()) {
      expect(proibidos.hasMatch(read(f.path)), isFalse, reason: f.path);
    }
  });
}
