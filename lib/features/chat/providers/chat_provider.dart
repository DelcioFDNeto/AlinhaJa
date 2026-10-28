import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:uuid/uuid.dart';
import 'package:alinha_ja/core/services/media_cache_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/extensions.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/chat/data/media_service.dart';
import 'package:alinha_ja/features/chat/data/chat_repository.dart';
import 'package:alinha_ja/features/chat/providers/chat_members_provider.dart';
import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/chats/ui/chats_list_screen.dart';
// ─── State ──────────────────────────────────────────────────

class ChatState {
  final List<MessageModel> messages;
  final bool isLoading;
  final bool hasMore;
  final DateTime? latestReadByOthers;
  final String? error;
  final Map<String, String> typingUsers;
  final Map<String, List<Map<String, dynamic>>> reactions;
  final MessageModel? pinnedMessage;
  final bool isReconnecting;
  final String searchQuery;

  /// Mensagens citadas por `reply_to` que estão fora da página carregada.
  final Map<String, MessageModel> quotedMessages;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.latestReadByOthers,
    this.error,
    this.typingUsers = const {},
    this.reactions = const {},
    this.pinnedMessage,
    this.isReconnecting = false,
    this.searchQuery = '',
    this.quotedMessages = const {},
  });

  /// Mensagem original citada por [msg], venha ela da página carregada ou do
  /// cache de citações.
  MessageModel? quotedFor(MessageModel msg) {
    final targetId = msg.replyTo;
    if (targetId == null) return null;
    for (final m in messages) {
      if (m.id == targetId) return m;
    }
    return quotedMessages[targetId];
  }

  ChatState copyWith({
    List<MessageModel>? messages,
    bool? isLoading,
    bool? hasMore,
    DateTime? latestReadByOthers,
    String? error,
    Map<String, String>? typingUsers,
    Map<String, List<Map<String, dynamic>>>? reactions,
    MessageModel? pinnedMessage,
    bool clearPin = false,
    bool? isReconnecting,
    String? searchQuery,
    Map<String, MessageModel>? quotedMessages,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        latestReadByOthers: latestReadByOthers ?? this.latestReadByOthers,
        error: error ?? this.error,
        typingUsers: typingUsers ?? this.typingUsers,
        reactions: reactions ?? this.reactions,
        pinnedMessage: clearPin ? null : (pinnedMessage ?? this.pinnedMessage),
        isReconnecting: isReconnecting ?? this.isReconnecting,
        searchQuery: searchQuery ?? this.searchQuery,
        quotedMessages: quotedMessages ?? this.quotedMessages,
      );
}

class ChatArgs {
  final String chatId;
  final String? threadId;

