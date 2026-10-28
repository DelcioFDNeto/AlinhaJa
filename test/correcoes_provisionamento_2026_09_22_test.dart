import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardas das correções de 2026-09-22, retidas no Fluxy dentro de migrations
/// marcadas como exclusivas daquele tenant: senha provisória obrigatória e
/// contador de não lidas dos canais.
///
/// Tudo mora em SQL, que não roda no `flutter test`: os testes prendem no
/// repositório o invariante de cada correção — inclusive o de uma que foi
/// deliberadamente NÃO replicada.
void main() {
  const migration =
      'supabase/migrations/20260922120000_correcoes_provisionamento_usuarios.sql';

  String read(String path) => File(path).readAsStringSync();

  /// Só o código: descarta linhas inteiras de comentário.
  String code(String path) => read(path)
      .split('\n')
      .where((l) => !RegExp(r'^\s*(//|--)').hasMatch(l))
      .join('\n');

  group('Senha provisória', () {
    test('admin_create_user marca must_change_password no usuário criado', () {
      final sql = code(migration);
      final funcao = sql.indexOf('FUNCTION public.admin_create_user');
      final update = sql.indexOf('UPDATE public.users', funcao);
      final flag = sql.indexOf('must_change_password = true', update);
      final where = sql.indexOf('WHERE id = v_new_user_id', update);
      expect(funcao, greaterThan(0));
      expect(flag, greaterThan(update));
      expect(flag, lessThan(where),
          reason: 'a flag entra no UPDATE do usuário recém-criado');
    });

    test('o ciclo fecha no app: login leva à troca, que limpa a flag', () {
      expect(code('lib/features/auth/ui/login_screen.dart'),
          contains('must_change_password'));
      expect(code('lib/features/auth/ui/force_change_password_screen.dart'),
          contains("rpc('mark_password_changed')"));
    });

    test('o auto-cadastro continua de fora: quem escolhe a senha não a troca',
        () {
      // A trigger de signup não pode carimbar a flag — ver cabeçalho da
      // migration. Só o caminho do admin tem senha provisória.
      expect(code(migration), isNot(contains('FUNCTION public.handle_new_user')));
    });
  });

  group('Não lidas dos canais', () {
    test('a trigger de incremento existe e é AFTER INSERT em channel_messages',
        () {
      final sql = code(migration);
      expect(sql, contains('FUNCTION public.increment_channel_unread_count()'));
      final trigger = sql.indexOf('CREATE TRIGGER trg_increment_channel_unread');
      expect(trigger, greaterThan(0));
      expect(sql.indexOf('AFTER INSERT ON public.channel_messages', trigger),
          greaterThan(trigger));
      // Idempotente: o DROP precede o CREATE.
      expect(sql.indexOf('DROP TRIGGER IF EXISTS trg_increment_channel_unread'),
          lessThan(trigger));
    });

    test('conta para todos menos o remetente, e mensagem de sistema conta para '
        'todos', () {
      final sql = code(migration);
      expect(sql, contains('unread_count = COALESCE(unread_count, 0) + 1'));
      expect(sql, contains('WHERE channel_id = NEW.channel_id'));
      // `!=` descartaria a mensagem inteira quando sender_id é NULL.
      expect(sql, contains('user_id IS DISTINCT FROM NEW.sender_id'));
      expect(sql, isNot(contains('user_id != NEW.sender_id')));
    });

    test('SECURITY DEFINER com search_path fixo e sem exposição a anon', () {
      final sql = code(migration);
      final fn = sql.indexOf('FUNCTION public.increment_channel_unread_count()');
      final corpo = sql.substring(fn, sql.indexOf(r'$$;', fn));
      expect(corpo, contains('SECURITY DEFINER'));
      expect(corpo, contains('SET search_path = public'));
      expect(sql, contains('REVOKE ALL ON FUNCTION '
          'public.increment_channel_unread_count() FROM PUBLIC, anon'));
    });

    test('o app depende da coluna: provider lê e a lista desenha o badge', () {
      expect(code('lib/features/channels/providers/channels_list_provider.dart'),
          contains("select('channel_id, unread_count')"));
      expect(code('lib/features/chats/ui/channels_tab.dart'),
          contains('channel.unreadCount > 0'));
    });
  });

  group('search_path das SECURITY DEFINER', () {
    test('retry_cv_extraction ganha o pin que faltou na 20260918110200', () {
      expect(code(migration),
          contains("ALTER FUNCTION public.retry_cv_extraction(UUID) "
              "SET search_path = ''"));
    });

    test('o corpo dela qualifica tudo, requisito para o pin vazio', () {
      final talentos =
          code('supabase/migrations/20260918110200_rh_rbac_rpcs_talentos.sql');
      final fn = talentos.indexOf('FUNCTION public.retry_cv_extraction');
      final corpo = talentos.substring(fn, talentos.indexOf(r'$$;', fn));
      // Nenhuma referência a tabela ou função do schema sem prefixo.
      for (final alvo in const [
        'public.candidato_curriculo',
        'public.candidato',
        'public.fn_rh_pode',
        'public.fn_current_org()',
        'public.get_edge_base_url()',
        'public.get_webhook_secret()',
        'net.http_post',
      ]) {
        expect(corpo, contains(alvo));
      }
      expect(corpo, isNot(contains('FROM candidato')));
      expect(corpo, isNot(contains('UPDATE candidato')));
    });
  });

  group('Escalada de privilégio que não foi replicada', () {
    test('handle_new_user ignora role_level e is_active do metadata', () {
      // O metadata vem do cliente no signUp e o cadastro é aberto: honrar
      // esses campos deixaria qualquer um nascer super_admin ativo.
      final trigger =
          code('supabase/migrations/20260813153000_reassert_handle_new_user.sql');
      expect(trigger, isNot(contains("raw_user_meta_data ->> 'role_level'")));
      expect(trigger, isNot(contains("raw_user_meta_data ->> 'is_active'")));
      expect(code(migration), isNot(contains("->> 'role_level'")));
    });

    test('o signup do app não envia esses campos', () {
      final tela = code('lib/features/auth/ui/signup_screen.dart');
      final signUp = tela.indexOf('auth.signUp(');
      final fecha = tela.indexOf(');', signUp);
      final payload = tela.substring(signUp, fecha);
      expect(payload, isNot(contains('role_level')));
      expect(payload, isNot(contains('is_active')));
    });
  });
}
