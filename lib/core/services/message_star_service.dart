import 'package:alinha_ja/core/supabase_client.dart';

/// Resultado de um favoritar em lote, para a UI poder dar o retorno certo.
class StarBatchResult {
  final int added;
  final int removed;

  const StarBatchResult({this.added = 0, this.removed = 0});

  bool get isEmpty => added == 0 && removed == 0;
}

/// Favoritos de mensagens, de conversas e de canais.
///
/// `starred_messages` guarda a origem em duas colunas exclusivas
/// (`chat_message_id` x `channel_message_id`), então tudo aqui recebe
/// [isChannel] para escolher a coluna certa.
class MessageStarService {
  static String _column(bool isChannel) =>
      isChannel ? 'channel_message_id' : 'chat_message_id';

  /// IDs, dentre [messageIds], que o usuário atual já favoritou.
  static Future<Set<String>> fetchStarred(
    Iterable<String> messageIds, {
    required bool isChannel,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    final ids = messageIds.toList();
    if (userId == null || ids.isEmpty) return {};

    final column = _column(isChannel);
    final rows = await supabase
        .from('starred_messages')
        .select(column)
        .eq('user_id', userId)
        .inFilter(column, ids);

    return {
      for (final row in (rows as List))
        if (row[column] != null) row[column].toString(),
    };
  }

  /// Alterna o favorito de um conjunto de mensagens.
  ///
  /// Se todas já estiverem favoritadas, desfavorita todas; caso contrário
  /// favorita as que faltam. É o comportamento que o usuário espera de um
  /// botão único de estrela agindo sobre uma seleção mista.
  static Future<StarBatchResult> toggleAll(
    Iterable<String> messageIds, {
    required String scopeId,
    required bool isChannel,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    final ids = messageIds.toSet().toList();
    if (userId == null || ids.isEmpty) return const StarBatchResult();

    final column = _column(isChannel);
    final alreadyStarred = await fetchStarred(ids, isChannel: isChannel);

    if (alreadyStarred.length == ids.length) {
      await supabase
          .from('starred_messages')
          .delete()
          .eq('user_id', userId)
          .inFilter(column, ids);
      return StarBatchResult(removed: ids.length);
    }

    final missing = ids.where((id) => !alreadyStarred.contains(id)).toList();
    if (missing.isEmpty) return const StarBatchResult();

    await supabase.from('starred_messages').insert([
      for (final id in missing)
        {
          'user_id': userId,
          column: id,
          'chat_id': scopeId,
        }
    ]);

    return StarBatchResult(added: missing.length);
  }
}
