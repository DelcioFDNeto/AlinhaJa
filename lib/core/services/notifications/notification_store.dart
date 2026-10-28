import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Uma linha da conversa exibida na notificação (estilo WhatsApp).
class NotificationLine {
  final String sender;
  final String? senderId;
  final String? avatarUrl;
  final String text;
  final int time;

  /// Mensagem enviada por quem está com o aparelho (resposta pela notificação).
  final bool fromMe;

  const NotificationLine({
    required this.sender,
    required this.text,
    required this.time,
    this.senderId,
    this.avatarUrl,
    this.fromMe = false,
  });

  Map<String, dynamic> toJson() => {
        'sender': sender,
        'text': text,
        'time': time,
        if (senderId != null) 'sender_id': senderId,
        if (avatarUrl != null) 'avatar': avatarUrl,
        if (fromMe) 'me': true,
      };

  /// Tolerante ao formato antigo do cache (`sender`, `text`, `time`).
  factory NotificationLine.fromJson(Map<String, dynamic> json) =>
      NotificationLine(
        sender: json['sender'] as String? ?? '',
        text: json['text'] as String? ?? '',
        time: (json['time'] as num?)?.toInt() ?? 0,
        senderId: json['sender_id'] as String?,
        avatarUrl: json['avatar'] as String?,
        fromMe: json['me'] == true,
      );
}

/// Resumo de uma conversa para a notificação agrupadora.
class ConversationDigest {
  final String chatId;
  final String title;
  final List<NotificationLine> lines;

  const ConversationDigest(this.chatId, this.title, this.lines);

  /// Mensagens recebidas (as respostas enviadas não contam como não lidas).
  int get unread => lines.where((l) => !l.fromMe).length;
}

/// Cache das conversas com notificação ativa.
///
/// Fica em SharedPreferences porque precisa ser compartilhado entre o app, o
/// isolate do FCM em segundo plano e o isolate das ações da notificação. Cada
/// isolate tem a sua instância de SharedPreferences com cache em memória: por
/// isso toda leitura chama `reload()` antes — sem isso o app, ao voltar para
/// o primeiro plano, sobrescrevia as mensagens gravadas em segundo plano.
class NotificationStore {
  NotificationStore._();

  static const maxLinesPerChat = 20;
  static const maxChats = 50;
  static const _activeKey = 'notif_active_chats';

  static String _linesKey(String chatId) => 'notif_cache_$chatId';
  static String _titleKey(String chatId) => 'notif_title_$chatId';
  static String _typeKey(String chatId) => 'notif_type_$chatId';
  static String _sourceKey(String chatId) => 'notif_src_$chatId';

  static Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  static Future<List<NotificationLine>> append(
    String chatId,
    NotificationLine line, {
    String? title,
    String? chatType,
    String? source,
  }) async {
    final prefs = await _prefs();
    final lines = _decode(prefs.getString(_linesKey(chatId)))..add(line);
    if (lines.length > maxLinesPerChat) {
      lines.removeRange(0, lines.length - maxLinesPerChat);
    }
    await prefs.setString(
        _linesKey(chatId), jsonEncode(lines.map((l) => l.toJson()).toList()));
    if (title != null) await prefs.setString(_titleKey(chatId), title);
    if (chatType != null) await prefs.setString(_typeKey(chatId), chatType);
    if (source != null) await prefs.setString(_sourceKey(chatId), source);

    // Conversa mais recente vai para o fim; as mais antigas saem do cache.
    final active = prefs.getStringList(_activeKey) ?? <String>[];
    active
      ..remove(chatId)
      ..add(chatId);
    if (active.length > maxChats) {
      final evicted = active.sublist(0, active.length - maxChats);
      active.removeRange(0, active.length - maxChats);
      for (final id in evicted) {
        await _removeChatKeys(prefs, id);
      }
    }
    await prefs.setStringList(_activeKey, active);
    return lines;
  }

  static Future<List<NotificationLine>> lines(String chatId) async {
    final prefs = await _prefs();
    return _decode(prefs.getString(_linesKey(chatId)));
  }

  static Future<String?> title(String chatId) async =>
      (await _prefs()).getString(_titleKey(chatId));

  static Future<String?> chatType(String chatId) async =>
      (await _prefs()).getString(_typeKey(chatId));

  static Future<String?> source(String chatId) async =>
      (await _prefs()).getString(_sourceKey(chatId));

  static Future<void> clear(String chatId) async {
    final prefs = await _prefs();
    await _removeChatKeys(prefs, chatId);
    final active = prefs.getStringList(_activeKey) ?? <String>[];
    active.remove(chatId);
    await prefs.setStringList(_activeKey, active);
  }

  /// Conversas ativas, da mais recente para a mais antiga.
  static Future<List<ConversationDigest>> digests() async {
    final prefs = await _prefs();
    final active = prefs.getStringList(_activeKey) ?? <String>[];
    final result = <ConversationDigest>[];
    for (final id in active.reversed) {
      final lines = _decode(prefs.getString(_linesKey(id)));
      if (lines.isEmpty) continue;
      result.add(ConversationDigest(
        id,
        prefs.getString(_titleKey(id)) ?? 'Conversa',
        lines,
      ));
    }
    return result;
  }

  static Future<void> _removeChatKeys(
      SharedPreferences prefs, String id) async {
    await prefs.remove(_linesKey(id));
    await prefs.remove(_titleKey(id));
    await prefs.remove(_typeKey(id));
    await prefs.remove(_sourceKey(id));
  }

  static List<NotificationLine> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <NotificationLine>[];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map>()
          .map((m) => NotificationLine.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      // Cache corrompido não pode derrubar a exibição da notificação.
      return <NotificationLine>[];
    }
  }
}

/// Texto do resumo agrupado, no formato do WhatsApp:
/// "5 mensagens de 2 conversas" / "1 mensagem".
String summaryText(List<ConversationDigest> digests) {
  final messages = digests.fold<int>(0, (sum, d) => sum + d.unread);
  final msgLabel = messages == 1 ? '1 mensagem' : '$messages mensagens';
  if (digests.length <= 1) return msgLabel;
  return '$msgLabel de ${digests.length} conversas';
}

/// Linha de uma conversa dentro do resumo: "Título: última mensagem".
String digestLine(ConversationDigest digest) {
  final last = digest.lines.last;
  final prefix = last.fromMe ? 'Você' : null;
  final text = prefix == null ? last.text : '$prefix: ${last.text}';
  return '${digest.title}: $text';
}
