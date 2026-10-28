import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/chats/models/chat_model.dart';
import 'package:alinha_ja/features/channels/models/channel_message_model.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';

class OfflineCacheService {
  static const String messagesBoxName = 'offline_messages';
  static const String chatsBoxName = 'offline_chats';
  static const String usersBoxName = 'offline_users';
  static const String settingsBoxName = 'offline_settings';
  static const String queueBoxName = 'offline_queue';
  static const String channelMessagesBoxName = 'offline_channel_messages';

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  static Future<void> init() async {
    try {
      await Hive.initFlutter();

      // Registra adapters
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(MessageModelAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(ChatModelAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(UserModelAdapter());
      }
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(ChannelMessageModelAdapter());
      }

      // Abre as boxes
      await Hive.openBox<Map>(messagesBoxName);
      await Hive.openBox<Map>(chatsBoxName);
      await Hive.openBox<Map>(usersBoxName);
      await Hive.openBox<dynamic>(settingsBoxName);
      await Hive.openBox<Map>(queueBoxName);
      await Hive.openBox<Map>(channelMessagesBoxName);

      _initialized = true;
      debugPrint('OfflineCache: Hive inicializado com sucesso.');
    } catch (e) {
      debugPrint(
          '⚠️ OfflineCache: Falha ao inicializar Hive (modo privado ou sem suporte): $e');
      _initialized = false;
    }
  }

  // ── Channel Messages ───────────────────────────────────────────────

  static Future<void> cacheChannelMessages(
      String channelId, List<ChannelMessageModel> messages) async {
    if (!_initialized) return;
    try {
      final box = Hive.box<Map>(channelMessagesBoxName);
      final data = messages.map((m) => _channelMessageToJson(m)).toList();
      await box.put(channelId,
          {'messages': data, 'timestamp': DateTime.now().toIso8601String()});
    } catch (e) {
      debugPrint('OfflineCache: Erro ao cachear mensagens de canal: $e');
    }
  }

