import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardas dos achados da auditoria de 2026-09-16.
///
/// Como no audit de 03/09, os defeitos moram em Edge Functions e SQL, que
/// não rodam no `flutter test`. Os testes prendem no repositório o
/// invariante de cada correção para que um sync entre os forks ou uma
/// reescrita não reabra a falha em silêncio.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Só o código: descarta linhas inteiras de comentário (`//` e `--`).
  /// Os comentários das correções citam o trecho vulnerável antigo, e os
  /// testes negativos não podem casar com a explicação.
  String code(String path) => read(path)
      .split('\n')
      .where((l) => !RegExp(r'^\s*(//|--)').hasMatch(l))
      .join('\n');

  group('Portal de candidatos e e-mails escapam dados de terceiros', () {
    final html = read('supabase/functions/_shared/html.ts');

    test('o helper escapa os cinco caracteres de HTML', () {
      for (final entity in ['&amp;', '&lt;', '&gt;', '&quot;', '&#39;']) {
        expect(html, contains(entity));
      }
    });

    test('rh-candidatura escapa nome, empresa e link nos templates HTML', () {
      final ts = read('supabase/functions/rh-candidatura/index.ts');
      expect(ts, contains("from '../_shared/html.ts'"));
      expect(ts, contains('const nome = escapeHtml(rawNome);'));
      expect(ts, contains('const empresa = escapeHtml(rawEmpresa);'));
      // As duas funções de template recebem o valor cru e escapam por dentro.
      expect('escapeHtml(rawLink)'.allMatches(ts).length, 2);
    });

    test('rh-automations escapa variáveis no corpo e limpa o assunto', () {
      final ts = read('supabase/functions/rh-automations/index.ts');
      expect(ts, contains('render(tpl.body_html, vars, escapeHtml)'));
      expect(ts, contains('stripHeaderBreaks(render(tpl.assunto'));
    });

    test('send-2fa-code escapa o nome e usa CSPRNG no código', () {
      final ts = read('supabase/functions/send-2fa-code/index.ts');
      expect(ts, contains('escapeHtml(userName)'));
      expect(ts, contains('crypto.getRandomValues'));
      expect(code('supabase/functions/send-2fa-code/index.ts'),
          isNot(contains('Math.random')));
    });
  });

  group('rh-automations: JWT de gestor só libera o teste de SMTP', () {
    final ts = read('supabase/functions/rh-automations/index.ts');

    test('o disparo de automações recusa o caminho por JWT', () {
      final guard = ts.indexOf('if (authViaJwt) {');
      final automacao = ts.indexOf("payload.table !== 'candidato_historico'");
      expect(guard, greaterThan(0));
      expect(guard, lessThan(automacao),
          reason: 'A recusa precisa vir antes de ler payload.organization_id '
              'do fluxo de automação.');
    });
  });

  group('send-call-notification: toque só em nome próprio', () {
    final ts = read('supabase/functions/send-call-notification/index.ts');

    test('no caminho por JWT exige caller_id do próprio usuário', () {
      expect(ts, contains('callerId !== jwtUserId'));
    });

    test('e exige ser membro da conversa antes de buscar destinatários', () {
      final guard = ts.indexOf(".eq('user_id', jwtUserId)");
      final destinatarios = ts.indexOf(".neq('user_id', callerId)");
      expect(guard, greaterThan(0));
      expect(guard, lessThan(destinatarios));
    });
  });

  group('Functions de push recusam quando falta WEBHOOK_SECRET', () {
    for (final fn in ['send-module-notification', 'send-workflow-notification']) {
      test(fn, () {
        final ts = read('supabase/functions/$fn/index.ts');
        expect(code('supabase/functions/$fn/index.ts'),
            isNot(contains('aceitando sem validacao')));
        expect(ts, contains("status: 503"));
      });
    }
  });

  group('get-agora-token', () {
    final ts = read('supabase/functions/get-agora-token/index.ts');

    test('nome de canal fora de call_/room_ é recusado, não liberado', () {
      expect(ts, contains('if (!roomMatch) {'));
      expect(ts, isNot(contains('if (chatIdMatch) {')),
          reason: 'A checagem condicional deixava qualquer outro nome passar.');
    });

    test('room_ é checado contra meetings, não contra chat_members', () {
      expect(ts, contains(".from('meetings')"));
      expect(ts, contains('meeting.host_id === user.id'));
    });
  });

  group('Migration 20260916120000', () {
    const path =
        'supabase/migrations/20260916120000_security_audit_2026_09_16.sql';
    final sql = read(path);

    test('RPCs de leitura e atividade exigem p_user_id = auth.uid()', () {
      expect(
        'p_user_id IS DISTINCT FROM auth.uid()'.allMatches(sql).length,
        3,
        reason: 'mark_messages_as_read, mark_all_chats_as_read e '
            'log_user_activity',
      );
    });

    test('REVOKEs nomeiam anon, não só PUBLIC', () {
      final revokes = RegExp(r'^REVOKE ALL ON FUNCTION .*$', multiLine: true)
          .allMatches(sql)
          .map((m) => m.group(0)!);
      expect(revokes, isNotEmpty);
      for (final r in revokes) {
        expect(r, contains('anon'), reason: r);
      }
    });

    test('RPCs de workflow sem uso perdem EXECUTE e métricas viram INVOKER', () {
      expect(sql, contains("p.proname IN ('update_workflow_status', 'get_workflow_cards')"));
      expect(sql, contains('FROM PUBLIC, anon, authenticated'));
      expect(sql, contains('ALTER FUNCTION public.get_workflow_metrics(uuid) SECURITY INVOKER;'));
    });

    test('transcrição não aceita mais INSERT irrestrito', () {
      expect(sql, contains('DROP POLICY IF EXISTS "Service can insert transcriptions"'));
      expect(code(path), isNot(contains('WITH CHECK (true)')));
    });

    test('as cinco RPCs administrativas chamam a guarda de organização', () {
      for (final fn in [
        'admin_toggle_user_status',
        'admin_update_user_role',
        'admin_update_user',
        'admin_update_user_password',
        'admin_reject_user',
      ]) {
        final start = sql.indexOf('CREATE OR REPLACE FUNCTION public.$fn(');
        expect(start, greaterThan(0), reason: fn);
        final end = sql.indexOf(r'$$;', start);
        expect(
          sql.substring(start, end),
          contains('PERFORM public.fn_assert_same_org(p_target_user_id);'),
          reason: fn,
        );
      }
    });

    test('não contém UTF-8 BOM (o psql aborta na linha 1)', () {
      final bytes = File(path).readAsBytesSync();
      expect(bytes.take(3).toList(), isNot(equals([0xEF, 0xBB, 0xBF])));
    });
  });

  group('Logout apaga o que a conta deixou no aparelho', () {
    test('marcar offline é best-effort e o cache Hive é limpo', () {
      final dart = read('lib/features/auth/providers/auth_provider.dart');
      final offline = dart.indexOf("'is_online': false");
      final tryBefore = dart.lastIndexOf('try {', offline);
      final wipe = dart.indexOf('BackupService.limparDadosDoDispositivo()');
      expect(tryBefore, greaterThan(dart.indexOf('// -- 2. Marcar como offline --')),
          reason: 'Sem rede o update lança e pulava limpeza e signOut.');
      expect(dart.indexOf('OfflineCacheService.clearAll()'), greaterThan(wipe));
    });

    test('clearAll inclui mensagens de canal e a fila offline', () {
      final dart = read('lib/core/services/offline_cache_service.dart');
      final start = dart.indexOf('static Future<void> clearAll()');
      final body = dart.substring(start, dart.indexOf('clearOldCache', start));
      expect(body, contains('channelMessagesBoxName'));
      expect(body, contains('queueBoxName'));
    });
  });

  group('Hosting envia cabeçalhos de segurança', () {
    final config = jsonDecode(read('firebase.json')) as Map<String, dynamic>;

    test('todos os alvos bloqueiam iframe e sniffing de MIME', () {
      for (final target in (config['hosting'] as List).cast<Map>()) {
        final globais = (target['headers'] as List? ?? [])
            .cast<Map>()
            .where((h) => h['source'] == '**')
            .expand((h) => (h['headers'] as List).cast<Map>())
            .map((h) => '${h['key']}: ${h['value']}')
            .toList();
        expect(globais, contains("Content-Security-Policy: frame-ancestors 'none'"),
            reason: '${target['target']}');
        expect(globais, contains('X-Content-Type-Options: nosniff'),
            reason: '${target['target']}');
      }
    });
  });
}
