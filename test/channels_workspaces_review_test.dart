import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardas dos defeitos da review de canais e workspaces (v1.3.9).
///
/// Os erros eram de contrato entre app e banco — RLS que atualiza zero linhas
/// sem erro, coluna ambígua em policy, ordem de operações destrutivas — e
/// nenhum aparece no analyzer. Os testes prendem cada invariante corrigido.
void main() {
  String read(String path) => File(path).readAsStringSync();
  String code(String path) => read(path)
      .split('\n')
      .where((l) => !RegExp(r'^\s*(//|--)').hasMatch(l))
      .join('\n');

  group('Migration 20260916140000', () {
    const path =
        'supabase/migrations/20260916140000_channels_workspaces_review.sql';
    final sql = code(path);

    test('policies de pedido de entrada amarram o canal do próprio pedido', () {
      for (final policy in [
        'Admins can select channel requests',
        'Admins can update channel requests',
        'Admins can delete channel requests',
      ]) {
        final start = sql.indexOf('CREATE POLICY "$policy"');
        expect(start, isNonNegative, reason: policy);
        final body = sql.substring(start, sql.indexOf(';', start));
        expect(
          body,
          contains(
              'can_review_channel_join_request(channel_join_requests.channel_id)'),
          reason: policy,
        );
      }
      // A subconsulta não pode voltar a comparar channel_id sem qualificar.
      expect(sql, isNot(contains('cm.channel_id = channel_id')));
    });

    test('update_channel_info faz merge e protege chaves de governança', () {
      final start = sql.indexOf('FUNCTION public.update_channel_info(');
      final body = sql.substring(start, sql.indexOf(r'$$;', start));
      expect(body, contains("COALESCE(metadata, '{}'::JSONB) ||"));
      for (final key in [
        'assignment_mode',
        'operator_ids',
        'default_operator_id',
        'archived',
      ]) {
        expect(body, contains("- '$key'"), reason: key);
      }
      expect(body, contains("NOT IN ('everyone', 'admins')"));
    });

    test('contagem por membro agrega no banco sob a RLS do usuário', () {
      final start = sql.indexOf('FUNCTION public.get_channel_message_counts(');
      final body = sql.substring(start, sql.indexOf(r'$$;', start));
      expect(body, contains('SECURITY INVOKER'));
      expect(body, contains('m.deleted_at IS NULL'));
      expect(body, contains('GROUP BY m.sender_id'));
    });
  });

  group('Canal (app)', () {
    final provider =
        code('lib/features/channels/providers/active_channel_provider.dart');

    test('stream da régua principal tem ordem e limite; tópico não', () {
      expect(provider, contains(".order('created_at', ascending: false)"));
      expect(provider, contains('.limit(_timelineStreamWindow)'));
      expect(provider, contains('parentMessageId == null'));
    });

    test('excluir canal: RPC antes de remover arquivos do Storage', () {
      final start = provider.indexOf('Future<void> deleteChannel()');
      final body = provider.substring(start, provider.indexOf('archiveChannel'));
      final rpc = body.indexOf("rpc('delete_channel'");
      final remove = body.indexOf(".remove(batch)");
      expect(rpc, isNonNegative);
      expect(remove, greaterThan(rpc));
    });

    test('tela de info não grava ajuste sem os detalhes carregados', () {
      final screen = code('lib/features/channels/ui/channel_info_screen.dart');
      final start = screen.indexOf('_updateChannelSetting(String key');
      final body = screen.substring(start, screen.indexOf("rpc('update_channel_info'", start));
      expect(body, contains('if (currentDetails == null)'));
    });

    test('aprovar/recusar pedido detecta RLS que atualiza zero linhas', () {
      final screen = code('lib/features/channels/ui/channel_info_screen.dart');
      expect(screen, contains('if ((updated as List).isEmpty)'));
      expect(screen, contains('if ((deleted as List).isEmpty)'));
    });

    test('info do canal: contagem via RPC e galeria sem mídia apagada', () {
      final info =
          code('lib/features/channels/providers/channel_info_provider.dart');
      expect(info, contains("rpc('get_channel_message_counts'"));
      expect(info, contains(".isFilter('deleted_at', null)"));
      expect(info, isNot(contains("row['sender_id'] as String")));
    });
  });

  group('Workflow (app)', () {
    test('comentário do solicitante segue a policy e não engole erro', () {
      final provider =
          code('lib/features/workflow/providers/workflow_provider.dart');
      final start = provider.indexOf('Future<void> addComment(');
      final body = provider.substring(start, provider.indexOf('\n  }\n', start));
      expect(body, contains('s.isFinal'));
      expect(body, isNot(contains('_throwIfRequesterOperation')));
      expect(body, isNot(contains('catch')),
          reason: 'A falha precisa chegar à tela.');

      final sheet =
          code('lib/features/workflow/ui/widgets/card_details_sheet.dart');
      final send = sheet.indexOf('await notifier.addComment(card.id, text);');
      final clear = sheet.indexOf('_commentController.clear();', send);
      final catchIdx = sheet.indexOf('} catch (e) {', send);
      expect(catchIdx, greaterThan(send));
      expect(clear, greaterThan(catchIdx),
          reason: 'O campo só é limpo depois de o envio dar certo.');
    });
  });

  test('Minha Operação tem entrada no menu principal', () {
    final scaffold = code('lib/features/chats/ui/main_scaffold.dart');
    expect(scaffold, contains("value: 'my_operation'"));
    expect(scaffold, contains("context.push('/minha-operacao')"));
  });

  test('versão igual em pubspec, constante, version.json e novidades', () {
    final pubspec = RegExp(r'^version: (\d+\.\d+\.\d+)\+(\d+)', multiLine: true)
        .firstMatch(read('pubspec.yaml'))!;
    final version = pubspec.group(1)!;
    expect(read('lib/core/constants.dart'),
        contains("static const appVersion = '$version';"));
    final webVersion = read('web/version.json');
    expect(webVersion, contains('"version": "$version"'));
    expect(webVersion, contains('"build": "${pubspec.group(2)}"'));
    final changelog = read('lib/features/settings/ui/changelog_screen.dart');
    final firstRelease = RegExp(r"version: 'v([\d.]+)'").firstMatch(changelog)!;
    expect(firstRelease.group(1), version,
        reason: 'A versão mais recente precisa estar no topo das Novidades.');
  });
}