  const ChatArgs({required this.chatId, this.threadId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatArgs &&
          runtimeType == other.runtimeType &&
          chatId == other.chatId &&
          threadId == other.threadId;

  @override
  int get hashCode => chatId.hashCode ^ threadId.hashCode;
}

// ─── Mescla de mensagens (puras, testáveis) ─────────────────

/// Mescla mensagens vindas do servidor em [current]: substitui pelo id,
/// acrescenta as novas (ordem decrescente, teto [cap]) e mantém as páginas
/// antigas já carregadas. [newFromOthers] indica mensagem nova de outra
/// pessoa — hora de marcar a conversa como lida.
({List<MessageModel> messages, bool newFromOthers}) mergeMessageLists(
  List<MessageModel> current,
  List<MessageModel> incoming, {
  required String? currentUserId,
  int cap = 500,
}) {
  final updated = List<MessageModel>.from(current);
  final indexById = <String, int>{
    for (var i = 0; i < updated.length; i++) updated[i].id: i,
  };

  var added = false;
  var newFromOthers = false;
  for (final m in incoming) {
    final i = indexById[m.id];
    if (i != null) {
      updated[i] = m;
    } else {
      indexById[m.id] = updated.length;
      updated.add(m);
      added = true;
      if (m.senderId != currentUserId) newFromOthers = true;
    }
  }

  if (added) {
    updated.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (updated.length > cap) updated.length = cap;
  }
  return (messages: updated, newFromOthers: newFromOthers);
}

/// Troca a mensagem otimista [tempId] pela [real] devolvida pelo insert. O
/// realtime pode entregar a real antes da resposta do insert: nesse caso ela
/// já está na lista e a otimista só sai (sem duplicar).
List<MessageModel> replaceOptimisticMessage(
    List<MessageModel> messages, String tempId, MessageModel real) {
  final alreadyMerged = messages.any((m) => m.id == real.id);
  return alreadyMerged
      ? messages.where((m) => m.id != tempId).toList()
      : messages.map((m) => m.id == tempId ? real : m).toList();
}

// ─── Provider Family ────────────────────────────────────────

/// Um [ChatNotifier] por `chatId` (e opcionalmente `threadId`).
final chatProvider = NotifierProvider.family<ChatNotifier, ChatState, ChatArgs>(
  ChatNotifier.new,
);

// ─── Notifier ───────────────────────────────────────────────

/// Controller responsável por toda a lógica da tela de chat:
/// - Carregamento e paginação de mensagens
/// - Realtime subscription (INSERT)
/// - Envio de texto
/// - Envio de imagem com UI OTIMISTA
///   (FileImage local → upload → NetworkImage com URL real)
class ChatNotifier extends FamilyNotifier<ChatState, ChatArgs> {
  final _uuid = const Uuid();
  final _media = MediaService();
  final _picker = ImagePicker();
  RealtimeChannel? _messagesChannel;
  StreamSubscription<List<Map<String, dynamic>>>? _membersSub;
  Timer? _typingTimer;
  RealtimeChannel? _typingChannel;
  final Map<String, Timer> _typingCleanupTimers = {};
  final Set<String> _pendingChangedIds = {};
  Timer? _changesDebounce;
  bool _subscribedOnce = false;
  bool _disposed = false;
  int _retryDelaySeconds = 3;

  String get chatId => arg.chatId;
  String? get threadId => arg.threadId;

  @override
  ChatState build(ChatArgs arg) {
    ref.onDispose(() {
      _disposed = true;
      _removeMessagesChannel();
      _changesDebounce?.cancel();
      _membersSub?.cancel();
      _typingTimer?.cancel();
      for (final timer in _typingCleanupTimers.values) {
        timer.cancel();
      }
      _typingCleanupTimers.clear();
      // removeChannel, não só unsubscribe: reabrir a conversa criava outro
      // canal com o mesmo tópico ao lado do antigo, ainda no cliente.
      final typing = _typingChannel;
      if (typing != null) supabase.removeChannel(typing);
    });
    // Cancela subscriptions anteriores caso build() seja chamado novamente
    _removeMessagesChannel();
    _membersSub?.cancel();
    _pendingChangedIds.clear();
    Future.microtask(() {
      if (_disposed) return;
      _loadMessages().then((_) {
        if (!_disposed) _subscribeRealtime();
      });
      _fetchInitialMembersInfo();
      _loadPinnedMessage();
      _subscribeMembersRealtime();
      _subscribeTypingChannel();
      _markAsRead();
    });
    return const ChatState(isLoading: true);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query.trim());
  }

  // ── Carregamento ─────────────────────────────────────────

  ChatRepository get _chatRepo => ref.read(chatRepositoryProvider);

  Future<void> _loadMessages() async {
    state = state.copyWith(isLoading: true);
    try {
      final msgs = await _chatRepo.loadMessages(chatId, threadId: threadId);
      state = state.copyWith(
        messages: msgs,
        isLoading: false,
        hasMore: msgs.length >= AppConstants.messagesPerPage,
      );
      unawaited(_hydrateQuotedMessages(msgs));
      // Reações em paralelo: não atrasam a assinatura do realtime.
      unawaited(loadReactions());
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Busca as mensagens citadas por `reply_to` que ficaram fora da página
  /// carregada, para a bolha conseguir desenhar o cartão de citação.
  Future<void> _hydrateQuotedMessages(List<MessageModel> msgs) async {
    final loadedIds = msgs.map((m) => m.id).toSet();
    final missing = msgs
        .map((m) => m.replyTo)
        .whereType<String>()
        .where((id) =>
            !loadedIds.contains(id) && !state.quotedMessages.containsKey(id))
        .toSet();
    if (missing.isEmpty) return;

    try {
      final rows = await supabase
          .from('messages')
          .select('*, sender:users(id, full_name, avatar_url)')
          .inFilter('id', missing.toList());

      final quoted = Map<String, MessageModel>.from(state.quotedMessages);
      for (final row in (rows as List)) {
        try {
          final msg = MessageModel.fromJson(Map<String, dynamic>.from(row));
          quoted[msg.id] = msg;
        } catch (_) {}
      }
      state = state.copyWith(quotedMessages: quoted);
    } catch (e) {
      debugPrint('Aviso: falha ao carregar mensagens citadas -> $e');
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoading || state.messages.isEmpty) return;
    state = state.copyWith(isLoading: true);

    try {
      final oldest = state.messages.last.createdAt;
      final older = await _chatRepo.loadMessages(chatId,
          olderThan: oldest, threadId: threadId);

      state = state.copyWith(
        messages: [...state.messages, ...older],
        isLoading: false,
        hasMore: older.length >= AppConstants.messagesPerPage,
      );
      unawaited(_hydrateQuotedMessages(older));
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── Realtime ─────────────────────────────────────────────

  /// Escuta INSERT/UPDATE da conversa via `onPostgresChanges`.
  ///
  /// Antes era `messages.stream().eq('chat_id')`: sem limite, ele baixava o
  /// histórico inteiro da conversa ao abrir (e a cada reconexão) e reenviava a
  /// lista completa a cada evento. Aqui cada evento traz só a linha alterada.
  void _subscribeRealtime() {
    if (state.isReconnecting) {
      state = state.copyWith(isReconnecting: false);
    }
    _removeMessagesChannel();
    _subscribedOnce = false;

    // Sufixo único: um canal antigo pode ainda estar saindo quando este entra.
    final topic = 'chat_messages:$chatId:${threadId ?? 'main'}:${_uuid.v4()}';
    _messagesChannel = supabase
        .channel(topic)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: _onMessageChange,
        )
        // Exclusões (visualização única consumida, exclusão definitiva).
        // DELETE não aceita filtro no Realtime: chega só a chave de cada
        // linha apagada, e basta ver se ela está na tela. Sem isto o
        // remetente via a mídia temporária "enviada" para sempre.
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          callback: _onMessageDelete,
        )
        .subscribe((status, error) {
      if (_disposed) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _retryDelaySeconds = 3;
          if (state.isReconnecting) {
            state = state.copyWith(isReconnecting: false);
          }
          // O que chegou antes da assinatura (ou durante uma queda de
          // conexão, ex.: app em segundo plano) não gerou evento.
          unawaited(_catchUp(afterReconnect: _subscribedOnce));
          _subscribedOnce = true;
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          _scheduleResubscribe(error);
        case RealtimeSubscribeStatus.closed:
          break;
      }
    });
  }

  void _removeMessagesChannel() {
    final channel = _messagesChannel;
    _messagesChannel = null;
    if (channel != null) unawaited(supabase.removeChannel(channel));
  }

  void _scheduleResubscribe(Object? error) {
    debugPrint(
        '⚠️ Realtime da conversa caiu: $error — reconectando em ${_retryDelaySeconds}s...');
    state = state.copyWith(isReconnecting: true);
    _removeMessagesChannel();
    Future.delayed(Duration(seconds: _retryDelaySeconds), () {
      if (_disposed) return;
      // Backoff exponencial com teto de 60s.
      _retryDelaySeconds = (_retryDelaySeconds * 2).clamp(3, 60);
      _subscribeRealtime();
    });
  }

  void _onMessageChange(PostgresChangePayload payload) {
    final row = payload.newRecord;
    final id = row['id'] as String?;
    if (id == null) return;
    // Um filtro só (chat_id) no realtime: a régua x tópico é separada aqui.
    if (row['thread_id'] != threadId) return;

    // Rajadas (ex.: recibo de leitura alterando dezenas de linhas) viram uma
    // única busca.
    _pendingChangedIds.add(id);
    _changesDebounce?.cancel();
    _changesDebounce =
        Timer(const Duration(milliseconds: 50), _flushPendingChanges);
  }

  void _onMessageDelete(PostgresChangePayload payload) {
    final id = payload.oldRecord['id'];
    if (id is! String || !state.messages.any((m) => m.id == id)) return;
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != id).toList(),
    );
  }

