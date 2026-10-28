import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import 'package:alinha_ja/core/supabase_client.dart';

/// Cliente do Portal do Candidato (RH-2) — todas as chamadas passam pela
/// Edge Function `rh-candidatura` (nenhum acesso anônimo direto às tabelas).
class CandidatePortalService {
  const CandidatePortalService();

  Future<Map<String, dynamic>> _invoke(
    Map<String, dynamic> body, {
    String? sessionToken,
  }) async {
    try {
      final res = await supabase.functions.invoke(
        'rh-candidatura',
        body: body,
        headers: sessionToken != null
            ? {'Authorization': 'Bearer $sessionToken'}
            : null,
      );
      return (res.data as Map).cast<String, dynamic>();
    } on FunctionException catch (e) {
      final data = e.details;
      final msg = data is Map && data['error'] != null
          ? data['error'] as String
          : 'Erro de comunicação com o servidor.';
      throw PortalException(msg, e.status);
    }
  }

  /// Dados públicos da empresa da página de carreiras.
  Future<Map<String, dynamic>> fetchOrg(String slug) =>
      _invoke({'action': 'org', 'slug': slug});

  /// Envia a candidatura. Ou anexa o currículo em [cvBytes], ou reaproveita
  /// o último currículo da conta ([reusarCv], exige [sessionToken] — Fase 7).
  ///
  /// Retorna o token da área do candidato e se o e-mail de confirmação
  /// saiu — a tela de confirmação usa os dois para não deixar o candidato
  /// sem caminho quando o SMTP falha (ou quando DEV_EMAIL_OVERRIDE desvia
  /// o e-mail em ambiente de desenvolvimento).
  Future<ApplyResult> apply({
    required String slug,
    required Map<String, dynamic> fields,
    Uint8List? cvBytes,
    bool reusarCv = false,
    String? sessionToken,
  }) async {
    assert(reusarCv || cvBytes != null,
        'Sem reuso, o currículo precisa ser anexado.');
    final res = await _invoke(
      {
        'action': 'apply',
        'slug': slug,
        ...fields,
        'consentimento_lgpd': true,
        if (reusarCv)
          'reusar_cv': true
        else
          'cv_base64': base64Encode(cvBytes!),
      },
      sessionToken: sessionToken,
    );
    return ApplyResult(
      token: res['token'] as String?,
      emailEnviado: res['email_enviado'] == true,
    );
  }

  /// Área do candidato: status + mensagens.
  Future<Map<String, dynamic>> fetchStatus(String token) =>
      _invoke({'action': 'status', 'token': token});

  /// Candidato envia mensagem ao RH.
  Future<void> sendMessage(String token, String texto) async {
    await _invoke({'action': 'message', 'token': token, 'texto': texto});
  }

  /// Inicia a avaliação técnica do candidato (RH-12). Retorna:
  /// `{ avaliacao_id, questoes:[{id,enunciado,opcoes}] }`,
  /// `{ disponivel:false }` (sem banco de questões) ou
  /// `{ ja_feita:true, nota }` (já respondida).
  Future<Map<String, dynamic>> avaliacaoIniciar(String token) =>
      _invoke({'action': 'avaliacao_iniciar', 'token': token});

  /// Envia as respostas; a correção é 100% server-side. Retorna
  /// `{ nota, acertos, total }`.
  Future<Map<String, dynamic>> avaliacaoEnviar({
    required String token,
    required String avaliacaoId,
    required List<Map<String, dynamic>> respostas,
  }) =>
      _invoke({
        'action': 'avaliacao_enviar',
        'token': token,
        'avaliacao_id': avaliacaoId,
        'respostas': respostas,
      });

  /// Candidato envia documento adicional.
  Future<void> uploadDocument({
    required String token,
    required Uint8List bytes,
    required String fileName,
  }) async {
    await _invoke({
      'action': 'upload',
      'token': token,
      'base64': base64Encode(bytes),
      'nome': fileName,
    });
  }
}

/// Resultado do envio de candidatura.
class ApplyResult {
  /// Token da área do candidato (`/candidato/<token>`).
  final String? token;

  /// O e-mail de confirmação saiu de fato. `false` quando o SMTP não está
  /// configurado, falhou, ou o ambiente desviou a mensagem.
  final bool emailEnviado;

  const ApplyResult({this.token, this.emailEnviado = false});
}

class PortalException implements Exception {
  final String message;
  final int? status;
  const PortalException(this.message, [this.status]);

  @override
  String toString() => message;
}
