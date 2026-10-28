import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado da seleção múltipla de mensagens de uma conversa ou canal.
class MessageSelection {
  /// Modo de seleção ligado. Fica ligado mesmo com [ids] vazio enquanto o
  /// usuário não sai, para a barra de ações não piscar ao desmarcar o último.
  final bool active;
  final Set<String> ids;

  const MessageSelection({this.active = false, this.ids = const {}});

  bool get isEmpty => ids.isEmpty;
  int get count => ids.length;
  bool contains(String id) => ids.contains(id);
}

/// Seleção múltipla, uma por conversa/canal (chave = chatId ou channelId).
///
/// Vive fora dos providers de mensagem porque DMs/grupos e canais usam
/// modelos diferentes mas exatamente o mesmo comportamento de seleção.
class MessageSelectionNotifier
    extends FamilyNotifier<MessageSelection, String> {
  @override
  MessageSelection build(String arg) => const MessageSelection();

  /// Entra no modo seleção já marcando [id] (gesto de long-press).
  void start(String id) {
    state = MessageSelection(active: true, ids: {id});
  }

  void toggle(String id) {
    final next = Set<String>.from(state.ids);
    if (!next.remove(id)) next.add(id);
    state = MessageSelection(active: true, ids: next);
  }

  void clear() {
    state = const MessageSelection();
  }
}

final messageSelectionProvider =
    NotifierProvider.family<MessageSelectionNotifier, MessageSelection, String>(
  MessageSelectionNotifier.new,
);
