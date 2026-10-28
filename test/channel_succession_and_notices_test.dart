import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/features/channels/ui/widgets/channel_successor_picker.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';

UserModel user(String id, String name) =>
    UserModel.fromJson({'id': id, 'full_name': name});

void main() {
  String read(String path) => File(path).readAsStringSync();
  String code(String path) => read(path)
      .split('\n')
      .where((l) => !RegExp(r'^\s*(//|--)').hasMatch(l))
      .join('\n');

  group('needsAdminSuccessor (mesma regra do banco)', () {
    test('único admin com outros membros precisa de sucessor', () {
      expect(
          needsAdminSuccessor('me', {'me': 'admin', 'a': 'viewer', 'b': 'editor'}),
          isTrue);
    });
    test('há outro admin: sai direto', () {
      expect(needsAdminSuccessor('me', {'me': 'admin', 'a': 'admin'}), isFalse);
    });
    test('último membro do canal: sai direto', () {
      expect(needsAdminSuccessor('me', {'me': 'admin'}), isFalse);
    });
    test('quem não é admin nunca precisa', () {
      expect(needsAdminSuccessor('me', {'me': 'editor', 'a': 'viewer'}), isFalse);
      expect(needsAdminSuccessor('me', {}), isFalse);
    });
  });

  test('candidatos: sem quem sai, editores primeiro, depois A-Z', () {
    final members = [
      user('me', 'Eu Mesmo'),
      user('z', 'Zeca'),
      user('b', 'bruna'),
      user('e', 'Téo Editor'),
      user('a', 'Ana'),
    ];
    final roles = {
      'me': 'admin',
      'z': 'viewer',
      'b': 'viewer',
      'e': 'editor',
      'a': 'viewer',
    };
    expect(successorCandidates('me', members, roles).map((u) => u.id),
        ['e', 'a', 'b', 'z']);
  });

  group('Migration 20260916150000', () {
    final sql = code(
        'supabase/migrations/20260916150000_channel_admin_succession_and_rejection_notices.sql');

    test('único admin não apaga a própria participação sem sucessor', () {
      expect(sql, contains('AS RESTRICTIVE'));
      expect(sql,
          contains('USING (NOT public.channel_member_is_sole_admin(channel_id, user_id))'));
    });

    test('leave_channel promove o sucessor antes de remover quem sai', () {
      final start = sql.indexOf('FUNCTION public.leave_channel(');
      final body = sql.substring(start, sql.indexOf(r'$$;', start));
      expect(body, contains("'SUCCESSOR_REQUIRED"));
      final promote = body.indexOf("SET role = 'admin'");
      final remove = body.indexOf('DELETE FROM public.channel_members');
      expect(promote, isNonNegative);
      expect(remove, greaterThan(promote));
      expect(body, contains("'channel_admin_transferred'"));
    });

    test('recusa de pedido avisa só quando houve recusa de verdade', () {
      final start = sql.indexOf('FUNCTION public.fn_notify_channel_join_rejected(');
      final body = sql.substring(start, sql.indexOf(r'$$;', start));
      expect(body, contains("OLD.status IS DISTINCT FROM 'pending'"));
      expect(body, contains('auth.uid() = OLD.user_id'),
          reason: 'O próprio usuário limpando o pedido não é recusa.');
      expect(body, contains('IF NOT FOUND OR NOT EXISTS'),
          reason: 'Exclusão em cascata do canal ou da conta não é recusa.');
      expect(sql, contains('AFTER DELETE ON public.channel_join_requests'));
    });

    test('cadastro recusado avisa por e-mail antes da exclusão', () {
      final start = sql.indexOf('FUNCTION public.admin_reject_user(');
      final body = sql.substring(start, sql.indexOf(r'$$;', start));
      final notify = body.indexOf("'signup_rejected'");
      final delete = body.indexOf('DELETE FROM auth.users');
      expect(notify, isNonNegative);
      expect(delete, greaterThan(notify));
      expect(body, contains('last_sign_in_at IS NULL'));
      expect(body, contains('fn_assert_same_org(p_target_user_id)'),
          reason: 'A guarda de organização não pode se perder na recriação.');
    });

    test('falha no aviso não desfaz a operação principal', () {
      final start = sql.indexOf('FUNCTION public.fn_notify_account_event(');
      final body = sql.substring(start, sql.indexOf(r'$$;', start));
      expect(body, contains('EXCEPTION WHEN OTHERS THEN'));
      expect(body, contains('/functions/v1/send-account-notification'));
    });
  });

  test('trigger de automações de RH chama a rota /functions/v1', () {
    final sql =
        code('supabase/migrations/20260916160000_fix_rh_automations_trigger_url.sql');
    expect(sql, contains("'/functions/v1/rh-automations'"));
  });

  test('send-account-notification: fail-closed e sem JWT no deploy', () {
    final ts = code('supabase/functions/send-account-notification/index.ts');
    expect(ts, contains("return json({ error: 'Server misconfigured' }, 503);"));
    expect(ts, contains('isStaleTokenError'));
    final toml = read('supabase/config.toml');
    final start = toml.indexOf('[functions.send-account-notification]');
    expect(start, isNonNegative);
    expect(toml.substring(start, start + 80), contains('verify_jwt = false'));
  });

  test('app sai do canal pela RPC e trata SUCCESSOR_REQUIRED', () {
    final screen = code('lib/features/channels/ui/channel_info_screen.dart');
    expect(screen, contains("rpc('leave_channel'"));
    expect(screen, contains("contains('SUCCESSOR_REQUIRED')"));
    expect(screen, isNot(contains(".from('channel_members')\n            .delete()")));
  });

  test('app exibe e abre avisos de conta no Android e em background', () {
    final push = code('lib/core/services/push_notification_service.dart');
    expect("dataType == 'account'".allMatches(push).length, 1);
    expect(push, contains("data['type'] == 'account'"));
    expect(push, contains("payloadStr.startsWith('route:')"));
    expect(push, contains("if (!route.startsWith('/') || route.startsWith('//')) return;"),
        reason: 'Rota do payload não pode virar URL externa.');
  });

  test('web: aviso de conta abre a rota interna e recusa URL externa',
      () async {
    final which = await Process.run(Platform.isWindows ? 'where' : 'which', ['node']);
    if (which.exitCode != 0) {
      markTestSkipped('node indisponível');
      return;
    }
    const script = '''
const f = require('./web/notification-format.js');
const a = f.build({type:'account', title:'Solicitação não aprovada', body:'x', route:'/channels/discover'}, 0);
const evil = f.build({type:'account', title:'t', route:'//evil.example'}, 0);
console.log(JSON.stringify({
  title: a.title, route: a.options.data.route,
  path: f.pathFor('', 'account', a.options.data.route),
  evilRoute: evil.options.data.route, evilPath: f.pathFor('', 'account', '//evil.example'),
  external: f.pathFor('', 'account', 'https://evil.example'),
}));
''';
    final node = (which.stdout as String).split(RegExp(r'\r?\n')).first.trim();
    final r = await Process.run(node, ['-e', script],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    expect(jsonDecode(r.stdout as String), {
      'title': 'Solicitação não aprovada',
      'route': '/channels/discover',
      'path': '/#/channels/discover',
      'evilRoute': null,
      'evilPath': '/',
      'external': '/',
    });
  });
}
