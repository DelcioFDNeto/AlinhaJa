import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ids das ações da notificação de conversa.
const kReplyActionId = 'reply';
const kMarkReadActionId = 'mark_read';

/// Tabela de origem da conversa: define para onde vai a resposta.
enum ConversationSource { messages, channelMessages }

ConversationSource sourceFor({String? table, String? chatType}) {
  if (table == 'channel_messages') return ConversationSource.channelMessages;
  if (table == 'messages') return ConversationSource.messages;
  // Payload antigo sem `conversation_table`: mesmo critério do roteamento.
  return chatType == 'channel'
      ? ConversationSource.channelMessages
      : ConversationSource.messages;
}

/// Operações que as ações da notificação executam no backend.
abstract class ConversationGateway {
  Future<void> sendText(
      String conversationId, ConversationSource source, String text);
  Future<void> markRead(String conversationId, ConversationSource source);
}

/// Executa pelo cliente Supabase vivo do isolate principal. É o caminho
/// preferido: o gotrue desse cliente é quem renova a sessão.
class SupabaseClientGateway implements ConversationGateway {
  final SupabaseClient client;
  SupabaseClientGateway(this.client);

  String get _uid {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('Sessão encerrada');
    return id;
  }

  @override
  Future<void> sendText(
      String conversationId, ConversationSource source, String text) async {
    final uid = _uid;
    if (source == ConversationSource.channelMessages) {
      await client.from('channel_messages').insert({
        'channel_id': conversationId,
        'sender_id': uid,
        'content': text,
        'content_type': 'text',
      });
    } else {
      await client.from('messages').insert({
        'chat_id': conversationId,
        'sender_id': uid,
        'content': text,
        'content_type': 'text',
      });
    }
  }

  @override
  Future<void> markRead(
      String conversationId, ConversationSource source) async {
    final uid = _uid;
    final now = DateTime.now().toUtc().toIso8601String();
    if (source == ConversationSource.channelMessages) {
      await client
          .from('channel_members')
          .update({'last_read_at': now, 'unread_count': 0})
          .eq('channel_id', conversationId)
          .eq('user_id', uid);
    } else {
      await client
          .from('chat_members')
          .update({'last_read_at': now})
          .eq('chat_id', conversationId)
          .eq('user_id', uid);
      await client.rpc('mark_messages_as_read',
          params: {'p_chat_id': conversationId, 'p_user_id': uid});
    }
  }
}

/// Sessão persistida pelo supabase_flutter em SharedPreferences.
class StoredSession {
  final Map<String, dynamic> raw;
  StoredSession(this.raw);

  String? get accessToken => raw['access_token'] as String?;
  String? get refreshToken => raw['refresh_token'] as String?;
  String? get userId => (raw['user'] as Map?)?['id'] as String?;
  int? get expiresAt => (raw['expires_at'] as num?)?.toInt();

  /// Mesma chave que o supabase_flutter usa (`supabase.dart`).
  static String storageKey(String supabaseUrl) =>
      'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

  static StoredSession? parse(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final map = jsonDecode(value);
      if (map is! Map) return null;
      final session = StoredSession(Map<String, dynamic>.from(map));
      if (session.accessToken == null || session.userId == null) return null;
      return session;
    } catch (_) {
      return null;
    }
  }

  /// Expirado ou perto de expirar: a requisição levaria 401 no meio do envio.
  bool isExpired(DateTime now,
      {Duration leeway = const Duration(seconds: 60)}) {
    final exp = expiresAt;
    if (exp == null) return true;
    return now.add(leeway).millisecondsSinceEpoch ~/ 1000 >= exp;
  }
}

/// Executa via REST com a sessão salva no aparelho.
///
/// Usado só quando o app NÃO está rodando (nenhum isolate principal
/// respondeu). Nesse caso é seguro renovar o token aqui e gravar a sessão
/// nova no mesmo lugar: o app lê dali na próxima abertura. Com o app aberto a
/// renovação ficaria em dois lugares e a detecção de reuso de refresh token do
/// Supabase derrubaria a sessão — por isso esse caso vai pelo
/// [SupabaseClientGateway].
class RestSessionGateway implements ConversationGateway {
  final String supabaseUrl;
  final String anonKey;
  final http.Client _http;

  RestSessionGateway({
    required this.supabaseUrl,
    required this.anonKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static const _timeout = Duration(seconds: 15);

  Future<StoredSession> _session() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final key = StoredSession.storageKey(supabaseUrl);
    final session = StoredSession.parse(prefs.getString(key));
    if (session == null) throw StateError('Sessão encerrada');
    if (!session.isExpired(DateTime.now())) return session;

    final refresh = session.refreshToken;
    if (refresh == null) throw StateError('Sessão expirada');
    final resp = await _http
        .post(
          Uri.parse('$supabaseUrl/auth/v1/token?grant_type=refresh_token'),
          headers: {'apikey': anonKey, 'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refresh}),
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw StateError('Falha ao renovar sessão (${resp.statusCode})');
    }
    final fresh = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    fresh['expires_at'] ??= DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        ((fresh['expires_in'] as num?)?.toInt() ?? 3600);
    final renewed = StoredSession(fresh);
    if (renewed.accessToken == null || renewed.userId == null) {
      throw StateError('Resposta de renovação inválida');
    }
    await prefs.setString(key, jsonEncode(fresh));
    return renewed;
  }

  Map<String, String> _headers(StoredSession s) => {
        'apikey': anonKey,
        'Authorization': 'Bearer ${s.accessToken}',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      };

  Future<void> _check(Future<http.Response> request) async {
    final resp = await request.timeout(_timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError('HTTP ${resp.statusCode}: ${resp.body}');
    }
  }

  @override
  Future<void> sendText(
      String conversationId, ConversationSource source, String text) async {
    final s = await _session();
    final isChannel = source == ConversationSource.channelMessages;
    await _check(_http.post(
      Uri.parse(
          '$supabaseUrl/rest/v1/${isChannel ? 'channel_messages' : 'messages'}'),
      headers: _headers(s),
      body: jsonEncode({
        isChannel ? 'channel_id' : 'chat_id': conversationId,
        'sender_id': s.userId,
        'content': text,
        'content_type': 'text',
      }),
    ));
  }

  @override
  Future<void> markRead(
      String conversationId, ConversationSource source) async {
    final s = await _session();
    final now = DateTime.now().toUtc().toIso8601String();
    final uid = Uri.encodeQueryComponent(s.userId!);
    final cid = Uri.encodeQueryComponent(conversationId);
    if (source == ConversationSource.channelMessages) {
      await _check(_http.patch(
        Uri.parse(
            '$supabaseUrl/rest/v1/channel_members?channel_id=eq.$cid&user_id=eq.$uid'),
        headers: _headers(s),
        body: jsonEncode({'last_read_at': now, 'unread_count': 0}),
      ));
    } else {
      await _check(_http.patch(
        Uri.parse(
            '$supabaseUrl/rest/v1/chat_members?chat_id=eq.$cid&user_id=eq.$uid'),
        headers: _headers(s),
        body: jsonEncode({'last_read_at': now}),
      ));
      await _check(_http.post(
        Uri.parse('$supabaseUrl/rest/v1/rpc/mark_messages_as_read'),
        headers: _headers(s),
        body: jsonEncode({'p_chat_id': conversationId, 'p_user_id': s.userId}),
      ));
    }
  }
}
