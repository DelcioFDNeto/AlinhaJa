import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/features/profile/models/user_model.dart';

/// Guardas dos defeitos encontrados no audit de 2026-09-03.
///
/// Os três falhavam **apenas em runtime, contra o banco**: nenhum aparecia no
/// `flutter analyze` nem nos testes de modelo, e os dois primeiros derrubavam
/// funcionalidade inteira (toda chamada de vídeo; a listagem de PII do painel
/// admin). Estes testes prendem o invariante no repositório para que a
/// regressão não volte pela próxima rodada de sync entre os forks.
void main() {
  const migration =
      'supabase/migrations/20260903140000_revoke_phone_column_privilege.sql';
  const agoraFn = 'supabase/functions/get-agora-token/index.ts';

  group('SELECT de users não pede coluna revogada', () {
    test('selectColumns fica fora das colunas sem privilégio', () {
      final colunas = UserModel.selectColumns.split(RegExp(r'[,\s]+'));
      for (final col in ['cpf', 'data_nascimento', 'sexo', 'phone']) {
        expect(
          colunas,
          isNot(contains(col)),
          reason: 'O SELECT de `$col` foi revogado para `authenticated`. '
              'Pedi-la aqui devolve 403 e derruba toda tela que usa '
              'selectColumns — inclusive o currentUserProvider.',
        );
      }
    });

    test('email continua no SELECT: o bootstrap do app depende dele', () {
      // GRANT de coluna não é sensível a linha: revogar `email` bloquearia
      // também a leitura do próprio e-mail, e currentUserProvider carrega a
      // sessão com selectWithOrg.
      expect(UserModel.selectColumns.split(RegExp(r'[,\s]+')), contains('email'));
    });

    test('fromJson sobrevive à ausência de phone', () {
      final u = UserModel.fromJson({'id': 'u1', 'full_name': 'Fulano'});
      expect(u.phone, isNull);
      expect(u.fullName, 'Fulano');
    });

    test('must_change_password possui concessão explícita de SELECT para authenticated', () {
      final migrationFiles = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .map((f) => f.readAsStringSync())
          .join('\n');

      expect(
        migrationFiles,
        contains('GRANT SELECT (must_change_password) ON public.users TO authenticated'),
        reason: 'Como SELECT on users foi revogado globalmente, must_change_password '
            'precisa de grant explícito para a consulta do login não falhar com 42501.',
      );
    });
  });

  group('Migration do revoke de phone', () {
    String sql() => File(migration).readAsStringSync();

    test('admin_list_users_pii é VOLATILE', () {
      // A função grava em rh_access_log; STABLE faz o PostgreSQL recusar o
      // INSERT com 0A000 e a listagem de PII quebra por inteiro.
      final corpo = sql().split('admin_list_users_pii()').skip(1).join();
      expect(corpo, contains('VOLATILE'));
      expect(
        RegExp(r'CREATE FUNCTION public\.admin_list_users_pii[\s\S]{0,400}?STABLE')
            .hasMatch(sql()),
        isFalse,
        reason: 'STABLE aqui reintroduz o bug corrigido pela 20260813152000',
      );
    });

    test('as duas funções são DROPadas antes do CREATE', () {
      // Mudar o RETURNS TABLE é mudar o tipo de retorno, e CREATE OR REPLACE
      // recusa isso com 42P13 — sem o DROP a migration aborta inteira.
      for (final fn in ['get_my_sensitive_profile', 'admin_list_users_pii']) {
        expect(sql(), contains('DROP FUNCTION IF EXISTS public.$fn()'));
        expect(sql(), isNot(contains('CREATE OR REPLACE FUNCTION public.$fn()')));
      }
    });

    test('a org-alvo vem de fn_current_org()', () {
      // Ler organization_id da própria linha ignora a "empresa em atuação"
      // do dono da plataforma e quebra o console multi-empresa.
      expect(sql(), contains('public.fn_current_org()'));
    });

    test('o revoke não inclui email', () {
      final revoke = RegExp(r"column_name NOT IN \(([^)]*)\)").firstMatch(sql());
      expect(revoke, isNotNull);
      expect(revoke!.group(1), contains("'phone'"));
      expect(revoke.group(1), isNot(contains("'email'")));
    });
  });

  group('Guarda de membresia e logs do get-agora-token', () {
    final ts = File(agoraFn).readAsStringSync();

    test('a checagem seleciona uma coluna que existe nas tabelas (R1)', () {
      // chat_members e channel_members têm PK composta (chat_id,user_id) /
      // (channel_id,user_id) e NÃO têm coluna `id`: pedir 'id' devolve 42703,
      // o `data` volta null e todo mundo leva 403 ao entrar em chamada.
      expect(
        ts,
        isNot(contains(".select('id')")),
        reason: 'chat_members/channel_members não têm coluna id',
      );
      expect(".select('user_id')".allMatches(ts).length, 2);
    });

    test('não registra user.email nos logs (Achado 12 - Minimização)', () {
      // Minimização da LGPD: user.id é suficiente para diagnóstico e não
      // retém identificador pessoal direto (e-mail) nos logs de execução.
      expect(
        ts,
        isNot(contains('user.email')),
        reason: 'get-agora-token não deve registrar user.email nos logs',
      );
      expect(ts, contains('user.id'));
    });
  });

  group('Migration de remediação dos 12 achados de segurança', () {
    const remMigration =
        'supabase/migrations/20260903170000_security_audit_remediation_12_findings.sql';
    String sql() => File(remMigration).readAsStringSync();

    test('derruba a policy permissiva branches_public_read (Achado 01)', () {
      expect(sql(), contains('DROP POLICY IF EXISTS branches_public_read ON public.branches;'));
      expect(sql(), contains('ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;'));
    });

    test('signup de candidato adota bcrypt custo 12 e expiração de token (Achados 05 e 08)', () {
      expect(sql(), contains("extensions.gen_salt('bf', 12)"));
      expect(sql(), contains('verification_token_expires_at'));
      expect(sql(), contains("NOW() + INTERVAL '48 hours'"));
    });

    test('login de candidato re-hasheia custo < 12 e limita sessão em 7 dias (Achados 05 e 08)', () {
      expect(sql(), contains("NOW() + INTERVAL '7 days'"));
      expect(sql(), contains("extensions.gen_salt('bf', 12)"));
    });

    test('troca de senha invalida todas as sessões anteriores (Achado 08)', () {
      expect(sql(), contains('DELETE FROM public.candidato_sessao WHERE candidato_usuario_id = v_user_id;'));
    });

    test('archive_user e delete_user_account limpam avatar do storage (Achado 09 - LGPD Art. 18)', () {
      expect(sql(), contains("DELETE FROM storage.objects\n     WHERE bucket_id = 'avatars'"));
      expect(sql(), contains('avatar_url = NULL'));
    });

    test('não contém UTF-8 BOM (evita quebra no psql/db push)', () {
      final bytes = File(remMigration).readAsBytesSync();
      expect(
        bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF,
        isFalse,
        reason: 'Migration não pode ter BOM UTF-8 porque o psql aborta na linha 1',
      );
    });

    test('hardening de search_path qualifica as 3 funções sensíveis (Achado 07)', () {
      expect(sql(), contains("SET search_path = ''"));
      // create_direct_chat
      expect(sql(), contains('FROM public.chat_members cm1'));
      expect(sql(), contains('INNER JOIN public.chats c ON c.id = cm1.chat_id'));
      expect(sql(), contains('INSERT INTO public.chats (type, created_by)'));
      expect(sql(), contains('INSERT INTO public.chat_members (chat_id, user_id, role)'));
      // mark_all_chats_as_read
      expect(sql(), contains('FROM public.chat_members WHERE user_id = p_user_id'));
      // get_workflow_metrics
      expect(sql(), contains('FROM public.workflow_cards WHERE channel_id = p_channel_id'));
      expect(sql(), contains('FROM public.workflow_cards\n        WHERE channel_id = p_channel_id'));
    });
  });

  group('Migration 001 não regride chat-media para público (Achado 10)', () {
    test('ON CONFLICT do bucket chat-media não sobrescreve public', () {
      final sql001 = File('supabase/migrations/001_init_base_schema_and_channels.sql').readAsStringSync();
      final bucketBlock = sql001.split("'chat-media'")[2];
      expect(
        bucketBlock.substring(0, 300),
        isNot(contains('public = EXCLUDED.public')),
        reason: 'Migration 001 não deve reverter chat-media para público em reexecução',
      );
    });
  });

  group('Edge Function rh-automations test_smtp (Achado 04)', () {
    test('prioriza authOrgId do JWT para evitar leak cross-tenant', () {
      final ts = File('supabase/functions/rh-automations/index.ts').readAsStringSync();
      // No caminho por JWT o payload é ignorado por completo — inclusive
      // quando o usuário não tem organização (authOrgId nulo), caso em que
      // o antigo `authOrgId || payload.organization_id` caía no payload.
      expect(ts, contains('authViaJwt ? authOrgId : payload.organization_id'));
      expect(
        ts,
        isNot(contains('payload.organization_id || authOrgId')),
        reason: 'O ID do payload não pode sobrepor o authOrgId autenticado pelo JWT',
      );
    });
  });

  group('Edge Function rh-candidatura (Achados 02, 03, 05, 06)', () {
    final ts = File('supabase/functions/rh-candidatura/index.ts').readAsStringSync();

    test('extrai IP real de proxies confiáveis sem confiar no cabeçalho do cliente (Achado 03)', () {
      expect(ts, contains('getClientIp(req)'));
      expect(
        ts,
        isNot(contains("req.headers.get('x-forwarded-for')?.split(',')[0]")),
        reason: 'Não deve confiar no primeiro elemento de x-forwarded-for controlado pelo remetente',
      );
    });

    test('aplica rate limiting em auth_login e auth_signup (Achado 02)', () {
      expect(ts, contains("checkRateLimit(supabase, ip, 'auth_login'"));
      expect(ts, contains("checkRateLimit(supabase, ip, 'auth_signup'"));
    });

    test('exige senha forte de no mínimo 12 caracteres com símbolos (Achado 05)', () {
      expect(ts, contains('password.length < 12'));
    });

    test('erro de login não distingue usuário inexistente de senha errada (Achado 06)', () {
      expect(
        ts,
        isNot(contains('return json({ error: error.message }, 401);')),
        reason: 'Mensagem de erro não deve expor error.message verbatim ao cliente',
      );
    });
  });

  group('ProfileScreen guarda dados sensíveis contra perda (Achado 11)', () {
    test('profile_screen.dart possui proteção _sensitiveDataLoaded', () {
      final dart = File('lib/features/profile/ui/profile_screen.dart').readAsStringSync();
      expect(dart, contains('_sensitiveDataLoaded'));
      expect(dart, contains('if (_sensitiveDataLoaded)'));
    });
  });
  group('Função com search_path fixo não usa enum do public sem prefixo', () {
    // A migration 20260903170000 pinou search_path = '' em toda função
    // SECURITY DEFINER. Ela cuidou das que referenciavam TABELAS sem prefixo,
    // mas approve_workflow_card quebrou por um cast de enum: nomes de tipo em
    // cast resolvem na EXECUÇÃO, e o ALTER FUNCTION não valida o corpo — a
    // migration aplicou limpa e aprovar card passou a dar 42704 em produção.
    // Este guard vale para toda função, não só para aquela.

    /// Última definição de cada função nas migrations, em ordem cronológica.
    Map<String, List<String>> definicoesDeFuncoes() {
      final dir = Directory('supabase/migrations');
      final arquivos = dir.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.sql')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final fnRe = RegExp(
        r'CREATE (?:OR REPLACE )?FUNCTION\s+(?:public\.)?([a-z_0-9]+)\s*\('
        r'([\s\S]*?)\)([\s\S]*?)AS\s*\$([a-z_]*)\$([\s\S]*?)\$\4\$',
        caseSensitive: false,
      );

      final ultima = <String, List<String>>{};
      for (final f in arquivos) {
        final sql = f.readAsStringSync();
        for (final m in fnRe.allMatches(sql)) {
          // [cabeçalho, corpo, arquivo]
          ultima[m.group(1)!.toLowerCase()] = [
            m.group(3)!,
            m.group(5)!,
            f.uri.pathSegments.last,
          ];
        }
      }
      return ultima;
    }

    Set<String> tiposCustomizados() {
      final dir = Directory('supabase/migrations');
      final re = RegExp(r'CREATE\s+TYPE\s+(?:public\.)?"?([a-z_0-9]+)"?',
          caseSensitive: false);
      final tipos = <String>{};
      for (final f in dir.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.sql'))) {
        for (final m in re.allMatches(f.readAsStringSync())) {
          tipos.add(m.group(1)!.toLowerCase());
        }
      }
      return tipos;
    }

    test('nenhum cast para enum do public fica sem prefixo', () {
      final tipos = tiposCustomizados();
      expect(tipos, isNotEmpty, reason: 'não achei nenhum CREATE TYPE');

      final castRe = RegExp(r'::\s*([a-z_0-9.]+)', caseSensitive: false);
      final spRe = RegExp(r'SET\s+search_path\s*=\s*([^\n]*)',
          caseSensitive: false);
      final definerRe = RegExp(r'SECURITY\s+DEFINER', caseSensitive: false);
      final infratores = <String>[];

      definicoesDeFuncoes().forEach((nome, partes) {
        final cabecalho = partes[0], corpo = partes[1], arquivo = partes[2];

        // Só interessa quem roda SEM `public` no caminho de busca:
        //  • quem declara search_path = '' na própria DDL; e
        //  • quem não declara nada e é SECURITY DEFINER — a 20260903170000
        //    varreu essas e pinou '' no banco, mesmo o texto da migration
        //    não mostrando.
        // `search_path = public` resolve o cast normalmente e fica de fora.
        final sp = spRe.firstMatch(cabecalho);
        final semPublic = sp == null
            ? definerRe.hasMatch(cabecalho)
            : RegExp(r"^''\s*;?\s*$").hasMatch(sp.group(1)!.trim());
        if (!semPublic) return;

        for (final c in castRe.allMatches(corpo)) {
          final t = c.group(1)!.toLowerCase();
          if (tipos.contains(t)) infratores.add('$nome ($arquivo) -> ::$t');
        }
      });

      expect(
        infratores,
        isEmpty,
        reason: 'Com search_path fixo, o cast não resolve e a chamada aborta '
            'com 42704. Qualifique como public.<tipo>.',
      );
    });

    test('approve_workflow_card qualifica o enum e fixa search_path', () {
      final partes = definicoesDeFuncoes()['approve_workflow_card'];
      expect(partes, isNotNull);
      expect(partes![0], contains('SET search_path'));
      expect(partes[1], contains('public.workflow_approval_status'));
      expect(
        RegExp(r"::\s*workflow_approval_status").hasMatch(partes[1]),
        isFalse,
        reason: 'sobrou cast sem o prefixo public.',
      );
    });
  });
}
