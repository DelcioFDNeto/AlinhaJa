import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/services/offline_cache_service.dart';
import 'package:alinha_ja/core/services/sync_service.dart';

/// Uma classe utilitária para interceptar exceções (AppException)
/// Em uma implementação futura mais robusta, isso chamaria um SnackBar global
/// ou enviaria erros estruturados para um Sentry/Crashlytics.
class ErrorHandler {
  static void logError(String message,
      [dynamic error, StackTrace? stackTrace]) {
    log('❌ [ERROR] $message', error: error, stackTrace: stackTrace);
  }

  static String handleSupabaseError(dynamic error) {
    if (error is PostgrestException) {
      if (error.code == 'PGRST116') return 'Registro não encontrado.';
      if (error.code == '23505') return 'Registro duplicado.';
      return 'Erro no banco de dados: ${error.message}';
    }
    if (error is AuthException) {
      return 'Erro de autenticação: ${error.message}';
    }
    return 'Erro desconhecido de conexão. Tente novamente.';
  }
}

/// Provider do ChatRepository para podermos injetar futuramente no Notifier
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(supabase);
});

class ChatRepository {
  final SupabaseClient _client;

  ChatRepository(this._client);

  /// Página de mensagens, da mais nova para a mais antiga. [olderThan] pagina
  /// para trás; [newerThan] traz só o que chegou depois (recuperação do
  /// realtime).
  Future<List<MessageModel>> loadMessages(String chatId,
      {DateTime? olderThan, DateTime? newerThan, String? threadId}) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;

      if (!SyncService().isConnected && olderThan == null && newerThan == null) {
        log('📡 [ChatRepository] Sem conexão. Carregando mensagens do Cache (Hive).');
        final cached = OfflineCacheService.getCachedMessages(chatId);
        if (cached != null) return cached;
      }

      var query = _client.from('messages').select('''
            *,
            sender:users(id, full_name, avatar_url),
            acks:message_actions!left(user_id, action_type)
          ''').eq('chat_id', chatId);

      if (threadId != null) {
        query = query.eq('thread_id', threadId);
      } else {
        query = query.isFilter('thread_id', null);
      }

      if (olderThan != null) {
        query = query.lt('created_at', olderThan.toIso8601String());
      }
      if (newerThan != null) {
        query = query.gt('created_at', newerThan.toUtc().toIso8601String());
      }

      final data = await query
          .order('created_at', ascending: false)
          .limit(AppConstants.messagesPerPage);

      final parsedList = (data as List).map((e) {
        final hasAck = (e['acks'] as List?)?.any((ack) =>
                ack['user_id'] == currentUserId &&
                ack['action_type'] == 'acknowledge') ??
            false;
        return MessageModel.fromJson(e).copyWith(
          acknowledgedByMe: hasAck,
        );
      }).toList();

      // Só a página mais recente COMPLETA vira cache offline.
      if (threadId == null &&
          olderThan == null &&
          newerThan == null &&
          parsedList.isNotEmpty) {
        OfflineCacheService.cacheMessages(chatId, parsedList);
      }

