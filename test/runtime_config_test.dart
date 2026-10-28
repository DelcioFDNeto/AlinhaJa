import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/config/runtime_config.dart';

/// Configuração em tempo de execução: o mesmo build Web atende a nuvem e a
/// instalação no servidor do cliente trocando só o `config.json`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => RuntimeConfig.debugSetValues(const {}));

  group('RuntimeConfig.parse', () {
    test('lê pares chave → texto e descarta vazios', () {
      final v = RuntimeConfig.parse(
          '{"SUPABASE_URL": " https://sb.cliente.com.br ", "VAZIO": "", "N": 3}');
      expect(v, {'SUPABASE_URL': 'https://sb.cliente.com.br', 'N': '3'});
    });

    test('HTML do rewrite do hosting vale como "sem configuração"', () {
      expect(RuntimeConfig.parse('<!DOCTYPE html><html></html>'), isEmpty);
    });

    test('JSON que não é objeto é ignorado', () {
      expect(RuntimeConfig.parse('["SUPABASE_URL"]'), isEmpty);
      expect(RuntimeConfig.parse('null'), isEmpty);
    });

    test('objetos aninhados não viram texto', () {
      expect(RuntimeConfig.parse('{"A": {"b": 1}, "C": "d"}'), {'C': 'd'});
    });
  });

  group('AppEnv com config.json', () {
    test('o arquivo tem prioridade sobre o build', () {
      RuntimeConfig.debugSetValues({'SUPABASE_URL': 'https://sb.cliente.com.br'});
      expect(AppEnv.supabaseUrl, 'https://sb.cliente.com.br');
    });

    test('sem arquivo, nada muda', () {
      expect(AppEnv.supabaseUrl, isEmpty);
      expect(() => AppEnv.isDev, returnsNormally);
    });

    test('APP_BASE_URL perde a barra final', () {
      RuntimeConfig.debugSetValues({'APP_BASE_URL': 'https://app.cliente.com.br/'});
      expect(AppEnv.appBaseUrl, 'https://app.cliente.com.br');
    });

    test('sem APP_BASE_URL fora da Web, usa o host da nuvem', () {
      expect(AppEnv.appBaseUrl, 'https://alinha-ja-app.web.app');
    });
  });

  test('load fora da Web não faz requisição', () async {
    var chamadas = 0;
    final client = MockClient((_) async {
      chamadas++;
      return http.Response('{"SUPABASE_URL": "x"}', 200);
    });
    await RuntimeConfig.load(client: client);
    expect(chamadas, 0);
    expect(RuntimeConfig.values, isEmpty);
  });
}
