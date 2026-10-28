import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/channels/models/channel_message_model.dart';
import 'package:alinha_ja/features/channels/models/message_metadata.dart';
import 'package:alinha_ja/features/chat/data/media_service.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/core/services/sync_service.dart';
import 'package:alinha_ja/core/services/offline_cache_service.dart';
import 'package:alinha_ja/core/services/media_cache_manager.dart';
import 'dart:async';

class ChannelArgs {
  final String channelId;
  final String? parentMessageId;

  ChannelArgs({required this.channelId, this.parentMessageId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelArgs &&
          runtimeType == other.runtimeType &&
          channelId == other.channelId &&
          parentMessageId == other.parentMessageId;

  @override
  int get hashCode => channelId.hashCode ^ (parentMessageId?.hashCode ?? 0);
}

class ChannelState {
  final List<ChannelMessageModel> messages;
  final bool isLoading;
  final String? channelType;
  final String? currentUserRole;
  final String? currentUserDepartment;
  final String? currentUserRoleLevel;
  final String postingPermission;
  final String? createdBy;
  final String? currentUserId;
  final Map<String, UserModel> userCache;
  final Map<String, dynamic>? metadata;
  final ChannelMessageModel? replyingTo;

  /// Mensagens citadas por `reply_to` que estão fora da página carregada.
  final Map<String, ChannelMessageModel> quotedMessages;

  /// `all` | `mentions` | `none` — preferência de push deste usuário no canal.
  final String notificationLevel;

  /// Marca de leitura do usuário, usada para posicionar a régua de não lidas.
  /// Congelada na abertura da tela: `_markAsRead()` zera o contador no banco,
  /// mas a régua precisa continuar onde estava enquanto a conversa está aberta.
  final DateTime? lastReadAt;

  final bool isLoadingMore;
  final bool hasMoreMessages;

  ChannelState({
    this.messages = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMoreMessages = true,
    this.channelType,
    this.currentUserRole,
    this.currentUserDepartment,
    this.currentUserRoleLevel,
    this.postingPermission = 'everyone',
    this.createdBy,
    this.currentUserId,
    this.userCache = const {},
    this.metadata,
    this.replyingTo,
    this.quotedMessages = const {},
    this.notificationLevel = 'all',
    this.lastReadAt,
  });

  bool get isMuted => notificationLevel == 'none';

  /// Id da primeira mensagem não lida — onde a régua "novas mensagens" entra.
  ///
  /// `messages` chega em ordem decrescente (mais recente primeiro), então a
  /// última da varredura é a mais antiga ainda não lida.
  String? get firstUnreadMessageId {
    final readAt = lastReadAt;
    if (readAt == null) return null;

    String? candidate;
    for (final msg in messages) {
      if (msg.senderId == currentUserId) continue;
      if (msg.createdAt.isAfter(readAt)) {
        candidate = msg.id;
      } else {
        break;
      }
    }
    return candidate;
  }

  /// Mensagem original citada por [msg], venha ela da página carregada ou do
  /// cache de citações.
  ChannelMessageModel? quotedFor(ChannelMessageModel msg) {
    final targetId = msg.replyTo;
    if (targetId == null) return null;
    for (final m in messages) {
      if (m.id == targetId) return m;
    }
    return quotedMessages[targetId];
  }

  bool get isRestricted =>
      (channelType == 'announcement' || channelType == 'restricted');

  bool get isAdminOrOwner =>
      currentUserRole == 'admin' ||
      currentUserRole == 'owner' ||
      isTI ||
      currentUserRoleLevel == 'admin' ||
      currentUserRoleLevel == 'super_admin';

  /// Respeita TANTO o tipo restrito legado QUANTO o novo campo posting_permission
  bool get canPost {
    if (currentUserRoleLevel == 'admin' ||
        currentUserRoleLevel == 'super_admin') {
      return true; // God Mode
    }

    if (postingPermission == 'admins') {
      return isAdminOrOwner;
    }
    // Se o tipo antigo for restrito, aplica regra legacy
    if (isRestricted) {
      return isAdminOrOwner;
    }
    return true;
  }

  // Nível de governança root (apenas dept TI)
  bool get isTI {
    if (currentUserDepartment == null) return false;
    return currentUserDepartment == 'ti';
  }

  /// Governança expandida: TI, admin global, ou criador do canal
  bool get canGovernChannel {
    if (isTI) return true;
    if (currentUserRoleLevel == 'admin' ||
        currentUserRoleLevel == 'super_admin') {
      return true;
    }
    if (createdBy != null &&
        currentUserId != null &&
        createdBy == currentUserId) {
      return true;
    }
    return false;
  }

  ChannelState copyWith({
    List<ChannelMessageModel>? messages,
    bool? isLoading,
    String? channelType,
    String? currentUserRole,
    String? currentUserDepartment,
    String? currentUserRoleLevel,
    String? postingPermission,
    String? createdBy,
    String? currentUserId,
    Map<String, UserModel>? userCache,
    Map<String, dynamic>? metadata,
    ChannelMessageModel? replyingTo,
    bool clearReply = false,
    Map<String, ChannelMessageModel>? quotedMessages,
    String? notificationLevel,
    DateTime? lastReadAt,
    bool? isLoadingMore,
    bool? hasMoreMessages,
  }) {
    return ChannelState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
      channelType: channelType ?? this.channelType,
      currentUserRole: currentUserRole ?? this.currentUserRole,
      currentUserDepartment:
          currentUserDepartment ?? this.currentUserDepartment,
      currentUserRoleLevel: currentUserRoleLevel ?? this.currentUserRoleLevel,
      postingPermission: postingPermission ?? this.postingPermission,
      createdBy: createdBy ?? this.createdBy,
      currentUserId: currentUserId ?? this.currentUserId,
      userCache: userCache ?? this.userCache,
      metadata: metadata ?? this.metadata,
      replyingTo: clearReply ? null : (replyingTo ?? this.replyingTo),
      quotedMessages: quotedMessages ?? this.quotedMessages,
      notificationLevel: notificationLevel ?? this.notificationLevel,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }
}

class ActiveChannelNotifier extends FamilyNotifier<ChannelState, ChannelArgs> {
  String get channelId => arg.channelId;
  String? get parentMessageId => arg.parentMessageId;
  bool _disposed = false;

  /// Coalesce das marcações de leitura.
  ///
  /// O stream do canal dispara a cada evento — mensagem nova, edição, reação —
  /// e cada disparo gravava um UPDATE em `channel_members`. Numa conversa
  /// movimentada isso era uma escrita por evento, sem nenhum ganho: só o
  /// último `last_read_at` da rajada importa.
  Timer? _markReadDebounce;

  static const _markReadDelay = Duration(seconds: 2);

  @override
  ChannelState build(ChannelArgs arg) {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _markReadDebounce?.cancel();
    });
    Future.microtask(() {
      _fetchChannelMetadata();
      _subscribeToChannel();
      _fetchMessages();
      _markAsRead();
    });
    return ChannelState(isLoading: true);
  }

