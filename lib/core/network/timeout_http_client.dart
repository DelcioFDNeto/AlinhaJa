import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Um interceptador de requisições HTTP focado no mercado corporativo (alta resiliência).
/// Ele adiciona:
/// 1. Timeout estrito (evitando que requisições fiquem presas em redes intermitentes).
/// 2. Retry automático (backoff) para métodos idempotentes (GET) em caso de falha de rede/timeout.
class TimeoutHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final Duration timeoutDuration;
  final int maxRetries;

  TimeoutHttpClient({
    this.timeoutDuration = const Duration(seconds: 15),
    this.maxRetries = 2,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    int attempts = 0;

    // Apenas tenta repetir requisições idempotentes (leitura)
    final bool canRetry = request.method == 'GET';

    while (true) {
      attempts++;
      try {
        // Para a primeira tentativa, usa a request original.
        // Nas tentativas seguintes, clona a request para evitar "Can't finalize a finalized Request".
        final currentRequest = attempts == 1 ? request : _cloneRequest(request);

        final response =
            await _inner.send(currentRequest).timeout(timeoutDuration);
        return response;
      } on TimeoutException {
        if (canRetry && attempts <= maxRetries) {
          debugPrint(
              '🌐 [TimeoutHttpClient] Timeout na tentativa $attempts para ${request.url}. Retentando...');
          await Future.delayed(
              Duration(milliseconds: 500 * attempts)); // Backoff simples
          continue;
        }
        debugPrint(
            '🌐 [TimeoutHttpClient] Timeout final (${timeoutDuration.inSeconds}s) atingido para ${request.url}');
        throw Exception(
            'A conexão demorou muito para responder (Timeout). Verifique a rede.');
      } catch (e) {
        if (canRetry && attempts <= maxRetries) {
          debugPrint(
              '🌐 [TimeoutHttpClient] Erro de rede na tentativa $attempts para ${request.url}: $e');
          await Future.delayed(Duration(milliseconds: 500 * attempts));
          continue;
        }
        rethrow;
      }
    }
  }

  http.BaseRequest _cloneRequest(http.BaseRequest request) {
    if (request is http.Request) {
      return http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..maxRedirects = request.maxRedirects
        ..followRedirects = request.followRedirects
        ..persistentConnection = request.persistentConnection
        ..bodyBytes = request.bodyBytes;
    }
    return http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..maxRedirects = request.maxRedirects
      ..followRedirects = request.followRedirects
      ..persistentConnection = request.persistentConnection;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
