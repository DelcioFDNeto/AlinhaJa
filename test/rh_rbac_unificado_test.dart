import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// O RH passou a obedecer o RBAC (migrations 20260918110000..110600).
///
/// Antes o banco liberava os dados de RH por users.role_level/hr_role
/// (fn_is_rh) enquanto o app escolhia os menus pelo RBAC: perfil "RH" sem
/// ser admin não via nada, e todo admin via salários. Estes testes
/// reconstroem o ESTADO FINAL das migrations (última definição de cada
/// política e função) e exigem que nenhuma política ou RPC volte a depender
/// do papel legado — um sync entre os forks reabriria a falha em silêncio.
void main() {
  final files = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  /// Sem linhas inteiras de comentário: explicações citam o código antigo.
  String code(String sql) => sql
      .split('\n')
      .where((l) => !RegExp(r'^\s*--').hasMatch(l))
      .join('\n');

  // ── Estado final: funções ──────────────────────────────────
  final functions = <String, String>{};
  final fnStart = RegExp(r'FUNCTION\s+public\.(\w+)\s*\(', caseSensitive: false);
  // ── Estado final: políticas (tabela|nome → corpo) ─────────
  final policies = <String, String>{};
  final create = RegExp(
      r'CREATE\s+POLICY\s+"([^"]+)"\s+ON\s+(?:public\.|storage\.)?(\w+)(.*?);',
      caseSensitive: false,
      dotAll: true);
  final drop = RegExp(
      r'DROP\s+POLICY\s+(?:IF\s+EXISTS\s+)?"([^"]+)"\s+ON\s+(?:public\.|storage\.)?(\w+)',
      caseSensitive: false);

  for (final f in files) {
    final sql = code(f.readAsStringSync());
    for (final m in fnStart.allMatches(sql)) {
      final prefix = sql.substring(0, m.start).trimRight().toUpperCase();
      if (!prefix.endsWith('CREATE OR REPLACE') && !prefix.endsWith('CREATE')) {
        continue;
      }
      // Só o corpo (depois do `$$` de abertura): a assinatura de
      // fn_is_rh() casaria com a própria busca pelo papel legado.
      final open = sql.indexOf(r'$$', m.end);
      final end = open < 0 ? -1 : sql.indexOf(r'$$;', open + 2);
      if (end < 0) continue;
      functions[m.group(1)!.toLowerCase()] = sql.substring(open + 2, end);
    }
    // Em ordem de aparição: DROP e CREATE intercalados no mesmo arquivo.
    final events = [
      for (final m in drop.allMatches(sql)) (m.start, 'drop', m),
      for (final m in create.allMatches(sql)) (m.start, 'create', m),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, kind, m) in events) {
      final key = '${m.group(2)!.toLowerCase()}|${m.group(1)}';
      if (kind == 'drop') {
        policies.remove(key);
      } else {
        policies[key] = m.group(3)!;
      }
    }
  }

  final legado = RegExp(r'fn_is_rh(_admin)?\(\)');

  test('nenhuma política depende do papel legado de RH', () {
    final legadas = policies.entries
        .where((e) => legado.hasMatch(e.value))
        .map((e) => e.key)
        .toList()
      ..sort();
    expect(legadas, isEmpty);
  });

  test('leitura de perfis atribuídos fica na própria organização', () {
    final body = policies['rbac_user_roles|Leitura de user_roles']!;
    expect(body, contains('organization_id = public.fn_current_org()'));
    expect(body, contains("'rh_funcionarios', 'manage'"));
  });

  test('nenhuma função depende do papel legado de RH', () {
    final legadas = functions.entries
        .where((e) => legado.hasMatch(e.value))
        .map((e) => e.key)
        .toList()
      ..sort();
    expect(legadas, isEmpty);
  });

  test('fn_rh_pode: super_admin passa, manage implica view, perfil da org', () {
    final body = functions['fn_rh_pode']!;
    expect(body, contains("u.role_level = 'super_admin'"));
    expect(body, contains("(p_action = 'view' AND p.action = 'manage')"));
    expect(body, contains('r.organization_id = public.fn_current_org()'));
    // Admin comum NÃO passa direto (era o furo: todo admin via salários).
    expect(body, isNot(contains("'admin'")));
  });

  test('fn_is_rh / fn_is_rh_admin viraram RBAC', () {
    expect(functions['fn_is_rh'], contains("fn_rh_pode_algum('view')"));
    expect(functions['fn_is_rh_admin'], contains("fn_rh_pode_algum('manage')"));
    expect(functions['fn_is_rh'], isNot(contains('hr_role')));
  });

  test('dados sensíveis exigem gerir funcionários (Gestor só tem view)', () {
    for (final fn in [
      'rh_get_dados_sensiveis',
      'rh_get_historico_cargo_salario',
      'rh_list_dependentes',
      'rh_upsert_dados_sensiveis',
    ]) {
      expect(functions[fn], contains("fn_rh_pode('rh_funcionarios', 'manage')"),
          reason: fn);
    }
    for (final t in ['rh_dependente|RH acessa dependentes (leitura)',
        'rh_historico_cargo_salario|RH lê e insere histórico (leitura)']) {
      expect(policies[t], contains("'rh_funcionarios', 'manage'"), reason: t);
    }
  });

  test('cada RPC de RH confere o módulo certo', () {
    const esperado = {
      'rh_decidir_ausencia': "'rh_ausencias', 'manage'",
      'rh_rejeitar_documento': "'rh_documentos', 'manage'",
      'rh_360_convidar': "'rh_desempenho', 'manage'",
      'rh_add_adesao_beneficio': "'rh_beneficios', 'manage'",
      'rh_save_smtp_config': "'rh_automacoes', 'manage'",
      'rh_soft_delete_candidato': "'rh_banco_talentos', 'manage'",
      'fn_tg_rh_holerite_somente_visualizacao': "'rh_holerites', 'manage'",
      'fn_tg_rh_ponto_hora_servidor': "'rh_ponto', 'manage'",
    };
    esperado.forEach((fn, trecho) {
      expect(functions[fn], contains(trecho), reason: fn);
    });
    // Converter candidato cria funcionário: exige os dois módulos.
    expect(functions['rh_converter_candidato'],
        contains("fn_rh_pode('rh_banco_talentos', 'manage') AND "
            "public.fn_rh_pode('rh_funcionarios', 'manage')"));
  });

  test('toda política FOR ALL de RH ganhou o par de leitura com view', () {
    expect(policies['rh_holerite|RH acessa holerites'],
        contains("'rh_holerites', 'manage'"));
    expect(policies['rh_holerite|RH acessa holerites (leitura)'],
        contains("'rh_holerites', 'view'"));
    // Nas políticas, o helper fica em (SELECT ...): avaliado uma vez.
    expect(policies['rh_ponto_registro|RH acessa ponto'],
        contains("(SELECT public.fn_rh_pode('rh_ponto', 'manage'))"));
  });

  test('Storage: holerites isolados no módulo de holerites', () {
    final leitura = policies['objects|RH lê storage RH']!;
    expect(leitura, contains("name LIKE 'holerites/%'"));
    expect(leitura, contains("fn_rh_pode('rh_holerites', 'view')"));
    expect(policies.containsKey('objects|RH acessa storage RH'), isFalse,
        reason: 'a política antiga (fn_is_rh em tudo) foi removida');
  });

  test('Edge Functions de RH usam o RBAC, não role_level', () {
    final auto = File('supabase/functions/rh-automations/index.ts')
        .readAsStringSync();
    expect(auto, contains("p_module: 'rh_automacoes'"));
    expect(auto, isNot(contains("role_level === 'gestor'")));

    final questoes = File('supabase/functions/rh-gerar-questoes/index.ts')
        .readAsStringSync();
    expect(questoes, contains("p_module: 'rh_banco_talentos'"));
    expect(code(questoes), isNot(contains("rpc('fn_is_rh_admin')")));
  });

  test('app: RH sai do RBAC, sem o papel legado', () {
    final lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    expect(lib, isNot(contains('canAccessHr(')));
    expect(lib, isNot(contains('isHrAdmin(')));

    final repo = File('lib/core/rbac/services/rbac_repository.dart')
        .readAsStringSync();
    // Admin não recebe mais "todas as permissões" (incluía o RH inteiro).
    expect(repo, isNot(contains("level == 'super_admin' || level == 'admin'")));
    expect(repo, contains('adminEffectivePermissions('));
  });
}