  void setReply(ChannelMessageModel msg) {
    state = state.copyWith(replyingTo: msg);
  }

  void clearReply() {
    state = state.copyWith(clearReply: true);
  }

  /// Campos de vínculo de uma nova mensagem.
  ///
  /// Resposta simples grava apenas `reply_to` e a mensagem segue na régua
  /// principal do canal. `thread_id` é exclusivo de mensagens enviadas de
  /// dentro de um tópico (provider construído com `parentMessageId`).
  Map<String, dynamic> _replyFields(ChannelMessageModel? replyingTo) => {
        if (replyingTo != null) 'reply_to': replyingTo.id,
        if (parentMessageId != null) 'thread_id': parentMessageId,
      };

  Future<void> _fetchChannelMetadata() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      // Buscar da tabela dedicada de canais/workspaces.
      final futures = await Future.wait([
        supabase
            .from('channels')
            .select(
                'type, name, description, created_by, metadata, posting_permission')
            .eq('id', channelId)
            .maybeSingle(),
        supabase
            .from('channel_members')
            .select('role, notification_level, last_read_at')
            .eq('channel_id', channelId)
            .eq('user_id', myId)
            .maybeSingle(),
        supabase
            .from('users')
            .select('department_id, role_level')
            .eq('id', myId)
            .maybeSingle(),
      ]);

      final channelRow = futures[0];
      final memberRow = futures[1];
      final userRow = futures[2];

      // Extrair metadata do workflow
      final metadata = (channelRow?['metadata'] as Map<String, dynamic>?) ?? {};
      final workflowEnabled = metadata['workflow_enabled'] as bool? ?? false;
      final postingPermission = (channelRow?['posting_permission'] ??
              metadata['posting_permission'] ??
              metadata['postingPermission'])
          ?.toString();

