import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'runtime_config.dart';

/// Configuração do ambiente.
///
/// Prioridade de cada chave:
///   1. `config.json` publicado junto do app Web ([RuntimeConfig]) — permite
///      apontar o mesmo build para outro backend sem recompilar;
///   2. `--dart-define` (embutido no build);
///   3. `.env` local (desenvolvimento).
class AppEnv {
  AppEnv._();

  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _firebaseWebApiKey =
      String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const _firebaseWebAppId =
      String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _firebaseWebMessagingSenderId =
      String.fromEnvironment('FIREBASE_WEB_MESSAGING_SENDER_ID');
  static const _firebaseWebProjectId =
      String.fromEnvironment('FIREBASE_WEB_PROJECT_ID');
  static const _firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
  static const _agoraAppId = String.fromEnvironment('AGORA_APP_ID');
  static const _agoraTempToken = String.fromEnvironment('AGORA_TEMP_TOKEN');
  static const _environment = String.fromEnvironment('ENVIRONMENT');
  static const _appBaseUrl = String.fromEnvironment('APP_BASE_URL');

  /// Flag de tenancy definida em build via dart_defines (`MULTI_TENANT`).
  ///
  /// **Não é o switch de marca.** Hoje só `dart_defines.admin.json` a define,
  /// então nas builds normais (dev e prod, nas duas marcas) ela é `false` e
  /// qualquer ternário baseado nela cairia sempre no mesmo ramo. O nome visível
  /// do app sai de `AppConstants.appName`. Compile-time const — sem fallback
  /// via dotenv.
  static const _multiTenant =
      bool.fromEnvironment('MULTI_TENANT', defaultValue: false);

  /// `true` apenas na build do Console de Plataforma (host de admin separado,
  /// entrypoint `lib/main_admin.dart`). Nas builds de tenant (Fluxy e AlinhaJá) brand-guard:allow
  /// é `false` → o console não é roteável. É o gate único do console.
  static const _platformAdmin =
      bool.fromEnvironment('PLATFORM_ADMIN', defaultValue: false);

  static String _value(String dartDefineValue, String dotenvKey) {
    final runtime = RuntimeConfig.values[dotenvKey];
    if (runtime != null && runtime.isNotEmpty) return runtime;
    if (dartDefineValue.isNotEmpty) return dartDefineValue;
    // O .env não é empacotado no APK/web de produção: sem load() bem-sucedido,
    // dotenv.env lança NotInitializedError — então só lê se estiver carregado.
    if (!dotenv.isInitialized) return '';
    return dotenv.env[dotenvKey] ?? '';
  }

  static String get supabaseUrl => _value(_supabaseUrl, 'SUPABASE_URL');
  static String get supabaseAnonKey =>
      _value(_supabaseAnonKey, 'SUPABASE_ANON_KEY');
  static String get firebaseWebApiKey =>
      _value(_firebaseWebApiKey, 'FIREBASE_WEB_API_KEY');
  static String get firebaseWebAppId =>
      _value(_firebaseWebAppId, 'FIREBASE_WEB_APP_ID');
  static String get firebaseWebMessagingSenderId =>
      _value(_firebaseWebMessagingSenderId, 'FIREBASE_WEB_MESSAGING_SENDER_ID');
  static String get firebaseWebProjectId =>
      _value(_firebaseWebProjectId, 'FIREBASE_WEB_PROJECT_ID');
  static String get firebaseVapidKey =>
      _value(_firebaseVapidKey, 'FIREBASE_VAPID_KEY');
  static String get agoraAppId => _value(_agoraAppId, 'AGORA_APP_ID');
  static String get agoraTempToken =>
      _value(_agoraTempToken, 'AGORA_TEMP_TOKEN');

  /// Endereço público do app Web, sem barra final. Usado em links que saem
  /// do app (redefinição de senha, página de carreiras).
  ///
  /// Sem configuração explícita: na Web, a própria origem (dev, produção e
  /// instalação do cliente resolvem sozinhos); no celular, onde não há
  /// origem, o host da nuvem conforme o ambiente.
  static String get appBaseUrl {
    final configured = _value(_appBaseUrl, 'APP_BASE_URL');
    if (configured.isNotEmpty) {
      return configured.replaceFirst(RegExp(r'/+$'), '');
    }
    if (kIsWeb) return Uri.base.origin;
    return isDev
        ? 'https://alinhajadev.web.app'
        : 'https://alinha-ja-app.web.app';
  }

  /// 'dev' quando buildado com dart_defines.dev.json; vazio/'prod' em produção.
  static String get environment => _value(_environment, 'ENVIRONMENT');
  static bool get isDev => environment == 'dev';

  /// `true` apenas onde `MULTI_TENANT=true` foi passado no build — hoje só a
  /// build do Console de Plataforma. **Não use para decidir marca**: use
  /// `AppConstants.appName`. Não confundir com [isPlatformAdminBuild].
  static bool get isMultiTenant => _multiTenant;

  /// `true` somente na build do Console de Plataforma (host de admin). Gate de
  /// visibilidade/roteamento do console; a autorização real é o RLS
  /// `is_platform_owner` no Supabase.
  static bool get isPlatformAdminBuild => _platformAdmin;
}