  /// A linha do realtime não traz o remetente (join com `users`) nem os
  /// "cientes": busca as alteradas num único select.
  Future<void> _flushPendingChanges() async {
    if (_disposed || _pendingChangedIds.isEmpty) return;
    final ids = _pendingChangedIds.toList();
    _pendingChangedIds.clear();
    try {
      final batch = await _chatRepo.getMessagesBatch(ids);
      if (!_disposed) _mergeMessages(batch);
    } catch (e) {
      log('Erro ao buscar mensagens alteradas do realtime: $e');
    }
  }

  /// Recupera o que ficou sem evento. Na primeira assinatura basta o que é
  /// mais novo que a tela; após reconexão recarrega a página mais recente
  /// inteira, para atualizar também status (checks) e edições.
  Future<void> _catchUp({required bool afterReconnect}) async {
    try {
      final newest = state.messages
          .where((m) => m.status != MessageStatus.sending)
          .map((m) => m.createdAt)
          .fold<DateTime?>(
              null, (a, b) => a == null || b.isAfter(a) ? b : a);
      final msgs = await _chatRepo.loadMessages(
        chatId,
        threadId: threadId,
        newerThan: afterReconnect ? null : newest,
      );
      if (!_disposed) _mergeMessages(msgs);
    } catch (e) {
      log('Erro ao recuperar mensagens da conversa: $e');
    }
  }

  void _mergeMessages(List<MessageModel> incoming) {
    if (incoming.isEmpty) return;
    final merge = mergeMessageLists(state.messages, incoming,
        currentUserId: supabase.auth.currentUser?.id);
    state = state.copyWith(messages: merge.messages);

    if (merge.newFromOthers) _markAsRead();
    unawaited(loadReactions());
  }

