import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/models/message_ref.dart';
import 'package:alinha_ja/core/supabase_client.dart';

/// Votos e confirmações vivem em `message_actions`, uma tabela genérica
/// (message_id OU channel_message_id + action_type + action_value). Os
/// providers ficam aqui para que chat e canais leiam a mesma fonte com o mesmo
/// formato — a [MessageRef] diz em qual das duas colunas gravar.

/// Em enquetes de múltipla escolha as opções marcadas vão em uma linha só,
/// separadas por este caractere de controle: existe no máximo uma ação de cada
/// tipo por usuário por mensagem.
final String kPollVoteSeparator = String.fromCharCode(1);

List<String> decodePollVote(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  return raw.split(kPollVoteSeparator).where((v) => v.isNotEmpty).toList();
}

String encodePollVote(Iterable<String> options) =>
    options.join(kPollVoteSeparator);

/// Opções que o usuário atual marcou nesta enquete.
final pollMyVoteProvider =
    FutureProvider.family<List<String>, MessageRef>((ref, message) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return const [];

  final result = await supabase
      .from('message_actions')
      .select('action_value')
      .eq(message.actionColumn, message.id)
      .eq('user_id', myId)
      .eq('action_type', 'poll_vote')
      .maybeSingle();

  return decodePollVote(result?['action_value'] as String?);
});

/// Contagem ao vivo por opção.
final pollResultsProvider =
    StreamProvider.family<Map<String, int>, MessageRef>((ref, message) {
  return supabase
      .from('message_actions')
      .stream(primaryKey: ['id'])
      .eq(message.actionColumn, message.id)
      .map((rows) {
        final counts = <String, int>{};
        for (final row in rows) {
          if (row['action_type'] != 'poll_vote') continue;
          for (final option in decodePollVote(row['action_value'] as String?)) {
            counts[option] = (counts[option] ?? 0) + 1;
          }
        }
        return counts;
      });
});

/// Se o usuário atual já confirmou a leitura desta mensagem.
///
/// Vale para as duas origens: antes existia só a versão de canal, então
/// anúncio em grupo não tinha como registrar ciência.
final messageAckedProvider =
    FutureProvider.family<bool, MessageRef>((ref, message) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return false;

  final result = await supabase
      .from('message_actions')
      .select('id')
      .eq(message.actionColumn, message.id)
      .eq('user_id', myId)
      .eq('action_type', 'acknowledge')
      .maybeSingle();

  return result != null;
});

/// Quem já confirmou, em ordem de confirmação.
final messageAckedByProvider =
    FutureProvider.family<List<Map<String, dynamic>>, MessageRef>(
        (ref, message) async {
  final result = await supabase
      .from('message_actions')
      .select('user_id, created_at')
      .eq(message.actionColumn, message.id)
      .eq('action_type', 'acknowledge')
      .order('created_at', ascending: true);

  return List<Map<String, dynamic>>.from(result);
});

/// Grava (ou substitui) uma ação do usuário atual sobre a mensagem.
///
/// Apaga antes de inserir em vez de usar UPSERT: a unicidade agora vem de dois
/// índices *parciais* (um por coluna de origem), e o `on_conflict` do PostgREST
/// não consegue mirar índice parcial — o Postgres exigiria o predicado do
/// índice, que a API REST não expõe. Duas chamadas resolvem sem depender de
/// inferência, e a policy de DELETE já permite remover as próprias ações.
Future<void> setMessageAction(
  MessageRef message, {
  required String actionType,
  String? value,
}) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return;

  await supabase
      .from('message_actions')
      .delete()
      .eq(message.actionColumn, message.id)
      .eq('user_id', myId)
      .eq('action_type', actionType);

  if (value == null) return;

  await supabase.from('message_actions').insert({
    message.actionColumn: message.id,
    'user_id': myId,
    'action_type': actionType,
    'action_value': value,
  });
}

/// Registra (ou troca) o voto do usuário atual. Lista vazia retira o voto.
Future<void> submitPollVote(MessageRef message, List<String> options) {
  return setMessageAction(
    message,
    actionType: 'poll_vote',
    value: options.isEmpty ? null : encodePollVote(options),
  );
}
