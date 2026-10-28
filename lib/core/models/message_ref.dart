import 'package:flutter/foundation.dart';

/// Aponta para uma mensagem em qualquer das duas tabelas do app.
///
/// `messages` guarda chat 1:1 e grupo; `channel_messages` guarda canal e
/// thread de canal. Como `message_actions` (votos e confirmações) agora tem
/// uma coluna para cada origem, quem grava precisa dizer de qual delas veio o
/// id — só o UUID não basta.
@immutable
class MessageRef {
  final String id;
  final bool isChannel;

  const MessageRef.chat(this.id) : isChannel = false;
  const MessageRef.channel(this.id) : isChannel = true;

  /// Coluna de `message_actions` que referencia esta mensagem.
  String get actionColumn => isChannel ? 'channel_message_id' : 'message_id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRef && other.id == id && other.isChannel == isChannel);

  @override
  int get hashCode => Object.hash(id, isChannel);

  @override
  String toString() => '${isChannel ? 'channel' : 'chat'}:$id';
}