  Future<void> _fetchInitialMembersInfo() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    final maxD = await _chatRepo.fetchLatestReadByOthers(chatId, currentUserId);
    if (maxD != null) {
      state = state.copyWith(latestReadByOthers: maxD);
    }
  }

  void _subscribeMembersRealtime() {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    // Escuta alterações na tabela chat_members (para pegar o last_read_at)
    _membersSub = supabase
        .from('chat_members')
        .stream(primaryKey: ['sync_id'])
        .eq('chat_id', chatId)
        .listen((rows) {
          if (rows.isEmpty) return;

          DateTime? maxD;
          for (final r in rows) {
            // Ignora se for o próprio usuário
            if (r['user_id'] == currentUserId) continue;

            final lra = r['last_read_at'] as String?;
            if (lra != null) {
              final d = DateTime.parse(lra);
              if (maxD == null || d.isAfter(maxD)) {
                maxD = d;
              }
            }
          }

          // Atualiza o estado se descobrirmos uma data de leitura mais recente
          if (maxD != null) {
            if (state.latestReadByOthers == null ||
                maxD.isAfter(state.latestReadByOthers!)) {
              state = state.copyWith(latestReadByOthers: maxD);
            }
          }
        }, onError: (e) {
          log('Erro no realtime de chat_members: $e');
        });
  }

  // ── Typing Indicator ──────────────────────────────────────

  void _subscribeTypingChannel() {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    _typingChannel = supabase.channel('typing:$chatId');
    _typingChannel!
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final userId = payload['user_id'] as String?;
            final userName = payload['user_name'] as String?;
            final isTyping = payload['is_typing'] as bool? ?? false;

            if (userId == null || userId == myId) return;

            final updated = Map<String, String>.from(state.typingUsers);
            if (isTyping) {
              updated[userId] = userName ?? 'Alguém';
            } else {
              updated.remove(userId);
            }
            state = state.copyWith(typingUsers: updated);

            // Auto-remove após 4 segundos sem atualização
            if (isTyping) {
              final timerKey = userId;
              _typingCleanupTimers[timerKey]?.cancel();
              _typingCleanupTimers[timerKey] =
                  Timer(const Duration(seconds: 4), () {
                final current = Map<String, String>.from(state.typingUsers);
                current.remove(userId);
                state = state.copyWith(typingUsers: current);
                _typingCleanupTimers.remove(timerKey);
              });
            }
          },
        )
        .subscribe();
  }

  /// Envia evento de "digitando..." via Broadcast (efêmero, sem DB)
  void sendTypingEvent(String userName) {
    _typingTimer?.cancel();
    _typingChannel?.sendBroadcastMessage(
      event: 'typing',
      payload: {
        'user_id': supabase.auth.currentUser?.id,
        'user_name': userName,
        'is_typing': true,
      },
    );

    // Para de "digitar" após 3s sem chamar o método de novo
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _typingChannel?.sendBroadcastMessage(
        event: 'typing',
        payload: {
          'user_id': supabase.auth.currentUser?.id,
          'user_name': userName,
          'is_typing': false,
        },
      );
    });
  }

  /// Sobe um arquivo avulso e devolve a URL pública, sem criar mensagem.
  ///
  /// Usado pelo anexo do anúncio, que precisa da URL antes de gravar a
  /// mensagem. Vai para a mesma pasta da conversa usada pelos documentos.
  Future<String?> uploadAttachment(XFile file) async {
    try {
      final result = await _media.uploadFile(
        chatId: chatId,
        file: file,
        mimeType: 'application/octet-stream',
      );
      return result.publicUrl;
    } catch (e) {
      debugPrint('Erro ao subir anexo na conversa: $e');
      return null;
    }
  }

  /// Envia texto. [metadata] carrega mensagens estruturadas (enquete, evento,
  /// localização, contato, anúncio) — ver `MessageExtras`; o `content_type`
  /// continua sendo `text` porque o enum do banco não tem esses tipos.
  Future<void> sendText(String text,
      {String? replyTo,
      Map<String, dynamic>? metadata}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final tempId = _uuid.v4();

    final baseMetadata = <String, dynamic>{
      ...?metadata,
    };

    final optimistic = MessageModel(
      id: tempId,
      chatId: chatId,
      senderId: userId,
      content: trimmed,
      contentType: ContentType.text,
      replyTo: replyTo,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      metadata: baseMetadata,
    );

    // Adiciona imediatamente à lista (UI otimista)
    final newList = [optimistic, ...state.messages];
    if (newList.length > 500) newList.length = 500;
    state = state.copyWith(messages: newList);

    try {
      final insertData = <String, dynamic>{
        'chat_id': chatId,
        'sender_id': userId,
        'content': trimmed,
        'content_type': 'text',
      };
      if (replyTo != null) insertData['reply_to'] = replyTo;
      if (threadId != null) insertData['thread_id'] = threadId;
      if (metadata != null && metadata.isNotEmpty) {
        insertData['metadata'] = Map<String, dynamic>.from(metadata);
      }

      // ── Parse de Menções (@NomeCompleto) ──
      final mentionRegex =
          RegExp(r'@([a-zA-ZÀ-ú0-9_]+(?:\s+[a-zA-ZÀ-ú0-9_]+)*)');
      final allMatches = mentionRegex.allMatches(trimmed);
      // Cap: máximo 10 menções, nome máximo 50 chars
      final safeMatches = allMatches
          .where((m) => (m.group(1)?.length ?? 0) <= 50)
          .take(10)
          .toList();
      if (safeMatches.isNotEmpty) {
        try {
          final memberIds = await _resolveMentions(
              safeMatches.map((m) => m.group(1)!).toList());
          if (memberIds.isNotEmpty) {
            // Preserva o metadata estruturado: antes a menção sobrescrevia o
            // campo inteiro e a enquete/evento chegava sem formato.
            insertData['metadata'] = {
              ...?insertData['metadata'] as Map<String, dynamic>?,
              'mentions': memberIds,
            };
          }
        } catch (e) {
          debugPrint('Aviso: Falha ao resolver menções -> $e');
        }
      }

      final inserted =
          await _chatRepo.insertMessage(insertData, tempId: tempId);

      // Substitui a mensagem otimista pelo registro real assim que o banco
      // confirma — o log de atividade não pode segurar o "enviando".
      _replaceOptimistic(tempId, MessageModel.fromJson(inserted));

      unawaited(supabase.rpc('log_user_activity', params: {
        'p_user_id': userId,
        'p_activity_type': 'message_sent',
        'p_description': 'Enviou mensagem em $chatId',
        'p_target_id': inserted['id'],
      }).catchError((Object e) {
        log('Aviso: Falha ao registrar log de atividade: $e');
        return null;
      }));
    } catch (e) {
      _markError(tempId);
    }
  }

  /// Resolve nomes mencionados para UUIDs consultando os membros do chat.
  Future<List<String>> _resolveMentions(List<String> names) async {
    final membersRes = await supabase
        .from('chat_members')
        .select('user_id, users!inner(full_name)')
        .eq('chat_id', chatId);

    final ids = <String>[];
    for (final member in (membersRes as List)) {
      final fullName =
          (member['users'] as Map<String, dynamic>?)?['full_name'] as String? ??
              '';
      for (final name in names) {
        if (fullName.toLowerCase() == name.toLowerCase().trim()) {
          ids.add(member['user_id'] as String);
        }
      }
    }
    return ids;
  }

  /// Dispara um Card interativo de Sala de Reunião na conversa
  Future<void> sendMeetingCard(String roomId, String roomName) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final tempId = _uuid.v4();
    final optimistic = MessageModel(
      id: tempId,
      chatId: chatId,
      senderId: userId,
      content: roomName,
      contentType: ContentType.meeting,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      metadata: {
        'room_id': roomId,
        'room_name': roomName,
      },
    );

    final newList = [optimistic, ...state.messages];
    if (newList.length > 500) newList.length = 500;
    state = state.copyWith(messages: newList);

    try {
      final inserted = await _chatRepo.insertMessage({
        'chat_id': chatId,
        'sender_id': userId,
        'content_type': 'meeting',
        'content': roomName,
        'metadata': {
          'room_id': roomId,
          'room_name': roomName,
        },
      });
      _replaceOptimistic(tempId, MessageModel.fromJson(inserted));
    } catch (e) {
      log('Erro ao enviar Card de Reunião: $e');
      _markError(tempId);
    }
  }

  // ── Envio de Imagem (com UI otimista + compressão) ───────

  /// Fluxo completo de envio de imagem:
  /// 1. Abre o seletor de galeria/câmera
  /// 2. Cria mensagem local com [FileImage] (UI otimista)
  /// 3. Comprime e faz upload em background
  /// 4. Atualiza a mensagem local com [NetworkImage] (URL real)
  Future<void> pickAndSendMedia({
    ImageSource source = ImageSource.gallery,
    XFile? file,
    bool isViewOnce = false,
    String? replyTo,
    String? caption,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    XFile? picked = file;
    if (picked == null) {
      if (source == ImageSource.gallery) {
        picked = await _picker.pickMedia(imageQuality: 80);
      } else {
        // Para câmera, por enquanto pickImage
        picked = await _picker.pickImage(source: source, imageQuality: 80);
      }
    }

    if (picked == null) return;

    await sendMediaFile(picked,
        isViewOnce: isViewOnce, replyTo: replyTo, caption: caption);
  }

  /// Uploads que o usuário cancelou: o envio em curso é descartado ao terminar.
  final Set<String> _canceledUploads = {};

  /// Cancela um upload em andamento e tira a mensagem da lista.
  ///
  /// O upload em si não é abortável no meio do caminho, então marcamos o id
  /// para descartar o resultado quando ele chegar — sem inserir no banco.
  void cancelUpload(String messageId) {
    _canceledUploads.add(messageId);
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
  }

  /// Reenvia uma mídia que falhou, usando o arquivo local da mensagem.
  Future<void> retryMedia(MessageModel failed) async {
    final path = failed.localFilePath;
    if (path == null) return;

    state = state.copyWith(
      messages: state.messages.where((m) => m.id != failed.id).toList(),
    );

    if (failed.contentType == ContentType.audio) {
      await sendAudio(path, replyTo: failed.replyTo);
      return;
    }
    await sendMediaFile(
      XFile(path),
      replyTo: failed.replyTo,
      caption: failed.content,
      isViewOnce: failed.metadata['is_view_once'] == true,
    );
  }

  /// Envia um arquivo de mídia já escolhido (a escolha e o preview vivem na UI).
  ///
  /// [caption] vira o corpo da mensagem, como legenda da foto/vídeo.
  Future<void> sendMediaFile(
    XFile picked, {
    bool isViewOnce = false,
    String? replyTo,
    String? caption,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final tempId = _uuid.v4();
    final isVideo = picked.path.toLowerCase().endsWith('.mp4') ||
        picked.path.toLowerCase().endsWith('.mov');
    final cType = isVideo ? ContentType.video : ContentType.image;

    final optimistic = MessageModel(
      id: tempId,
      chatId: chatId,
      senderId: userId,
      content: caption,
      contentType: cType,
      threadId: threadId,
      replyTo: replyTo,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      localFilePath: picked.path,
      metadata: isViewOnce ? {'is_view_once': true} : {},
    );

    final newList = [optimistic, ...state.messages];
    if (newList.length > 500) newList.length = 500;
    state = state.copyWith(messages: newList);

    try {
      final MediaUploadResult result;
      if (isVideo) {
        result = await _media.uploadFile(
          chatId: chatId,
          file: picked,
          mimeType: 'video/mp4',
          onProgress: (progress) {
            _updateOptimisticProgress(tempId, progress);
          },
        );
      } else {
        result = await _media.compressAndUploadImage(
          chatId: chatId,
          file: picked,
          onProgress: (progress) {
            _updateOptimisticProgress(tempId, progress);
          },
        );
      }

      // Cancelado durante o upload: descarta sem gravar nada.
      if (_canceledUploads.remove(tempId)) return;

      final inserted = await _chatRepo.insertMessage({
        'chat_id': chatId,
        'sender_id': userId,
        'content_type': isVideo ? 'video' : 'image',
        if (caption != null && caption.trim().isNotEmpty) 'content': caption,
        'media_url': result.publicUrl,
        'media_mime_type': result.mimeType,
        'media_size_bytes': result.sizeBytes,
        'metadata': isViewOnce ? {'is_view_once': true} : {},
        if (replyTo != null) 'reply_to': replyTo,
        if (threadId != null) 'thread_id': threadId,
      });

      await MediaCacheManager.cacheLocalFile(
        localPath: picked.path,
        mediaUrl: result.publicUrl,
        messageId: inserted['id'],
        chatId: chatId,
        mediaType: isVideo ? 'video' : 'image',
      );

      _replaceOptimistic(tempId, MessageModel.fromJson(inserted));
    } catch (e) {
      if (_canceledUploads.remove(tempId)) return;
      _markError(tempId);
    }
  }

  Future<void> sendAudio(String filePath, {String? replyTo}) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final tempId = _uuid.v4();
    final fileToUpload = XFile(filePath);

    final optimistic = MessageModel(
      id: tempId,
      chatId: chatId,
      senderId: userId,
      contentType: ContentType.audio,
      threadId: threadId,
      replyTo: replyTo,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      localFilePath: filePath,
    );

    final newList = [optimistic, ...state.messages];
    if (newList.length > 500) newList.length = 500;
    state = state.copyWith(messages: newList);

    try {
      final uploadResult = await _media.uploadFile(
        chatId: chatId,
        file: fileToUpload,
        mimeType: 'audio/m4a',
        onProgress: (p) => _updateOptimisticProgress(tempId, p),
      );

      final inserted = await _chatRepo.insertMessage({
        'chat_id': chatId,
        'sender_id': userId,
        'content_type': 'audio',
        'media_url': uploadResult.publicUrl,
        'media_mime_type': uploadResult.mimeType,
        'media_size_bytes': uploadResult.sizeBytes,
        if (replyTo != null) 'reply_to': replyTo,
        if (threadId != null) 'thread_id': threadId,
      });

      await MediaCacheManager.cacheLocalFile(
        localPath: filePath,
        mediaUrl: uploadResult.publicUrl,
        messageId: inserted['id'],
        chatId: chatId,
        mediaType: 'audio',
      );

      _replaceOptimistic(tempId, MessageModel.fromJson(inserted));
    } catch (e) {
      log('Erro ao enviar áudio: $e');
      _markError(tempId);
    }
  }

  Future<void> openViewOnceMessage(String messageId) async {
    // Sai da conversa na hora: uma visualização só, mesmo que a rede falhe
    // abaixo. Antes, qualquer erro na RPC deixava a mídia na tela para ser
    // reaberta quantas vezes quisessem.
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
    try {
      // A RPC apaga a mensagem e o metadado do objeto (o que já o torna
      // inacessível pela Storage API) e devolve o path removido.
      final storagePath = await supabase
          .rpc('mark_view_once_opened', params: {'p_message_id': messageId});

      // Purge físico do arquivo no bucket. É complementar, não a garantia:
      // a destruição autoritativa é a da RPC, que o cliente não pode pular.
      if (storagePath is String && storagePath.isNotEmpty) {
        try {
          await supabase.storage
              .from(AppConstants.storageBucket)
              .remove([storagePath]);
        } catch (e) {
          log('Falha no purge físico da mídia view-once: $e');
        }
        await MediaCacheManager.evict(storagePath);
      }
    } catch (e) {
      log('Erro ao deletar mensagem temporária: $e');
    }
  }

  // ── Envio de Documento ──────────────────────────────────
  Future<void> pickAndSendDocument(
      {XFile? externalFile, String? replyTo}) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    String fileName;
    int fileSize;
    XFile fileToUpload;
    Uint8List? fileBytes;

    if (externalFile != null) {
      // Caso Drag & Drop tenha fornecido o arquivo
      fileName = externalFile.name;
      fileBytes = await externalFile.readAsBytes();
      if (fileBytes.isEmpty) return;
      fileSize = fileBytes.length;
      fileToUpload = externalFile;
    } else {
      // Abre o FilePicker
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) return;

      fileName = file.name;
      fileSize = file.bytes!.length;
      fileBytes = file.bytes;
      fileToUpload = XFile.fromData(file.bytes!, name: fileName);
    }

    final mimeType = _getMimeType(fileName);
    final tempId = _uuid.v4();

    // Mensagem otimista
    final optimistic = MessageModel(
      id: tempId,
      chatId: chatId,
      senderId: userId,
      contentType: ContentType.file,
      threadId: threadId,
      replyTo: replyTo,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      metadata: {
        'original_filename': fileName,
        'file_size_display': fileSize.fileSizeFormatted,
      },
    );

    final newList = [optimistic, ...state.messages];
    if (newList.length > 500) newList.length = 500;
    state = state.copyWith(messages: newList);

    try {
      final uploadResult = await _media.uploadFile(
        chatId: chatId,
        file: fileToUpload,
        mimeType: mimeType,
        onProgress: (p) => _updateOptimisticProgress(tempId, p),
      );

      final inserted = await _chatRepo.insertMessage({
        'chat_id': chatId,
        'sender_id': userId,
        'content_type': 'file',
        'content': fileName,
        'media_url': uploadResult.publicUrl,
        'media_mime_type': uploadResult.mimeType,
        'media_size_bytes': uploadResult.sizeBytes,
        if (replyTo != null) 'reply_to': replyTo,
        if (threadId != null) 'thread_id': threadId,
        'metadata': {
          'original_filename': fileName,
          'file_size_display': fileSize.fileSizeFormatted,
        },
      });

      if (fileToUpload.path.isNotEmpty) {
        await MediaCacheManager.cacheLocalFile(
          localPath: fileToUpload.path,
          mediaUrl: uploadResult.publicUrl,
          messageId: inserted['id'],
          chatId: chatId,
          mediaType: 'document',
        );
      }

      _replaceOptimistic(tempId, MessageModel.fromJson(inserted));
    } catch (e) {
      log('Erro ao enviar documento: $e');
      _markError(tempId);
    }
  }

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    const mimeMap = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'zip': 'application/zip',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
  }

  // ── Utilitários de Estado ─────────────────────────────────

  void _replaceOptimistic(String tempId, MessageModel real) {
    state = state.copyWith(
      messages: replaceOptimisticMessage(state.messages, tempId, real),
    );
  }

  void _markError(String tempId) {
    state = state.copyWith(
      messages: state.messages
          .map(
            (m) => m.id == tempId ? m.copyWith(status: MessageStatus.error) : m,
          )
          .toList(),
    );
  }

  void _updateOptimisticProgress(String tempId, double progress) {
    state = state.copyWith(
      messages: state.messages
          .map(
            (m) => m.id == tempId
                ? m.copyWith(
                    metadata: {...m.metadata, 'upload_progress': progress})
                : m,
          )
          .toList(),
    );
  }

  /// Soft delete de mensagem (marca deleted_at no banco, mostra "apagada" na UI).
  Future<void> deleteMessage(String messageId) async {
    // 1. Otimista: marca como deletada (mostra "Mensagem apagada" na bolha)
    final backup = List<MessageModel>.from(state.messages);
    state = state.copyWith(
      messages: state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(setDeleted: true);
        }
        return m;
      }).toList(),
    );

    try {
      // 2. Atualiza o banco via Repositório (a RLS garante que só o autor pode fazer UPDATE)
      await _chatRepo.softDeleteMessage(messageId);
    } catch (e) {
      // Reverte em caso de erro
      log('Erro ao apagar mensagem (soft delete): $e');
      state = state.copyWith(messages: backup);
    }
  }

  /// Edita o conteúdo de uma mensagem (apenas texto).
  Future<void> editMessage(String messageId, String newContent) async {
    final trimmed = newContent.trim();
    if (trimmed.isEmpty) return;

    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    // Encontra a mensagem para verificar se é o autor
    final messageIndex = state.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    final message = state.messages[messageIndex];
    if (message.senderId != currentUserId) return;

    // 1. Otimista: atualiza localmente
    final backup = List<MessageModel>.from(state.messages);
    final updatedMessages = List<MessageModel>.from(state.messages);
    updatedMessages[messageIndex] = message.copyWith(
      content: trimmed,
      editedAt: DateTime.now().toUtc(),
    );
    state = state.copyWith(messages: updatedMessages);

    try {
      // 2. Atualiza no banco
      await _chatRepo.editMessage(messageId, trimmed);

      // Registra atividade do usuário
      try {
        await supabase.rpc('log_user_activity', params: {
          'p_user_id': currentUserId,
          'p_activity_type': 'message_edited',
          'p_description': 'Editou mensagem',
          'p_target_id': messageId,
        });
      } catch (e) {
        debugPrint(
            'Aviso: Falha ao registrar log_user_activity (edição) -> $e');
      }
    } catch (e) {
      log('Erro ao editar mensagem: $e');
      state = state.copyWith(messages: backup);
      Globals.showErrorSnackBar(
          'Erro ao editar mensagem. Verifique a conexão.');
    }
  }

  /// Exclui uma mensagem definitivamente (hard delete).
  Future<void> permanentlyDeleteMessage(String messageId) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    // Verifica se é o autor ou admin
    final messageIndex = state.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    final message = state.messages[messageIndex];
    final isAuthor = message.senderId == currentUserId;
    final user = await _getCurrentUser();
    final isAdmin = AppPermissions.canModerate(user?.roleLevel);

    if (!isAuthor && !isAdmin) return;

    // 1. Otimista: remove da lista
    final backup = List<MessageModel>.from(state.messages);
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );

    try {
      await _chatRepo.hardDeleteMessage(messageId);
    } catch (e) {
      log('Erro ao excluir mensagem permanentemente: $e');
      state = state.copyWith(messages: backup);
      Globals.showErrorSnackBar(
          'Erro ao apagar mensagem. Verifique a conexão.');
    }
  }

  Future<dynamic> _getCurrentUser() async {
    return ref.read(currentUserProvider).value;
  }

  /// Carrega a mensagem fixada no chat.
  Future<void> _loadPinnedMessage() async {
    try {
      final data = await _chatRepo.fetchPinnedMessage(chatId);
      if (data != null) {
        state = state.copyWith(pinnedMessage: MessageModel.fromJson(data));
      }
    } catch (e) {
      debugPrint(
          'Aviso: Falha ao carregar pinned message (pode ter sido apagada ou não há conexão) -> $e');
    }
  }

  /// Carrega reações para as mensagens carregadas.
  Future<void> loadReactions() async {
    final ids = state.messages.map((m) => m.id).toSet().toList();
    if (ids.isEmpty) return;
    final reactions = await _chatRepo.fetchReactions(ids);
    state = state.copyWith(reactions: reactions);
  }

  /// Toggle de reação em uma mensagem.
  Future<void> toggleReaction(String messageId, String emoji) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final backup =
        Map<String, List<Map<String, dynamic>>>.from(state.reactions);
    final userReactions =
        List<Map<String, dynamic>>.from(state.reactions[messageId] ?? []);

    final existingIndex = userReactions
        .indexWhere((r) => r['user_id'] == userId && r['emoji'] == emoji);
    if (existingIndex >= 0) {
      userReactions.removeAt(existingIndex);
    } else {
      userReactions
          .add({'message_id': messageId, 'user_id': userId, 'emoji': emoji});
    }

    final updatedReactions =
        Map<String, List<Map<String, dynamic>>>.from(state.reactions);
    updatedReactions[messageId] = userReactions;
    state = state.copyWith(reactions: updatedReactions);

    final success = await _chatRepo.toggleReaction(messageId, userId, emoji);
    if (!success) state = state.copyWith(reactions: backup);
  }

  /// Fixa ou desfixa uma mensagem.
  Future<void> pinMessage(String? messageId) async {
    await _chatRepo.pinMessage(chatId, messageId);
    if (messageId == null) {
      state = state.copyWith(clearPin: true);
    } else {
      await _loadPinnedMessage();
    }
  }

  Future<void> toggleMute() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;
    try {
      final memberRes = await supabase
          .from('chat_members')
          .select('muted')
          .eq('chat_id', chatId)
          .eq('user_id', myId)
          .maybeSingle();
      if (memberRes != null) {
        final isMuted = memberRes['muted'] as bool? ?? false;
        await supabase
            .from('chat_members')
            .update({'muted': !isMuted})
            .eq('chat_id', chatId)
            .eq('user_id', myId);
        // Atualiza a UI (ícone no título e rótulo do menu) imediatamente
        ref.invalidate(chatMembersProvider(chatId));
      }
    } catch (e) {
      debugPrint('Erro ao alternar mudo: $e');
    }
  }

  void clearLocalMessages() {
    state = state.copyWith(messages: []);
  }

  Future<void> leaveGroup() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;
    try {
      await supabase
          .from('chat_members')
          .delete()
          .eq('chat_id', chatId)
          .eq('user_id', myId);
      // Remove o grupo da lista de conversas imediatamente
      ref.invalidate(chatsListProvider);
    } catch (e) {
      debugPrint('Erro ao sair do grupo: $e');
    }
  }

  Future<void> _markAsRead() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _chatRepo.markAsRead(chatId, userId);

    // Invalida a lista de conversas lateral para limpar o contador (badge) de mensagens não lidas instantaneamente
    ref.invalidate(chatsListProvider);
  }

  /// Assina (confirma ciência) em uma mensagem oficial.
  Future<void> acknowledgeMessage(String messageId) async {
    try {
      // 1. Otimista (atualiza a UI na hora)
      final msgs = List<MessageModel>.from(state.messages);
      final idx = msgs.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        msgs[idx] = msgs[idx].copyWith(acknowledgedByMe: true);
        state = state.copyWith(messages: msgs);
      }

      // 2. Chama o repositório
      await _chatRepo.acknowledgeMessage(
          messageId, supabase.auth.currentUser!.id);
    } catch (e) {
      // Reverte em caso de erro
      log('Erro ao assinar mensagem: $e');
      final msgs = List<MessageModel>.from(state.messages);
      final idx = msgs.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        msgs[idx] = msgs[idx].copyWith(acknowledgedByMe: false);
        state = state.copyWith(messages: msgs);
      }
    }
  }
}
