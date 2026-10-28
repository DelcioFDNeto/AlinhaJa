import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardas dos achados da auditoria de RH + RBAC de 2026-09-18.
///
/// As correções moram em SQL, que não roda no `flutter test`: os testes
/// prendem no repositório o invariante de cada uma, para que um sync entre os
/// forks ou uma reescrita não reabra a falha em silêncio.
void main() {
  const migration = 'supabase/migrations/20260918100000_rh_rbac_auditoria.sql';

  /// Só o código: descarta linhas inteiras de comentário (`//` e `--`).
  String code(String path) => File(path)
      .readAsStringSync()
      .split('\n')
      .where((l) => !RegExp(r'^\s*(//|--)').hasMatch(l))
      .join('\n');

  /// Corpo de `CREATE [OR REPLACE] FUNCTION public.<name>` até o `$$;`.
  String functionBody(String sql, String name) {
    final start = sql.indexOf(RegExp('FUNCTION public\\.$name\\s*\\('));
    expect(start, isNot(-1), reason: '$name não encontrada');
    return sql.substring(start, sql.indexOf(r'$$;', start));
  }

  late final String sql = code(migration);

  test('admin comum não age sobre super_admin (guarda de todas as RPCs)', () {
    final body = functionBody(sql, 'fn_assert_same_org');
    expect(body, contains("t.role_level = 'super_admin'"));
    expect(body, contains("c.role_level = 'super_admin'"));
    // A guarda de organização continua lá.
    expect(body, contains('t.organization_id = public.fn_current_org()'));
  });

  test('batida de ponto do colaborador usa a hora do servidor', () {
    final body = functionBody(sql, 'fn_tg_rh_ponto_hora_servidor');
    expect(body, contains('NEW.data_hora := now()'));
    expect(body, contains('fn_is_own_funcionario(NEW.funcionario_id)'));
    expect(sql, contains('BEFORE INSERT ON public.rh_ponto_registro'));
  });

  test('colaborador só registra a visualização do próprio holerite', () {
    final body = functionBody(sql, 'fn_tg_rh_holerite_somente_visualizacao');
    expect(body, contains('NEW IS DISTINCT FROM v_esperado'));
    expect(body, contains('COALESCE(OLD.data_visualizacao, now())'));
    expect(sql, contains('BEFORE UPDATE ON public.rh_holerite'));
  });

  test('exclusão de candidato exige RH e a própria organização', () {
    final body = functionBody(sql, 'rh_soft_delete_candidato');
    expect(body, contains('NOT public.fn_is_rh()'));
    expect(body, contains('organization_id = public.fn_current_org()'));
    expect(sql, isNot(contains(
        'GRANT EXECUTE ON FUNCTION public.rh_soft_delete_candidato(uuid) TO anon')));
  });

  test('permissões do perfil trocam numa RPC só, e o app a usa', () {
    final body = functionBody(sql, 'rbac_set_role_permissions');
    expect(body, contains('public.fn_is_admin()'));
    expect(body, contains('organization_id = public.fn_current_org()'));

    final repo = code('lib/core/rbac/services/rbac_repository.dart');
    expect(repo, contains("rpc('rbac_set_role_permissions'"));
    // O caminho antigo (apaga e insere em duas requisições) não volta.
    expect(repo, isNot(contains(".from('rbac_role_permissions').delete()")));
  });

  test('escrita em rbac_user_roles fica na própria organização', () {
    final start = sql.indexOf(
        'CREATE POLICY "Gestão de user_roles por admin"');
    expect(start, isNot(-1));
    final policy = sql.substring(start, sql.indexOf(';', start));
    expect(policy, contains('WITH CHECK'));
    expect(
        'organization_id = public.fn_current_org()'.allMatches(policy).length,
        3);
  });

  test('toda RPC chamada pelo app existe em alguma migration', () {
    // Fora do escopo desta auditoria: registrada para correção à parte.
    const pendentes = {'update_group_settings'};

    final migrations = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .map((f) => f.readAsStringSync().toLowerCase())
        .join('\n');

    final chamadas = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final m in RegExp(r"rpc\(\s*'([a-z0-9_]+)'")
          .allMatches(f.readAsStringSync())) {
        chamadas.add(m.group(1)!);
      }
    }

    final faltando = chamadas
        .where((fn) =>
            !pendentes.contains(fn) &&
            !RegExp('function\\s+(public\\.)?$fn\\s*\\(')
                .hasMatch(migrations))
        .toList()
      ..sort();
    expect(faltando, isEmpty,
        reason: 'RPCs chamadas pelo app sem definição em migration');
  });
}
