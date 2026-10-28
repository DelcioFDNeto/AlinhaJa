import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/models/message_receipts.dart';
import 'package:alinha_ja/core/supabase_client.dart';

/// Identifica a mensagem cujos recibos serão buscados.
///
/// Chat e canal guardam mensagem em tabelas diferentes, e o id sozinho não
/// diz qual delas — daí o escopo viajar junto na chave do provider.
@immutable
class MessageReceiptArgs {
  final String messageId;
  final ReceiptScope scope;

  const MessageReceiptArgs({required this.messageId, required this.scope});

  @override
  bool operator ==(Object other) =>
      other is MessageReceiptArgs &&
      other.messageId == messageId &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(messageId, scope);
}

/// Quem recebeu e quem leu uma mensagem.
///
/// Busca sob demanda, ao abrir a folha de informações: manter isto ao vivo
/// para toda mensagem da tela custaria uma consulta por bolha e não mudaria
/// nada do que já é visível nos checks.
final messageReceiptsProvider = FutureProvider.family<MessageReceiptSummary,
    MessageReceiptArgs>((ref, args) async {
  final response = await supabase.rpc(
    'get_message_receipts',
    params: {
      'p_message_id': args.messageId,
      'p_scope': args.scope.rpcValue,
    },
  );

  if (response is! Map) {
    throw StateError('Resposta inesperada de get_message_receipts');
  }

  return MessageReceiptSummary.fromJson(Map<String, dynamic>.from(response));
});
