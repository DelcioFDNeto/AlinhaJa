import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardas da migration 20260916180000 (idêntica nos dois forks).
void main() {
  final sql = File(
          'supabase/migrations/20260916180000_channel_member_role_guards.sql')
      .readAsStringSync()
      .split('\n')
      .where((l) => !RegExp(r'^\s*--').hasMatch(l))
      .join('\n');

  String body(String fn) {
    final start = sql.indexOf('FUNCTION public.$fn(');
    expect(start, isNonNegative, reason: fn);
    return sql.substring(start, sql.indexOf(r'$$;', start));
  }

  test('gestão de workspace fica restrita à empresa do canal', () {
    final b = body('can_manage_workspace');
    final orgCheck = b.indexOf('v_channel_org IS DISTINCT FROM public.fn_current_org()');
    expect(orgCheck, isNonNegative);
    expect(b, contains('NOT public.fn_is_platform_owner()'));
    // A checagem de empresa vem antes de qualquer caminho que devolva TRUE.
    expect(orgCheck, lessThan(b.indexOf('v_is_owner :=')));
  });

  test('rebaixar um admin exige nível admin e não deixa o canal sem admin', () {
    final b = body('add_channel_member');
    expect(b, contains("IF v_role = 'admin' OR v_current = 'admin' THEN"));
    expect(b, contains('channel_member_is_sole_admin(p_channel_id, p_user_id)'));
  });

  test('remover o único admin é recusado', () {
    final b = body('remove_channel_member');
    final guard = b.indexOf('channel_member_is_sole_admin(p_channel_id, p_user_id)');
    expect(guard, isNonNegative);
    expect(guard, lessThan(b.indexOf('DELETE FROM public.channel_members')));
  });

  test('sem BOM (o psql aborta na primeira linha)', () {
    final bytes = File(
            'supabase/migrations/20260916180000_channel_member_role_guards.sql')
        .readAsBytesSync();
    expect(bytes.take(3).toList(), isNot(equals([0xEF, 0xBB, 0xBF])));
  });
}
