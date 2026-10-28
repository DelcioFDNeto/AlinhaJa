import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'runtime_config_stub.dart'
    if (dart.library.js_interop) 'runtime_config_web.dart' as platform;

/// Configuração lida em tempo de execução, sem recompilar o app.
///
/// Na Web, o app busca `config.json` ao lado do `index.html` antes de
/// inicializar o Supabase. Assim **o mesmo build** atende a nuvem e uma
/// instalação no servidor do cliente: muda só o arquivo publicado junto.
///
/// ```json
/// { "SUPABASE_URL": "https://supabase.cliente.com.br",
///   "SUPABASE_ANON_KEY": "eyJ...",
///   "APP_BASE_URL": "https://app.cliente.com.br" }
/// ```
///
/// As chaves são as mesmas do `dart_defines.example.json`. Arquivo ausente,
/// inválido ou lento não impede a abertura: o app segue com os valores
/// embutidos no build (`--dart-define`). No Android/iOS não há arquivo a
/// buscar e o carregamento é um no-op.
class RuntimeConfig {
  RuntimeConfig._();

  static Map<String, String> _values = const {};

  /// Valores carregados (vazio até [load] concluir ou fora da Web).
  static Map<String, String> get values => _values;

  /// Tempo máximo de espera pelo arquivo: o boot não pode travar por ele.
  static const timeout = Duration(seconds: 4);

  /// Busca e aplica o `config.json`. Nunca lança.
  static Future<void> load({http.Client? client}) async {
    final url = platform.configUrl();
    if (url == null) return;
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(url, headers: const {'Cache-Control': 'no-cache'})
          .timeout(timeout);
      if (res.statusCode != 200) return;
      _values = parse(res.body);
      if (_values.isNotEmpty) {
        debugPrint('RuntimeConfig: ${_values.length} chave(s) de $url');
      }
    } catch (e) {
      debugPrint('RuntimeConfig: config.json indisponível ($e) — usando o build.');
    } finally {
      if (client == null) c.close();
    }
  }

  /// Converte o conteúdo do arquivo em pares chave → texto.
  ///
  /// O Firebase Hosting reescreve qualquer rota inexistente para o
  /// `index.html`: sem `config.json` publicado, a resposta é HTML com status
  /// 200. Conteúdo que não seja um objeto JSON vale como "sem configuração".
  /// Valores vazios são descartados para não apagar o que veio do build.
  @visibleForTesting
  static Map<String, String> parse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const {};
      final out = <String, String>{};
      decoded.forEach((k, v) {
        if (v is String || v is num || v is bool) {
          final s = v.toString().trim();
          if (s.isNotEmpty) out[k.toString()] = s;
        }
      });
      return Map.unmodifiable(out);
    } on FormatException {
      return const {};
    }
  }

  /// Substitui os valores carregados (testes).
  @visibleForTesting
  static void debugSetValues(Map<String, String> values) => _values = values;
}
