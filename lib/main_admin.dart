import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart' as flutter_dotenv;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/config/runtime_config.dart';
import 'package:alinha_ja/core/network/timeout_http_client.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'app.dart';

/// Entrypoint do **Console de Plataforma** (host de admin separado).
///
/// Buildar com `--target lib/main_admin.dart --dart-define PLATFORM_ADMIN=true`
/// (ver `dart_defines.admin.example.json`). Reaproveita [AppRoot] e todo o
/// fluxo de auth/2FA; o router (com `PLATFORM_ADMIN=true`) leva o usuário
/// verificado direto ao `/plataforma`.
///
/// Bootstrap enxuto: NÃO inicializa serviços de tenant (Drift, chamadas,
/// localização, push/FCM, sync, polling) — o console fala apenas com o Supabase
/// (auth + RPCs `platform_*`, guardadas por `fn_is_platform_owner()`).
Future<void> main() async {
  assert(() {
    if (!AppEnv.isPlatformAdminBuild) {
      debugPrint('AVISO: main_admin.dart sem PLATFORM_ADMIN=true. '
          'Adicione --dart-define PLATFORM_ADMIN=true.');
    }
    return true;
  }());

  WidgetsFlutterBinding.ensureInitialized();

  // Traduções de tempo relativo (usadas em listagens do console).
  timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
  timeago.setLocaleMessages('pt_BR_short', timeago.PtBrShortMessages());
  timeago.setDefaultLocale('pt_BR');

  // .env como fallback local; em produção web usa os --dart-define embutidos.
  // isOptional: sem o arquivo o dotenv ficaria não inicializado e qualquer
  // leitura de dotenv.env lançaria NotInitializedError (mesmo motivo do
  // `main.dart`).
  try {
    await flutter_dotenv.dotenv.load(fileName: '.env', isOptional: true);
  } catch (e) {
    debugPrint('Aviso: .env não carregado. Usando variáveis embutidas (--dart-define).');
  }

  // config.json publicado com o app (mesma regra do `main.dart`).
  await RuntimeConfig.load();

  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    anonKey: AppEnv.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      // Mesmo motivo do `main.dart`: PKCE mantém o access token fora da URL.
      // O console de plataforma é o entrypoint do dono — vazar o token dele
      // aqui daria acesso a todas as empresas, não a uma.
      authFlowType: AuthFlowType.pkce,
    ),
    postgrestOptions: const PostgrestClientOptions(schema: 'public'),
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
    httpClient: TimeoutHttpClient(
      timeoutDuration: const Duration(seconds: 15),
      maxRetries: 2,
    ),
  );

  runApp(const ProviderScope(child: AppRoot()));
}