  static List<ChannelMessageModel>? getCachedChannelMessages(String channelId) {
    if (!_initialized) return null;
    try {
      final box = Hive.box<Map>(channelMessagesBoxName);
      final data = box.get(channelId);
      if (data == null) return null;

      final messages = data['messages'] as List?;
      if (messages == null) return null;

      return messages
          .map(
              (m) => ChannelMessageModel.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('OfflineCache: Erro ao ler mensagens de canal cacheadas: $e');
      return null;
    }
  }

  static Future<void> clearChannelMessagesCache(String channelId) async {
    if (!_initialized) return;
    try {
      final box = Hive.box<Map>(channelMessagesBoxName);
      await box.delete(channelId);
    } catch (e) {
      debugPrint(
          'OfflineCache: Erro ao limpar cache de mensagens de canal: $e');
    }
  }

  // ── Mensagens ───────────────────────────────────────────────

  static Future<void> cacheMessages(
      String chatId, List<MessageModel> messages) async {
    if (!_initialized) return;
    try {
      final box = Hive.box<Map>(messagesBoxName);
      final data = messages.map((m) => _messageToJson(m)).toList();
      await box.put(chatId,
          {'messages': data, 'timestamp': DateTime.now().toIso8601String()});
    } catch (e) {
      debugPrint('OfflineCache: Erro ao cachear mensagens: $e');
    }
  }

  static List<MessageModel>? getCachedMessages(String chatId) {
    if (!_initialized) return null;
    try {
      final box = Hive.box<Map>(messagesBoxName);
      final data = box.get(chatId);
      if (data == null) return null;

      final messages = data['messages'] as List?;
      if (messages == null) return null;

      return messages
          .map((m) => MessageModel.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('OfflineCache: Erro ao ler mensagens cacheada: $e');
      return null;
    }
  }

  static Future<void> clearMessagesCache(String chatId) async {
    if (!_initialized) return;
    try {
      final box = Hive.box<Map>(messagesBoxName);
      await box.delete(chatId);
    } catch (e) {
      debugPrint('OfflineCache: Erro ao limpar cache de mensagens: $e');
    }
  }

  // ── Chats List ──────────────────────────────────────────────

  static Future<void> cacheChats(List<ChatModel> chats) async {
    if (!_initialized) return;
    try {
      final box = Hive.box<Map>(chatsBoxName);
      final data = chats.map((c) => _chatToJson(c)).toList();
      await box.put('all_chats',
          {'chats': data, 'timestamp': DateTime.now().toIso8601String()});
    } catch (e) {
      debugPrint('OfflineCache: Erro ao cachear chats: $e');
    }
  }

  static List<ChatModel>? getCachedChats() {
    if (!_initialized) return null;
    try {
      final box = Hive.box<Map>(chatsBoxName);
      final data = box.get('all_chats');
      if (data == null) return null;

      final chats = data['chats'] as List?;
      if (chats == null) return null;

      return chats
          .map((c) => ChatModel.fromJson(Map<String, dynamic>.from(c)))
          .toList();
    } catch (e) {
      debugPrint('OfflineCache: Erro ao ler chats cacheado: $e');
      return null;
    }
  }

  // ── Usuários ────────────────────────────────────────────────

  static Future<void> cacheUser(UserModel user) async {
    if (!_initialized) return;
    try {
      final box = Hive.box<Map>(usersBoxName);
      await box.put(user.id, _userToJson(user));
    } catch (e) {
      debugPrint('OfflineCache: Erro ao cachear usuario: $e');
    }
  }

  static UserModel? getCachedUser(String userId) {
    if (!_initialized) return null;
    try {
      final box = Hive.box<Map>(usersBoxName);
      final data = box.get(userId);
      if (data == null) return null;
      return UserModel.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('OfflineCache: Erro ao ler usuario cacheado: $e');
      return null;
    }
  }

  static Future<void> cacheUsers(List<UserModel> users) async {
    if (!_initialized) return;
    try {
      final box = Hive.box<Map>(usersBoxName);
      for (final user in users) {
        await box.put(user.id, _userToJson(user));
      }
    } catch (e) {
      debugPrint('OfflineCache: Erro ao cachear usuarios: $e');
    }
  }

  // ── Configurações ───────────────────────────────────────────

  static Future<void> cacheSetting(String key, dynamic value) async {
    if (!_initialized) return;
    try {
      final box = Hive.box<dynamic>(settingsBoxName);
      await box.put(key, value);
    } catch (e) {
      debugPrint('OfflineCache: Erro ao salvar configuracao: $e');
    }
  }

  static T? getSetting<T>(String key) {
    if (!_initialized) return null;
    try {
      final box = Hive.box<dynamic>(settingsBoxName);
      return box.get(key) as T?;
    } catch (e) {
      debugPrint('OfflineCache: Erro ao ler configuracao: $e');
      return null;
    }
  }

  // ── Fila de Sincronização (Queue) ──────────────────────────

  static Future<void> enqueueOperation(Map<String, dynamic> operation) async {
    if (!_initialized) return;
    try {
      final box = Hive.box<Map>(queueBoxName);
      final id = operation['temp_id'] ??
          DateTime.now().millisecondsSinceEpoch.toString();
      await box.put(id, operation);
    } catch (e) {
      debugPrint('OfflineCache: Erro ao enfileirar operacao: $e');
    }
  }

  static List<Map<String, dynamic>> getPendingOperations() {
    if (!_initialized) return [];
    try {
      final box = Hive.box<Map>(queueBoxName);
      return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint('OfflineCache: Erro ao ler operacoes pendentes: $e');
      return [];
    }
  }

  static Future<void> removeOperation(String id) async {
    if (!_initialized) return;
    try {
      final box = Hive.box<Map>(queueBoxName);
      await box.delete(id);
    } catch (e) {
      debugPrint('OfflineCache: Erro ao remover operacao da fila: $e');
    }
  }

  /// Atualiza campos de uma operação pendente na fila.
  /// Usado para incrementar contador de retries sem remover a operação.
  static Future<void> updateOperation(
      String id, Map<String, dynamic> updates) async {
    if (!_initialized) return;
    try {
      final box = Hive.box<Map>(queueBoxName);
      final existing = box.get(id);
      if (existing != null) {
        existing.addAll(updates);
        await box.put(id, existing);
      }
    } catch (e) {
      debugPrint('OfflineCache: Erro ao atualizar operacao na fila: $e');
    }
  }

  // ── Limpeza ────────────────────────────────────────────────

  /// Apaga tudo que a conta deixou no Hive. Chamado no logout: inclui a
  /// fila offline, senão as operações pendentes de uma conta seriam
  /// reenviadas com a sessão da próxima.
  static Future<void> clearAll() async {
    if (!_initialized) return;
    try {
      await Hive.box<Map>(messagesBoxName).clear();
      await Hive.box<Map>(channelMessagesBoxName).clear();
      await Hive.box<Map>(chatsBoxName).clear();
      await Hive.box<Map>(usersBoxName).clear();
      await Hive.box<Map>(queueBoxName).clear();
      await Hive.box<dynamic>(settingsBoxName).clear();
    } catch (e) {
      debugPrint('OfflineCache: Erro ao limpar caches: $e');
    }
  }

  static Future<void> clearOldCache({int daysOld = 7}) async {
    if (!_initialized) return;
    try {
      final cutoff = DateTime.now().subtract(Duration(days: daysOld));

      // Limpa mensagens antigas
      final messagesBox = Hive.box<Map>(messagesBoxName);
      final keysToDelete = <String>[];
      for (final key in messagesBox.keys) {
        final data = messagesBox.get(key);
        if (data != null) {
          final timestamp = data['timestamp'] as String?;
          if (timestamp != null) {
            final date = DateTime.tryParse(timestamp);
            if (date != null && date.isBefore(cutoff)) {
              keysToDelete.add(key as String);
            }
          }
        }
      }
      for (final key in keysToDelete) {
        await messagesBox.delete(key);
      }
    } catch (e) {
      debugPrint('OfflineCache: Erro ao limpar cache antigo: $e');
    }
  }

  // ── Helpers de serialização ────────────────────────────────

  static Map<String, dynamic> _messageToJson(MessageModel m) => {
        'id': m.id,
        'chat_id': m.chatId,
        'sender_id': m.senderId,
        'content': m.content,
        'content_type': m.contentTypeString,
        'media_url': m.mediaUrl,
        'media_mime_type': m.mediaMimeType,
        'media_size_bytes': m.mediaSizeBytes,
        'reply_to': m.replyTo,
        'thread_id': m.threadId,
        'is_bot': m.isBot,
        'thread_reply_count': m.threadReplyCount,
        'metadata': m.metadata,
        'status': m.status.name,
        'created_at': m.createdAt.toIso8601String(),
        'deleted_at': m.deletedAt?.toIso8601String(),
        'edited_at': m.editedAt?.toIso8601String(),
        'acknowledged_by_me': m.acknowledgedByMe,
      };

  static Map<String, dynamic> _chatToJson(ChatModel c) => {
        'id': c.id,
        'name': c.name,
        'type': c.type.name,
        'avatar_url': c.avatarUrl,
        'description': c.description,
        'created_by': c.createdBy,
        'metadata': c.metadata,
        'created_at': c.createdAt.toIso8601String(),
        'is_pinned': c.isPinned,
      };

  static Map<String, dynamic> _userToJson(UserModel u) => {
        'id': u.id,
        'full_name': u.fullName,
        'avatar_url': u.avatarUrl,
        'is_online': u.isOnline,
        'last_seen': u.lastSeenAt?.toIso8601String(),
        'branch_id': u.branchId,
        'role_level': u.roleLevel,
        'department_id': u.departmentId,
        'job_position_id': u.jobPositionId,
        'is_active': u.isActive,
        // cpf/data_nascimento/sexo/phone NÃO são cacheados: o cache offline (Hive)
        // fica em claro no dispositivo e persiste ao logout, o que espalharia
        // dado sensível de terceiros por todo aparelho que abriu o app.
        // Quem precisa deles busca sob demanda (get_my_sensitive_profile /
        // admin_list_users_pii).
      };

  static Map<String, dynamic> _channelMessageToJson(ChannelMessageModel m) => {
        'id': m.id,
        'channel_id': m.channelId,
        'sender_id': m.senderId,
        'content': m.content,
        'content_type': m.contentType,
        'media_url': m.mediaUrl,
        'metadata': m.metadata.toMap(),
        'is_bot': m.isBot,
        'is_system': m.isSystem,
        'reply_to': m.replyTo,
        'thread_id': m.parentMessageId,
        'thread_reply_count': m.replyCount,
        'created_at': m.createdAt.toIso8601String(),
        'updated_at': m.updatedAt?.toIso8601String(),
        'deleted_at': m.deletedAt?.toIso8601String(),
      };
}

// ── TypeAdapters para Hive ───────────────────────────────────

class ChannelMessageModelAdapter extends TypeAdapter<ChannelMessageModel> {
  @override
  final int typeId = 3;

  @override
  ChannelMessageModel read(BinaryReader reader) {
    try {
      final map = reader.readMap().cast<String, dynamic>();
      return ChannelMessageModel.fromJson(map);
    } catch (e) {
      return ChannelMessageModel.fromJson({
        'id': 'corrupted_${DateTime.now().millisecondsSinceEpoch}',
        'channel_id': '',
        'sender_id': '',
        'content': '[Mensagem corrompida no cache]',
        'content_type': 'text',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  @override
  void write(BinaryWriter writer, ChannelMessageModel obj) {
    writer.writeMap(OfflineCacheService._channelMessageToJson(obj));
  }
}

class MessageModelAdapter extends TypeAdapter<MessageModel> {
  @override
  final int typeId = 0;

  @override
  MessageModel read(BinaryReader reader) {
    try {
      final map = reader.readMap().cast<String, dynamic>();
      return MessageModel.fromJson(map);
    } catch (e) {
      // Cache corrompido — retorna mensagem placeholder para não crashar
      return MessageModel.fromJson({
        'id': 'corrupted_${DateTime.now().millisecondsSinceEpoch}',
        'chat_id': '',
        'sender_id': '',
        'content': '[Mensagem corrompida no cache]',
        'content_type': 'text',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  @override
  void write(BinaryWriter writer, MessageModel obj) {
    writer.writeMap(OfflineCacheService._messageToJson(obj));
  }
}

class ChatModelAdapter extends TypeAdapter<ChatModel> {
  @override
  final int typeId = 1;

  @override
  ChatModel read(BinaryReader reader) {
    try {
      final map = reader.readMap().cast<String, dynamic>();
      return ChatModel.fromJson(map);
    } catch (e) {
      return ChatModel.fromJson({
        'id': 'corrupted_${DateTime.now().millisecondsSinceEpoch}',
        'name': '[Chat corrompido]',
        'type': 'direct',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  @override
  void write(BinaryWriter writer, ChatModel obj) {
    writer.writeMap(OfflineCacheService._chatToJson(obj));
  }
}

class UserModelAdapter extends TypeAdapter<UserModel> {
  @override
  final int typeId = 2;

  @override
  UserModel read(BinaryReader reader) {
    try {
      final map = reader.readMap().cast<String, dynamic>();
      return UserModel.fromJson(map);
    } catch (e) {
      return UserModel.fromJson({
        'id': 'corrupted_${DateTime.now().millisecondsSinceEpoch}',
        'full_name': '[Usuário corrompido]',
      });
    }
  }

  @override
  void write(BinaryWriter writer, UserModel obj) {
    writer.writeMap(OfflineCacheService._userToJson(obj));
  }
}
