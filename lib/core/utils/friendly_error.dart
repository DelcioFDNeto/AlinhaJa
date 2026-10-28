import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Frase para o usuário a partir de uma exceção técnica.
///
/// As telas mostravam o erro cru (`PostgrestException(message: new row
/// violates row-level security policy…, code: 42501…)`). Aqui ele vira algo
/// que dá para entender e agir. Mensagens que já são para o usuário — o
/// `RAISE EXCEPTION` das nossas funções e o `Exception('…')` do próprio app —
/// passam como estão.
///
/// Sem `dart:io`: o app também compila para web, então falha de rede é
/// reconhecida pelo texto.
String friendlyError(Object error) {
  if (error is PostgrestException) return _postgrest(error);

  if (error is StorageException) {
    switch (error.statusCode) {
      case '401':
      case '403':
        return _semPermissao;
      case '404':
        return 'Arquivo não encontrado.';
      case '413':
        return 'Arquivo grande demais para enviar.';
    }
    return 'Não foi possível acessar o arquivo. Tente novamente.';
  }

  if (error is AuthException) {
    return 'Sua sessão expirou. Entre novamente.';
  }

  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    if (error.status == 401 || error.status == 403) return _semPermissao;
  }

  if (error is TimeoutException) return _lento;

  final text = error.toString();
  if (_rede.any(text.contains)) {
    return 'Sem conexão com o servidor. Verifique a internet e tente novamente.';
  }

  // `throw Exception('…')` do app: a mensagem já foi escrita para o usuário.
  const prefix = 'Exception: ';
  if (text.startsWith(prefix)) {
    final inner = text.substring(prefix.length);
    if (inner.isNotEmpty && !inner.contains('Exception(')) return inner;
  }

  return _generico;
}

const _semPermissao =
    'Você não tem permissão para esta ação. Fale com quem administra os '
    'perfis de acesso.';
const _lento = 'A conexão demorou demais. Tente novamente.';
const _generico = 'Não foi possível concluir. Tente novamente.';

const _rede = [
  'SocketException',
  'Failed host lookup',
  'ClientException',
  'Connection closed',
  'Connection refused',
  'Network is unreachable',
  'XMLHttpRequest error',
];

String _postgrest(PostgrestException e) {
  switch (e.code) {
    case '42501':
      // Nossas funções usam 42501 com frase própria; a do RLS é técnica.
      final tecnica = e.message.contains('row-level security') ||
          e.message.contains('permission denied');
      return tecnica ? _semPermissao : e.message;
    case 'P0001':
      return e.message;
    case '23505':
      return 'Já existe um registro com esses dados.';
    case '23503':
      return 'Não dá para concluir: há registros vinculados a este.';
    case '23502':
    case '23514':
    case '22P02':
      return 'Algum dado informado é inválido. Revise e tente de novo.';
    case 'PGRST116':
      return 'Registro não encontrado.';
    case 'PGRST301':
      return 'Sua sessão expirou. Entre novamente.';
  }
  return _generico;
}
