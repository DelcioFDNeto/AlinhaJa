import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:alinha_ja/core/utils/friendly_error.dart';

/// As telas de RH mostravam a exceção crua ao usuário. `friendlyError` troca
/// o técnico por algo acionável e preserva as mensagens que já são para o
/// usuário (RAISE EXCEPTION das nossas funções, Exception('…') do app).
void main() {
  test('RLS negado vira "sem permissão", sem vazar detalhes do banco', () {
    final msg = friendlyError(const PostgrestException(
      message: 'new row violates row-level security policy for table "rh_holerite"',
      code: '42501',
    ));
    expect(msg, contains('não tem permissão'));
    expect(msg, isNot(contains('rh_holerite')));
  });

  test('42501 com frase nossa passa a frase adiante', () {
    expect(
      friendlyError(const PostgrestException(
          message: 'Apenas o RH pode excluir candidatos.', code: '42501')),
      'Apenas o RH pode excluir candidatos.',
    );
  });

  test('RAISE EXCEPTION (P0001) mantém a mensagem da função', () {
    expect(
      friendlyError(const PostgrestException(
          message: 'Saldo insuficiente para as férias.', code: 'P0001')),
      'Saldo insuficiente para as férias.',
    );
  });

  test('duplicidade e registro não encontrado', () {
    expect(friendlyError(const PostgrestException(message: 'x', code: '23505')),
        contains('Já existe'));
    expect(
        friendlyError(const PostgrestException(message: 'x', code: 'PGRST116')),
        'Registro não encontrado.');
  });

  test('Storage 403 vira "sem permissão"', () {
    expect(friendlyError(const StorageException('denied', statusCode: '403')),
        contains('não tem permissão'));
  });

  test('Edge Function devolve o `error` do corpo', () {
    expect(
      friendlyError(const FunctionException(
          status: 400, details: {'error': 'Informe o cargo.'})),
      'Informe o cargo.',
    );
  });

  test('falta de rede e timeout', () {
    expect(friendlyError(Exception('SocketException: Failed host lookup')),
        contains('Sem conexão'));
    expect(friendlyError(TimeoutException('x')), contains('demorou'));
  });

  test('Exception do app mantém a própria mensagem', () {
    expect(friendlyError(Exception('Selecione o funcionário.')),
        'Selecione o funcionário.');
  });

  test('erro desconhecido cai numa frase genérica', () {
    expect(friendlyError(StateError('boom')), contains('Não foi possível'));
  });
}