      return parsedList;
    } catch (e, st) {
      ErrorHandler.logError(
          'Erro ao carregar mensagens do chat $chatId', e, st);
      throw Exception(ErrorHandler.handleSupabaseError(e));
    }
  }

  Future<MessageModel> getSingleMessage(String messageId) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      final query = _client.from('messages').select('''
            *,
            sender:users(id, full_name, avatar_url),
            acks:message_actions!left(user_id, action_type)
          ''').eq('id', messageId);

      final fullMsgRes = await query.maybeSingle();
      if (fullMsgRes == null) {
        throw Exception('Mensagem não encontrada');
      }

      final hasAck = (fullMsgRes['acks'] as List?)?.any((ack) =>
              ack['user_id'] == currentUserId &&
              ack['action_type'] == 'acknowledge') ??
          false;
      return MessageModel.fromJson(fullMsgRes).copyWith(
        acknowledgedByMe: hasAck,
      );
    } catch (e, st) {
      ErrorHandler.logError(
          'Erro ao carregar mensagem única $messageId', e, st);
      throw Exception(ErrorHandler.handleSupabaseError(e));
    }
  }

  Future<List<MessageModel>> getMessagesBatch(List<String> messageIds) async {
    if (messageIds.isEmpty) return [];
    try {
      final currentUserId = _client.auth.currentUser?.id;
      final query = _client.from('messages').select('''
            *,
            sender:users(id, full_name, avatar_url),
            acks:message_actions!left(user_id, action_type)
          ''').inFilter('id', messageIds);

      final fullMsgRes = await query;

      final parsedList = (fullMsgRes as List).map((e) {
        final hasAck = (e['acks'] as List?)?.any((ack) =>
                ack['user_id'] == currentUserId &&
                ack['action_type'] == 'acknowledge') ??
            false;
        return MessageModel.fromJson(e).copyWith(
          acknowledgedByMe: hasAck,
        );
      }).toList();
      return parsedList;
    } catch (e, st) {
      ErrorHandler.logError('Erro ao carregar mensagens em lote', e, st);
      throw Exception(ErrorHandler.handleSupabaseError(e));
    }
  }

  Future<void> acknowledgeMessage(String messageId, String userId) async {
    try {
      // message_actions já é genérica, o UI pode fazer o ciente usando o provedor direto
      // Se necessário centralizar:
      await _client.from('message_actions').insert({
        'message_id': messageId,
        'user_id': userId,
        'action_type': 'acknowledge',
        'action_value': 'confirmed'
      });
    } catch (e, st) {
      ErrorHandler.logError('Erro ao dar ciente na mensagem $messageId', e, st);
      throw Exception(ErrorHandler.handleSupabaseError(e));
    }
  }

  Future<void> softDeleteMessage(String messageId) async {
    try {
      await _client
          .from('messages')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq(
              'id', messageId);
    } catch (e, st) {
      ErrorHandler.logError('Erro ao deletar mensagem $messageId', e, st);
      throw Exception(ErrorHandler.handleSupabaseError(e));
    }
  }

  Future<Map<String, dynamic>> insertMessage(Map<String, dynamic> payload,
      {String? tempId}) async {
    try {
      if (!SyncService().isConnected) {
        log('📡 [ChatRepository] Offline. Colocando mensagem enviada na fila (Sync Queue).');

        final syntheticId = tempId ??
            payload['id'] ??
            DateTime.now().millisecondsSinceEpoch.toString();

        await OfflineCacheService.enqueueOperation({
          'temp_id': syntheticId,
          'type': 'insert_message',
          'payload': payload,
        });

        // Retorna um espelho sintético simulando retorno db
        payload['id'] = syntheticId;
        if (!payload.containsKey('created_at')) {
          payload['created_at'] = DateTime.now().toUtc().toIso8601String();
        }

        return payload;
      }

      final result =
          await _client.from('messages').insert(payload).select().single();

      return result;
    } catch (e, st) {
      ErrorHandler.logError('Erro ao enviar mensagem', e, st);
      throw Exception(ErrorHandler.handleSupabaseError(e));
    }
  }

  Future<void> markAsRead(String chatId, String userId) async {
    try {
      // Atualiza o last_read_at da sessão do membro
      await _client
          .from('chat_members')
          .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('chat_id', chatId)
          .eq('user_id', userId);

      // Marca visualmente as mensagens como lidas (Double Ticks + Array ReadBy) usando a RPC optimizada
      await _client.rpc('mark_messages_as_read', params: {
        'p_chat_id': chatId,
        'p_user_id': userId,
      });
    } catch (e, st) {
      ErrorHandler.logError('Erro ao marcar chat $chatId como lido', e, st);
    }
  }

  Future<DateTime?> fetchLatestReadByOthers(
      String chatId, String currentUserId) async {
    try {
      final rows = await _client
          .from('chat_members')
          .select('last_read_at')
          .eq('chat_id', chatId)
          .neq('user_id', currentUserId)
          .not('last_read_at', 'is', null)
          .order('last_read_at', ascending: false)
          .limit(1);

      if ((rows as List).isNotEmpty) {
        final lra = rows.first['last_read_at'] as String?;
        if (lra != null) return DateTime.parse(lra);
      }
      return null;
    } catch (e, st) {
      ErrorHandler.logError(
          'Erro ao buscar recibos de leitura do chat $chatId', e, st);
      return null;
    }
  }

  /// Busca as reações de uma lista de mensagens (batch).
  Future<Map<String, List<Map<String, dynamic>>>> fetchReactions(
      List<String> messageIds) async {
    if (messageIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('message_reactions')
          .select('message_id, user_id, emoji')
          .inFilter('message_id', messageIds);

      final result = <String, List<Map<String, dynamic>>>{};
      for (final r in (rows as List)) {
        final msgId = r['message_id'] as String;
        result.putIfAbsent(msgId, () => []).add(Map<String, dynamic>.from(r));
      }
      return result;
    } catch (e, st) {
      ErrorHandler.logError('Erro ao buscar reações', e, st);
      return {};
    }
  }

  /// Insere ou remove uma reação (toggle).
  Future<bool> toggleReaction(
      String messageId, String userId, String emoji) async {
    try {
      // Tenta remover primeiro
      final deleted = await _client
          .from('message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', userId)
          .eq('emoji', emoji)
          .select();

      if ((deleted as List).isNotEmpty) return false; // Removeu

      // Se não existia, insere
      await _client.from('message_reactions').insert({
        'message_id': messageId,
        'user_id': userId,
        'emoji': emoji,
      });
      return true; // Adicionou
    } catch (e, st) {
      ErrorHandler.logError('Erro ao alternar reação', e, st);
      return false;
    }
  }

  /// Fixa ou desfixa uma mensagem no chat.
  Future<void> pinMessage(String chatId, String? messageId) async {
    try {
      await _client
          .from('chats')
          .update({'pinned_message_id': messageId}).eq('id', chatId);
    } catch (e, st) {
      ErrorHandler.logError('Erro ao fixar mensagem no chat $chatId', e, st);
    }
  }

  /// Busca a mensagem fixada de um chat.
  Future<Map<String, dynamic>?> fetchPinnedMessage(String chatId) async {
    try {
      final chat = await _client
          .from('chats')
          .select('pinned_message_id')
          .eq('id', chatId)
          .maybeSingle();

      if (chat == null) return null;

      final pinnedId = chat['pinned_message_id'] as String?;
      if (pinnedId == null) return null;

      return await _client
          .from('messages')
          .select()
          .eq('id', pinnedId)
          .maybeSingle();
    } catch (e, st) {
      ErrorHandler.logError(
          'Erro ao buscar mensagem fixada do chat $chatId', e, st);
      return null;
    }
  }

  /// Atualiza o conteúdo de uma mensagem (edição).
  Future<void> editMessage(String messageId, String newContent) async {
    try {
      await _client.from('messages').update({
        'content': newContent,
        'edited_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', messageId);
    } catch (e, st) {
      ErrorHandler.logError('Erro ao editar mensagem $messageId', e, st);
      throw Exception(ErrorHandler.handleSupabaseError(e));
    }
  }

  /// Exclui uma mensagem definitivamente (hard delete).
  Future<void> hardDeleteMessage(String messageId) async {
    try {
      await _client.from('messages').delete().eq('id', messageId);
    } catch (e, st) {
      ErrorHandler.logError(
          'Erro ao excluir definitivamente mensagem $messageId', e, st);
      throw Exception(ErrorHandler.handleSupabaseError(e));
    }
  }
}
