import 'package:flutter/foundation.dart';

/// Em qual tabela a mensagem vive. É o `p_scope` do RPC
/// `get_message_receipts`.
enum ReceiptScope {
  chat,
  channel;

  String get rpcValue => name;
}

/// Situação de um destinatário em relação a uma mensagem.
///
/// A ordem das constantes é a ordem em que aparecem na folha: quem leu, quem
/// recebeu, quem ainda não.
enum ReceiptState {
  read,
  delivered,
  pending;

  static ReceiptState parse(String? raw) => switch (raw) {
        'read' => ReceiptState.read,
        'delivered' => ReceiptState.delivered,
        _ => ReceiptState.pending,
      };
}

/// Uma pessoa da conversa e o que aconteceu com a mensagem para ela.
@immutable
class MessageReceipt {
  final String userId;
  final String fullName;
  final String? avatarUrl;
  final ReceiptState state;

  /// Quando o estado foi atingido. `null` em quem ainda não recebeu.
  ///
  /// É um carimbo de sessão ("última vez que abriu"), não o instante exato da
  /// leitura — a UI mostra a hora sem prometer precisão maior que essa.
  final DateTime? at;

  const MessageReceipt({
    required this.userId,
    required this.fullName,
    this.avatarUrl,
    required this.state,
    this.at,
  });

  factory MessageReceipt.fromJson(Map<String, dynamic> json) => MessageReceipt(
        userId: json['user_id']?.toString() ?? '',
        fullName: json['full_name']?.toString().trim().isNotEmpty == true
            ? json['full_name'].toString()
            : 'Usuário',
        avatarUrl: json['avatar_url']?.toString(),
        state: ReceiptState.parse(json['state']?.toString()),
        at: json['at'] != null
            ? DateTime.tryParse(json['at'].toString())?.toLocal()
            : null,
      );
}

/// Resposta completa do RPC: contagens do cabeçalho + lista nominal.
@immutable
class MessageReceiptSummary {
  final String messageId;
  final ReceiptScope scope;
  final String? senderId;
  final DateTime? sentAt;

  /// Total de destinatários (todos os membros menos quem enviou).
  final int recipientCount;
  final int readCount;
  final int deliveredCount;
  final int pendingCount;

  final List<MessageReceipt> recipients;

  const MessageReceiptSummary({
    required this.messageId,
    required this.scope,
    this.senderId,
    this.sentAt,
    required this.recipientCount,
    required this.readCount,
    required this.deliveredCount,
    required this.pendingCount,
    required this.recipients,
  });

  /// Conversa de duas pessoas: a folha troca "3 de 8 leram" por uma frase.
  bool get isOneToOne => recipientCount == 1;

  bool get everyoneRead => recipientCount > 0 && readCount == recipientCount;

  List<MessageReceipt> whereState(ReceiptState state) =>
      recipients.where((r) => r.state == state).toList(growable: false);

  factory MessageReceiptSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['recipients'];

    return MessageReceiptSummary(
      messageId: json['message_id']?.toString() ?? '',
      scope: json['scope']?.toString() == 'channel'
          ? ReceiptScope.channel
          : ReceiptScope.chat,
      senderId: json['sender_id']?.toString(),
      sentAt: json['sent_at'] != null
          ? DateTime.tryParse(json['sent_at'].toString())?.toLocal()
          : null,
      recipientCount: (json['recipient_count'] as num?)?.toInt() ?? 0,
      readCount: (json['read_count'] as num?)?.toInt() ?? 0,
      deliveredCount: (json['delivered_count'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
      recipients: raw is List
          ? raw
              .whereType<Map>()
              .map((r) => MessageReceipt.fromJson(Map<String, dynamic>.from(r)))
              .toList(growable: false)
          : const [],
    );
  }
}
