import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart' as flutter_dotenv;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/config/runtime_config.dart';
import 'package:alinha_ja/core/services/push_notification_service.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/core/services/offline_cache_service.dart';
import 'package:alinha_ja/core/services/realtime_polling_service.dart';
import 'package:alinha_ja/core/services/location_service.dart';
import 'package:alinha_ja/core/services/sync_service.dart';
import 'package:alinha_ja/core/database/drift_database.dart';
import 'package:alinha_ja/core/network/timeout_http_client.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'app.dart';

/// Ponto de entrada — carrega .env e inicializa o Supabase.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa cache offline (Hive)
  await OfflineCacheService.init();

  // Inicializa o banco de dados estruturado Drift
  try {
    await driftDb.customSelect('SELECT 1').get();
    debugPrint('DriftDatabase: Inicializado com sucesso.');
  } catch (e) {
    debugPrint('DriftDatabase: Falha na inicialização - $e');
  }

  // Inicializa serviço de polling inteligente
  RealtimePollingService.instance.init();

  // Registra as traduções de tempo relativo (Timeago) para pt_BR
  timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
  timeago.setLocaleMessages('pt_BR_short', timeago.PtBrShortMessages());
  timeago.setDefaultLocale('pt_BR');

  // Carrega .env como fallback local. isOptional: o .env não é asset do
  // release, e sem ele o dotenv ficaria não inicializado — qualquer leitura
  // de dotenv.env lançaria NotInitializedError e derrubaria o app.
  try {
    await flutter_dotenv.dotenv.load(fileName: '.env', isOptional: true);
  } catch (e) {
    debugPrint(
        'Aviso: .env não carregado via rede. Usando variáveis embutidas (--dart-define).');
  }

  // config.json publicado com o app Web (no-op no celular). Precisa vir antes
  // de qualquer leitura do AppEnv: é ele que aponta o build para o backend.
  await RuntimeConfig.load();

  // Prioridade: config.json (Web) > dart-define (compilação) > dotenv
  final supabaseUrl = AppEnv.supabaseUrl;
  final supabaseAnonKey = AppEnv.supabaseAnonKey;

  debugPrint(
      '🔗 Supabase URL: ${supabaseUrl.isNotEmpty ? supabaseUrl.substring(0, 20) : "VAZIO!"}...');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      // PKCE em vez de implicit: o implicit flow devolve o access token no
      // fragmento da URL, onde ele fica exposto a histórico do navegador,
      // extensões e referrer. Com PKCE o token vem no corpo da resposta.
      authFlowType: AuthFlowType.pkce,
    ),
    postgrestOptions: const PostgrestClientOptions(
      schema: 'public',
    ),
    realtimeClientOptions: const RealtimeClientOptions(
      eventsPerSecond: 10,
    ),
    httpClient: TimeoutHttpClient(
      timeoutDuration: const Duration(seconds: 15),
      maxRetries: 2,
    ),
  );

  // Inicializa o Firebase (Web usa credenciais injetadas, mobile usa google-services.json)
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: AppEnv.firebaseWebApiKey,
        appId: AppEnv.firebaseWebAppId,
        messagingSenderId: AppEnv.firebaseWebMessagingSenderId,
        projectId: AppEnv.firebaseWebProjectId,
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  // Registra o handler de background logo após o Firebase: se um passo
  // abaixo falhar, o push com o app fechado continua sendo exibido.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Inicializa serviço de chamadas (CallKit + Agora) — após dotenv e Supabase
  await CallService.instance.init();

  // Sem pedido de permissões no boot: cada recurso pede a sua na hora do uso
  // (notificação no login, microfone/câmera ao ligar ou atender, localização
  // ao iniciar o rastreamento, galeria ao abrir o anexo).

  // Inicializa o sistema de rastreamento de localização (ignorado na Web)
  await LocationService().init();

  // Inicializa o serviço de sincronização após o Supabase e bancos estarem prontos
  SyncService().init();

  // NOTA: A inicialização do PushNotificationService é feita em app.dart
  // dentro do contexto Riverpod, para que o Ref seja injetado corretamente.

  runApp(
    // ProviderScope habilita o Riverpod em toda a árvore
    const ProviderScope(child: AppRoot()),
  );
}

