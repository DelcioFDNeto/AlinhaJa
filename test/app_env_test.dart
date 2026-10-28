import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alinha_ja/core/config/app_env.dart';

/// Regressão: o APK de release não empacota o .env, então o dotenv pode não
/// estar inicializado. Ler uma chave sem --dart-define (ex.: ENVIRONMENT, que
/// o builder do MaterialApp consulta via AppEnv.isDev) lançava
/// NotInitializedError e o app abria direto na tela "Ops! Algo deu errado.".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppEnv não lança quando o dotenv não foi carregado', () {
    expect(dotenv.isInitialized, isFalse);
    expect(() => AppEnv.isDev, returnsNormally);
    expect(AppEnv.environment, isEmpty);
    expect(AppEnv.agoraTempToken, isEmpty);
  });

  test('load opcional sem .env deixa o dotenv inicializado e vazio', () async {
    await dotenv.load(fileName: '.env.inexistente', isOptional: true);
    expect(dotenv.isInitialized, isTrue);
    expect(dotenv.env, isEmpty);
    expect(AppEnv.isDev, isFalse);
  });
}