      state = state.copyWith(
        currentUserId: myId,
        channelType: workflowEnabled
            ? 'workflow'
            : (channelRow?['type'] as String? ?? 'channel'),
        postingPermission: postingPermission == 'all'
            ? 'everyone'
            : (postingPermission ?? 'everyone'),
        createdBy: channelRow?['created_by'] as String?,
        currentUserRole: memberRow?['role'] as String?,
        currentUserDepartment: userRow?['department_id'] as String?,
        currentUserRoleLevel: userRow?['role_level'] as String?,
        metadata: metadata,
        // A coluna só existe após a migration 20260813110000; em banco antigo
        // o campo vem ausente e o canal segue notificando tudo, como antes.
        notificationLevel:
            memberRow?['notification_level']?.toString() ?? 'all',
        // Só na primeira carga: `_markAsRead()` avança `last_read_at` no banco
        // logo em seguida, e reler depois jogaria a régua para o fim.
        lastReadAt: state.lastReadAt ??
            (memberRow?['last_read_at'] != null
                ? DateTime.tryParse(memberRow!['last_read_at'].toString())
                    ?.toUtc()
                : null),
      );
    } catch (_) {
      debugPrint('Erro ignorado ao buscar metadados do canal');
    }
  }

  /// Troca a preferência de push do usuário neste canal.
  ///
  /// `all` recebe tudo, `mentions` só quando citado (direto ou via
  /// `@canal`/`@aqui`), `none` silencia. A Edge Function `send-chat-notification`
  /// aplica o filtro antes de disparar o FCM.
  Future<void> setNotificationLevel(String level) async {
    const allowed = {'all', 'mentions', 'none'};
    if (!allowed.contains(level)) {
      throw ArgumentError('Nível de notificação inválido: $level');
    }

    final previous = state.notificationLevel;
    state = state.copyWith(notificationLevel: level);

    try {
      await supabase.rpc('set_channel_notification_level', params: {
        'p_channel_id': channelId,
        'p_level': level,
      });
    } catch (e) {
      state = state.copyWith(notificationLevel: previous);
      debugPrint('Erro ao definir nível de notificação do canal: $e');
      rethrow;
    }
  }

  bool _isFetching = false;

  Future<void> _fetchMessages() async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      // ── OFFLINE CACHE ──
      // O cache é da régua principal; a tela de tópico sempre busca da rede.
      final cached = parentMessageId != null
          ? null
          : OfflineCacheService.getCachedChannelMessages(channelId);
      if (cached != null && cached.isNotEmpty) {
        final cachedUserCache = Map<String, UserModel>.from(state.userCache);
        for (final msg in cached) {
          if (!cachedUserCache.containsKey(msg.senderId)) {
            final u = OfflineCacheService.getCachedUser(msg.senderId);
            if (u != null) {
              cachedUserCache[msg.senderId] = u;
            }
          }
        }
        state = state.copyWith(
            messages: cached, isLoading: false, userCache: cachedUserCache);
        if (!SyncService().isConnected) {
          _isFetching = false;
          return;
        }
      }

      // Buscar da tabela dedicada de mensagens usando channel_id.
      // Sem `parentMessageId` carregamos a régua principal (thread_id nulo);
      // com ele, apenas as respostas daquele tópico.
      var query = supabase
          .from('channel_messages')
          .select(
              'id, channel_id, sender_id, content, content_type, media_url, metadata, is_bot, is_system, read_by, thread_id, reply_to, thread_reply_count, created_at, updated_at, deleted_at')
          .eq('channel_id', channelId);

      query = parentMessageId != null
          ? query.eq('thread_id', parentMessageId!)
          : query.isFilter('thread_id', null);

      final response =
          await query.order('created_at', ascending: false).limit(50);

      final List<ChannelMessageModel> msgs = [];
      final Set<String> neededUserIds = {};

      for (final row in (response as List)) {
        try {
          final msg =
              ChannelMessageModel.fromJson(Map<String, dynamic>.from(row));
          msgs.add(msg);
          if (!state.userCache.containsKey(msg.senderId)) {
            neededUserIds.add(msg.senderId);
          }
        } catch (e) {
          debugPrint(
              'Falha ao processar a conversão JSON em _fetchMessages: $e');
        }
      }

      final newUserCache = Map<String, UserModel>.from(state.userCache);

      if (neededUserIds.isNotEmpty) {
        try {
          final usersRes = await supabase
              .from('users')
              .select('id, full_name, avatar_url, department_id, role_level')
              .inFilter('id', neededUserIds.toList());

          for (final row in (usersRes as List)) {
            final u = UserModel.fromJson(Map<String, dynamic>.from(row));
            newUserCache[u.id] = u;
          }
        } catch (e) {
          debugPrint('Erro ignorado ao buscar usuarios no cache: $e');
        }
      }

      // P2: Cache Pruning

      if (msgs.isNotEmpty && parentMessageId == null) {
        OfflineCacheService.cacheChannelMessages(channelId, msgs);
      }

      state = state.copyWith(
          messages: msgs,
          isLoading: false,
          userCache: newUserCache,
          hasMoreMessages: msgs.length >= 50);
      unawaited(_hydrateQuotedMessages(msgs));
    } catch (e) {
      debugPrint('❌ Erro crítico ao buscar mensagens do canal: $e');
      state = state.copyWith(
          isLoading: false, messages: [], hasMoreMessages: false);
    } finally {
      _isFetching = false;
    }
  }

  /// Busca as mensagens citadas por `reply_to` que não estão na página atual,
  /// para que a bolha consiga desenhar o cartão de citação.
  Future<void> _hydrateQuotedMessages(List<ChannelMessageModel> msgs) async {
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
          .from('channel_messages')
          .select(
              'id, channel_id, sender_id, content, content_type, media_url, metadata, thread_id, reply_to, created_at, deleted_at')
          .inFilter('id', missing.toList());

      if (_disposed) return;

      final quoted =
          Map<String, ChannelMessageModel>.from(state.quotedMessages);
      final neededUserIds = <String>{};
      for (final row in (rows as List)) {
        try {
          final msg =
              ChannelMessageModel.fromJson(Map<String, dynamic>.from(row));
          quoted[msg.id] = msg;
          if (!state.userCache.containsKey(msg.senderId)) {
            neededUserIds.add(msg.senderId);
          }
        } catch (_) {}
      }

      final newUserCache = Map<String, UserModel>.from(state.userCache);
      if (neededUserIds.isNotEmpty) {
        try {
          final usersRes = await supabase
              .from('users')
              .select('id, full_name, avatar_url, department_id, role_level')
              .inFilter('id', neededUserIds.toList());
          for (final row in (usersRes as List)) {
            final u = UserModel.fromJson(Map<String, dynamic>.from(row));
            newUserCache[u.id] = u;
          }
        } catch (_) {}
      }

      if (_disposed) return;
      state = state.copyWith(quotedMessages: quoted, userCache: newUserCache);
    } catch (e) {
      debugPrint('Aviso: falha ao carregar mensagens citadas -> $e');
    }
  }

  /// Paginação sob demanda: carrega lote anterior de 50 mensagens mais antigas.
  Future<void> loadMoreMessages() async {
    if (state.isLoadingMore || !state.hasMoreMessages || state.messages.isEmpty) {
      return;
    }
    state = state.copyWith(isLoadingMore: true);
    try {
      final oldestMessage = state.messages.lastWhere(
        (m) => !m.isOptimistic,
        orElse: () => state.messages.last,
      );

      var query = supabase
          .from('channel_messages')
          .select(
              'id, channel_id, sender_id, content, content_type, media_url, metadata, is_bot, is_system, read_by, thread_id, reply_to, thread_reply_count, created_at, updated_at, deleted_at')
          .eq('channel_id', channelId)
          .lt('created_at', oldestMessage.createdAt.toIso8601String());

      query = parentMessageId != null
          ? query.eq('thread_id', parentMessageId!)
          : query.isFilter('thread_id', null);

      final response =
          await query.order('created_at', ascending: false).limit(50);

      final List<ChannelMessageModel> olderMsgs = [];
      final Set<String> neededUserIds = {};

      for (final row in (response as List)) {
        try {
          final msg =
              ChannelMessageModel.fromJson(Map<String, dynamic>.from(row));
          olderMsgs.add(msg);
          if (!state.userCache.containsKey(msg.senderId)) {
            neededUserIds.add(msg.senderId);
          }
        } catch (e) {
          debugPrint('Falha ao processar mensagem antiga: $e');
        }
      }

      final newUserCache = Map<String, UserModel>.from(state.userCache);
      if (neededUserIds.isNotEmpty) {
        try {
          final usersRes = await supabase
              .from('users')
              .select('id, full_name, avatar_url, department_id, role_level')
              .inFilter('id', neededUserIds.toList());

          for (final row in (usersRes as List)) {
            final u = UserModel.fromJson(Map<String, dynamic>.from(row));
            newUserCache[u.id] = u;
          }
        } catch (e) {
          debugPrint('Erro ao buscar usuários antigos no cache: $e');
        }
      }

      final existingIds = state.messages.map((m) => m.id).toSet();
      final filteredOlder =
          olderMsgs.where((m) => !existingIds.contains(m.id)).toList();

      final allMessages = [...state.messages, ...filteredOlder];
      state = state.copyWith(
        messages: allMessages,
        isLoadingMore: false,
        hasMoreMessages: olderMsgs.length >= 50,
        userCache: newUserCache,
      );
      unawaited(_hydrateQuotedMessages(olderMsgs));
    } catch (e) {
      debugPrint('Erro ao carregar mensagens anteriores: $e');
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Exposto para Pull-to-Refresh na UI
  Future<void> refreshMessages() async {
    await _fetchMessages();
  }

  Future<void> refreshChannelMetadata() async {
    await _fetchChannelMetadata();
  }

  /// Janela do stream da régua principal. A tela mostra 50 mensagens; a folga
  /// cobre respostas de tópico, que ocupam a janela mas são filtradas abaixo.
  static const _timelineStreamWindow = 200;

  void _subscribeToChannel() {
    final base = supabase
        .from('channel_messages')
        .stream(primaryKey: ['id'])
        .eq('channel_id', channelId);
    // Sem ordem e limite o stream baixava o canal inteiro a cada conexão, e o
    // PostgREST corta em 1000 linhas SEM ordem garantida: em canal grande as
    // mensagens mais novas podiam ficar de fora da tela. No tópico o stream
    // continua sem limite — respostas antigas sairiam da janela e sumiriam.
    final stream = parentMessageId == null
        ? base
            .order('created_at', ascending: false)
            .limit(_timelineStreamWindow)
        : base;
    final sub = stream.listen(
          (rows) async {
            if (_disposed) return;

            // O stream do Supabase aceita um único filtro (channel_id), então
            // a separação régua principal x tópico é feita aqui.
            final scopedRows = rows.where((row) {
              final threadId = row['thread_id']?.toString();
              return parentMessageId != null
                  ? threadId == parentMessageId
                  : threadId == null;
            });

            // Ordenação Client-Side (Performance)
            final sortedRows = List<Map<String, dynamic>>.from(scopedRows);
            sortedRows.sort((a, b) {
              final aTime =
                  DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                      DateTime.now();
              final bTime =
                  DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                      DateTime.now();
              return bTime.compareTo(aTime); // Descending
            });

            // Pega os 50 mais recentes
            final limitedRows = sortedRows.take(50).toList();

            final List<ChannelMessageModel> msgs = [];
            final Set<String> neededUserIds = {};

            for (final row in limitedRows) {
              try {
                final msg = ChannelMessageModel.fromJson(row);
                msgs.add(msg);
                if (!state.userCache.containsKey(msg.senderId)) {
                  neededUserIds.add(msg.senderId);
                }
              } catch (e) {
                // ignorar json error local
              }
            }

            final newUserCache = Map<String, UserModel>.from(state.userCache);
            if (neededUserIds.isNotEmpty) {
              try {
                final usersRes = await supabase
                    .from('users')
                    .select(
                        'id, full_name, avatar_url, department_id, role_level')
                    .inFilter('id', neededUserIds.toList());

                for (final row in (usersRes as List)) {
                  final u = UserModel.fromJson(Map<String, dynamic>.from(row));
                  newUserCache[u.id] = u;
                }
              } catch (e) {
                // ignora
              }
            }

            // Mesclar com as mensagens otimistas locais (que ainda não vieram no stream)
            final optimisticMessages =
                state.messages.where((m) => m.isOptimistic).toList();

            final mergedMessages = [...optimisticMessages];
            for (var msg in msgs) {
              if (!mergedMessages.any((m) => m.id == msg.id)) {
                mergedMessages.add(msg);
              }
            }
            // Preserva as mensagens anteriores que foram paginadas pelo usuário
            for (var msg in state.messages) {
              if (!msg.isOptimistic && !mergedMessages.any((m) => m.id == msg.id)) {
                mergedMessages.add(msg);
              }
            }

            // Re-ordena o resultado final para garantir que as otimistas (mais novas) fiquem no topo
            mergedMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));

            state = state.copyWith(
                messages: mergedMessages, userCache: newUserCache);
            unawaited(_hydrateQuotedMessages(mergedMessages));
            _scheduleMarkAsRead();
          },
          onError: (error) {
            debugPrint('Erro no stream de canais: $error');
            Future.delayed(const Duration(seconds: 5), () {
              if (!_disposed) _fetchMessages();
            });
          },
        );

    ref.onDispose(() {
      sub.cancel();
    });
  }

  final _media = MediaService();

  void _updateOptimisticProgress(String tempId, double progress) {
    final newList = state.messages.map((m) {
      if (m.id == tempId) {
        return m.copyWith(
          metadata: MessageMetadata.fromMap({
            ...m.metadata.toMap(),
            'upload_progress': progress,
          }),
        );
      }
      return m;
    }).toList();
    state = state.copyWith(messages: newList);
  }

  void _replaceOptimistic(String tempId, ChannelMessageModel finalMsg) {
    final newList = state.messages.map((m) {
      if (m.id == tempId) return finalMsg;
      return m;
    }).toList();

    // Fallback: se a real-time já inseriu, removemos a duplicata temporária.
    final hasReal = newList.where((m) => m.id == finalMsg.id).length > 1;
    if (hasReal) {
      newList.removeWhere((m) => m.id == tempId);
    }

    state = state.copyWith(messages: newList);
  }

  void _markError(String tempId) {
    final newList = state.messages.map((m) {
      if (m.id == tempId) return m.copyWith(isError: true);
      return m;
    }).toList();
    state = state.copyWith(messages: newList);
  }

  /// [caption] vira o corpo da mensagem, como legenda da mídia.
  Future<void> sendImage(XFile file, {String? caption}) async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final isVideo = file.path.toLowerCase().endsWith('.mp4') ||
        file.path.toLowerCase().endsWith('.mov');
    final replyingTo = state.replyingTo;

    final optimistic = ChannelMessageModel(
      id: tempId,
      channelId: channelId,
      senderId: myId,
      content: caption,
      contentType: isVideo ? 'video' : 'image',
      createdAt: DateTime.now().toUtc(),
      localFilePath: file.path,
      isOptimistic: true,
      replyTo: replyingTo?.id,
      parentMessageId: parentMessageId,
      metadata: MessageMetadata.fromMap({'upload_progress': 0.0}),
    );

    state = state.copyWith(messages: [optimistic, ...state.messages]);
    if (replyingTo != null) clearReply();

    if (!SyncService().isConnected) {
      _markError(tempId);
      return;
    }

    try {
      final uploadResult = isVideo
          ? await _media.uploadFile(
              chatId: channelId,
              file: file,
              mimeType: 'video/mp4',
              onProgress: (p) => _updateOptimisticProgress(tempId, p),
            )
          : await _media.compressAndUploadImage(
              chatId: channelId,
              file: file,
              onProgress: (p) => _updateOptimisticProgress(tempId, p),
            );

      final insertData = {
        'channel_id': channelId,
        'sender_id': myId,
        'content_type': isVideo ? 'video' : 'image',
        'content': caption?.trim().isNotEmpty == true ? caption!.trim() : '',
        'media_url': uploadResult.publicUrl,
        'metadata': MessageMetadata.media(
          mimeType: uploadResult.mimeType,
          sizeBytes: uploadResult.sizeBytes,
        ).toMap(),
        ..._replyFields(replyingTo),
      };

      final result = await supabase
          .from('channel_messages')
          .insert(insertData)
          .select()
          .single();

      await MediaCacheManager.cacheLocalFile(
        localPath: file.path,
        mediaUrl: uploadResult.publicUrl,
        messageId: result['id'],
        chatId: channelId,
        mediaType: isVideo ? 'video' : 'image',
      );

      _replaceOptimistic(tempId, ChannelMessageModel.fromJson(result));
    } catch (e) {
      debugPrint('Erro ao enviar imagem/video no canal: $e');
      _markError(tempId);
    }
  }

  Future<void> sendDocument(XFile file) async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final replyingTo = state.replyingTo;

    final optimistic = ChannelMessageModel(
      id: tempId,
      channelId: channelId,
      senderId: myId,
      contentType: 'file',
      content: file.name,
      createdAt: DateTime.now().toUtc(),
      localFilePath: file.path,
      isOptimistic: true,
      replyTo: replyingTo?.id,
      parentMessageId: parentMessageId,
      metadata: MessageMetadata.fromMap({'upload_progress': 0.0}),
    );

    state = state.copyWith(messages: [optimistic, ...state.messages]);
    if (replyingTo != null) clearReply();

    if (!SyncService().isConnected) {
      _markError(tempId);
      return;
    }

    try {
      final uploadResult = await _media.uploadFile(
        chatId: channelId,
        file: file,
        mimeType: 'application/octet-stream', // Fallback
        onProgress: (p) => _updateOptimisticProgress(tempId, p),
      );

      final insertData = {
        'channel_id': channelId,
        'sender_id': myId,
        'content_type': 'file',
        'content': file.name,
        'media_url': uploadResult.publicUrl,
        'metadata': MessageMetadata.media(
          mimeType: uploadResult.mimeType,
          sizeBytes: uploadResult.sizeBytes,
        ).toMap(),
        ..._replyFields(replyingTo),
      };

      final result = await supabase
          .from('channel_messages')
          .insert(insertData)
          .select()
          .single();

      if (file.path.isNotEmpty) {
        await MediaCacheManager.cacheLocalFile(
          localPath: file.path,
          mediaUrl: uploadResult.publicUrl,
          messageId: result['id'],
          chatId: channelId,
          mediaType: 'document',
        );
      }

      _replaceOptimistic(tempId, ChannelMessageModel.fromJson(result));
    } catch (e) {
      debugPrint('Erro ao enviar documento no canal: $e');
      _markError(tempId);
    }
  }

  /// Sobe um arquivo avulso e devolve a URL pública, sem criar mensagem.
  ///
  /// O anexo do anúncio precisa da URL antes de gravar a mensagem — vai para
  /// a mesma pasta do canal usada por `sendDocument`, então as políticas de
  /// storage já valem sem ajuste.
  Future<String?> uploadAttachment(XFile file) async {
    try {
      final result = await _media.uploadFile(
        chatId: channelId,
        file: file,
        mimeType: 'application/octet-stream',
      );
      return result.publicUrl;
    } catch (e) {
      debugPrint('Erro ao subir anexo no canal: $e');
      return null;
    }
  }

  Future<void> sendMessage(String text,
      {Map<String, dynamic>? metadata}) async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    if (text.trim().isEmpty) {
      // Feedback opicional via exception ou flag no estado
      // Aqui usamos throw para que o widget capture e mostre SnackBar
      throw Exception('A mensagem não pode estar vazia.');
    }

    final replyingTo = state.replyingTo;

    final Map<String, dynamic> insertData = {
      'channel_id': channelId,
      'sender_id': myId,
      'content': text.trim(),
      'content_type': 'text',
      ..._replyFields(replyingTo),
    };

    if (metadata != null && metadata.isNotEmpty) {
      insertData['metadata'] = metadata;
    }

    // ── Parse de Menções (@NomeCompleto, @canal, @aqui) ──
    final parsed = await _parseMentions(text);
    if (parsed.userIds.isNotEmpty || parsed.everyone) {
      insertData['metadata'] = {
        ...?(insertData['metadata'] as Map<String, dynamic>?),
        if (parsed.userIds.isNotEmpty) 'mentions': parsed.userIds,
        if (parsed.everyone) 'mentions_everyone': true,
      };
    }

    if (!SyncService().isConnected) {
      debugPrint('📡 [ActiveChannel] Offline. Enfileirando mensagem de canal.');
      final syntheticId = DateTime.now().millisecondsSinceEpoch.toString();

      await OfflineCacheService.enqueueOperation({
        'temp_id': syntheticId,
        'type': 'insert_channel_message',
        'payload': insertData,
      });

      insertData['id'] = syntheticId;
      insertData['created_at'] = DateTime.now().toUtc().toIso8601String();
      insertData['updated_at'] = DateTime.now().toUtc().toIso8601String();

      try {
        final msg = ChannelMessageModel.fromJson(insertData);
        state = state.copyWith(messages: [msg, ...state.messages]);
      } catch (_) {}
      if (replyingTo != null) clearReply();
      return;
    }

    final result = await supabase
        .from('channel_messages')
        .insert(insertData)
        .select()
        .single();

    // A resposta só é consumida quando o envio conclui: se o insert falhar, o
    // preview continua na barra e o usuário pode tentar de novo.
    if (replyingTo != null) clearReply();

    try {
      final msg = ChannelMessageModel.fromJson(result);
      final exists = state.messages.any((m) => m.id == msg.id);
      if (!exists) {
        state = state.copyWith(messages: [msg, ...state.messages]);
      }
    } catch (e) {
      debugPrint('Erro ao atualizar UI local após texto: $e');
    }
  }

  /// Apelidos que citam o canal inteiro. Gravam `mentions_everyone` no
  /// metadata, e é isso que faz a mensagem furar o nível "somente menções".
  static const Set<String> everyoneMentionAliases = {
    'canal',
    'todos',
    'aqui',
    'channel',
    'here',
    'everyone',
  };

  /// Extrai de um texto quem foi citado: ids de membros e se cita todo o canal.
  Future<({List<String> userIds, bool everyone})> _parseMentions(
      String text) async {
    final trimmed = text.trim();
    final mentionRegex = RegExp(r'@([a-zA-ZÀ-ú0-9_]+(?:\s+[a-zA-ZÀ-ú0-9_]+)*)');
    final matches = mentionRegex
        .allMatches(trimmed)
        .where((m) => (m.group(1)?.length ?? 0) <= 50)
        .take(10)
        .toList();

    if (matches.isEmpty) {
      return (userIds: const <String>[], everyone: false);
    }

    var everyone = false;
    final names = <String>[];
    for (final match in matches) {
      final raw = match.group(1)!;
      // `@canal` seguido de texto ("@canal pessoal") casa a frase inteira no
      // regex, então a checagem é sobre a primeira palavra.
      final firstWord = raw.split(RegExp(r'\s+')).first.toLowerCase();
      if (everyoneMentionAliases.contains(firstWord)) {
        everyone = true;
      } else {
        names.add(raw);
      }
    }

    if (names.isEmpty) {
      return (userIds: const <String>[], everyone: everyone);
    }

    try {
      final ids = await _resolveMentions(names);
      return (userIds: ids, everyone: everyone);
    } catch (e) {
      debugPrint('Aviso: Falha ao resolver menções no canal -> $e');
      return (userIds: const <String>[], everyone: everyone);
    }
  }

  /// Resolve nomes mencionados para UUIDs consultando os membros do canal.
  Future<List<String>> _resolveMentions(List<String> names) async {
    final membersRes = await supabase
        .from('channel_members')
        .select('user_id')
        .eq('channel_id', channelId);

    final memberIds =
        (membersRes as List).map((m) => m['user_id'] as String).toList();

    if (memberIds.isEmpty) return [];

    final usersRes = await supabase
        .from('users')
        .select('id, full_name')
        .inFilter('id', memberIds);

    final ids = <String>[];
    for (final user in (usersRes as List)) {
      final fullName = user['full_name'] as String? ?? '';
      for (final name in names) {
        if (fullName.toLowerCase() == name.toLowerCase().trim()) {
          ids.add(user['id'] as String);
        }
      }
    }
    return ids;
  }

  // ── GOVERNANÇA ROOT (TI) ──

  /// Deleta completamente o canal em cascata:
  /// 1. Remove mídia do Supabase Storage (imagens/docs enviados no canal)
  /// 2. Chama RPC que limpa messages → chat_members → chats
  /// Soft delete de mensagem do canal (marca `deleted_at`; a bolha passa a
  /// mostrar "mensagem apagada").
  ///
  /// Vai por RPC `SECURITY DEFINER`: `channel_messages` tem RLS com policies
  /// apenas de SELECT e INSERT, então o `UPDATE` direto que existia aqui
  /// afetava zero linhas sem levantar erro — a bolha sumia da tela e voltava no
  /// próximo fetch. A RPC valida autor ou moderador do workspace.
  Future<void> deleteMessage(String messageId) async {
    final backup = List<ChannelMessageModel>.from(state.messages);
    state = state.copyWith(
      messages: state.messages
          .map((m) =>
              m.id == messageId ? m.copyWith(deletedAt: DateTime.now()) : m)
          .toList(),
    );

    try {
      await supabase.rpc('delete_channel_message', params: {
        'p_message_id': messageId,
      });
    } catch (e) {
      debugPrint('Erro ao apagar mensagem do canal: $e');
      state = state.copyWith(messages: backup);
      rethrow;
    }
  }

  /// Edita o texto (ou a legenda de mídia) de uma mensagem própria do canal.
  ///
  /// O trigger `fn_channel_messages_guard_immutable` carimba `edited_at`, que a
  /// bolha já exibe como "• editado". Anúncios e enquetes são recusados pela
  /// RPC porque carregam estado próprio (ciência, votos).
  Future<void> editMessage(String messageId, String newContent) async {
    final trimmed = newContent.trim();
    if (trimmed.isEmpty) {
      throw Exception('A mensagem não pode ficar vazia.');
    }

    final backup = List<ChannelMessageModel>.from(state.messages);
    state = state.copyWith(
      messages: state.messages
          .map((m) => m.id == messageId
              ? m.copyWith(content: trimmed, editedAt: DateTime.now().toUtc())
              : m)
          .toList(),
    );

    try {
      final parsed = await _parseMentions(trimmed);
      await supabase.rpc('edit_channel_message', params: {
        'p_message_id': messageId,
        'p_content': trimmed,
        'p_mentions': parsed.userIds,
        'p_mentions_everyone': parsed.everyone,
      });
    } catch (e) {
      debugPrint('Erro ao editar mensagem do canal: $e');
      state = state.copyWith(messages: backup);
      rethrow;
    }
  }

  Future<void> deleteChannel() async {
    if (!state.canGovernChannel) {
      throw Exception('Sem permissão para excluir este canal.');
    }
    try {
      // 1. Levanta os arquivos ANTES de apagar: depois da RPC as mensagens
      // que apontam para eles já não existem.
      final List<String> storagePaths = [];
      try {
        final mediaMessages = await supabase
            .from('channel_messages')
            .select('media_url')
            .eq('channel_id', channelId)
            .not('media_url', 'is', null);

        for (final row in mediaMessages) {
          final url = row['media_url'] as String?;
          if (url != null && url.contains('/chat-media/')) {
            // Extrai o path relativo ao bucket: "chats/channelId/uuid.ext"
            final parts = url.split('/chat-media/');
            if (parts.length > 1) {
              storagePaths.add(parts.last.split('?').first);
            }
          }
        }
      } catch (listErr) {
        debugPrint('⚠️ Erro ao listar mídia do canal: $listErr');
      }

      // 2. Exclui no banco. Vem antes do Storage: se a RPC recusar (sem
      // permissão, rede), o canal continua íntegro. Na ordem antiga os
      // arquivos já tinham sido apagados e o canal ficava com anexos
      // quebrados.
      await supabase.rpc('delete_channel', params: {'p_channel_id': channelId});

      // 3. Só então remove os arquivos (em lotes, limite da API de Storage).
      for (var i = 0; i < storagePaths.length; i += 100) {
        final batch = storagePaths.sublist(
            i, i + 100 > storagePaths.length ? storagePaths.length : i + 100);
        try {
          await supabase.storage.from('chat-media').remove(batch);
        } catch (storageErr) {
          debugPrint('⚠️ Erro ao limpar Storage (não-bloqueante): $storageErr');
        }
      }
    } catch (e) {
      debugPrint('Erro ao excluir canal via RPC: $e');
      rethrow;
    }
  }

  /// Limpa todos os membros do canal usando RPC, isolando-o para auditoria
  Future<void> archiveChannel() async {
    if (!state.canGovernChannel) {
      throw Exception('Sem permissão para arquivar este canal.');
    }
    try {
      await supabase
          .rpc('archive_channel', params: {'p_channel_id': channelId});
    } catch (e) {
      debugPrint('Erro ao arquivar canal via RPC: $e');
      rethrow;
    }
  }

  Future<void> updateWorkflowOperators({
    required String assignmentMode,
    required List<String> operatorIds,
    String? defaultOperatorId,
  }) async {
    if (!state.canGovernChannel &&
        state.currentUserRoleLevel != 'super_admin') {
      throw Exception('Sem permissao para gerenciar operadores deste canal.');
    }

    try {
      await supabase.rpc('update_workflow_operators', params: {
        'p_channel_id': channelId,
        'p_assignment_mode': assignmentMode,
        'p_operator_ids': operatorIds,
        'p_default_operator_id': defaultOperatorId,
      });
      await _fetchChannelMetadata();
    } catch (e) {
      debugPrint('Erro ao atualizar operadores do workflow: $e');
      rethrow;
    }
  }

  /// Agenda a marcação de leitura, colapsando rajadas do stream num só UPDATE.
  void _scheduleMarkAsRead() {
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(_markReadDelay, () {
      if (_disposed) return;
      _markAsRead();
    });
  }

  Future<void> _markAsRead() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      await supabase
          .from('channel_members')
          .update({
            'last_read_at': DateTime.now().toUtc().toIso8601String(),
            'unread_count': 0
          })
          .eq('channel_id', channelId)
          .eq('user_id', myId);
    } catch (e) {
      debugPrint('Erro ao marcar mensagens do canal como lidas: $e');
      // Não rethrow para não quebrar o fluxo da UI, mas registramos
    }
  }
}

final activeChannelProvider =
    NotifierProvider.family<ActiveChannelNotifier, ChannelState, ChannelArgs>(
  ActiveChannelNotifier.new,
);
