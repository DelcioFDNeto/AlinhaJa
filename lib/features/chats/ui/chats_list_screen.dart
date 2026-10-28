import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType,
        RealtimeSubscribeStatus;
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/extensions.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/chats/models/chat_model.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/core/providers/presence_service.dart';
import 'package:alinha_ja/core/ui/responsive_layout.dart';
import 'package:alinha_ja/core/providers/desktop_selection_provider.dart';

// ─── Provider da lista de chats (Realtime + RPC otimizado) ──

/// Confirma a entrega ('sent' → 'delivered') de todas as mensagens que
/// chegaram para o usuário. É o equivalente ao segundo check do WhatsApp:
/// a mensagem chegou ao destinatário, mas ainda não foi aberta.
///
/// O UPDATE só atinge linhas com status 'sent', então repetir a chamada é
/// inofensivo (nenhuma linha alterada ⇒ nenhum evento de realtime ⇒ sem loop).
Future<void> _markIncomingAsDelivered(String userId) async {
  try {
    await supabase.rpc('mark_messages_as_delivered', params: {
      'p_user_id': userId,
    });
  } catch (e) {
    debugPrint('⚠️ Erro ao confirmar entrega de mensagens: $e');
  }
}

/// Realtime da lista de conversas: um canal só, vivo enquanto houver sessão,
/// que apenas manda a lista recarregar (RPC `get_chats_with_preview`).
///
/// Antes a própria lista assinava `messages.stream()` sem filtro nem limite e
/// se invalidava a cada evento — cada mensagem, edição ou recibo de leitura,
/// em qualquer conversa, derrubava a assinatura e BAIXAVA DE NOVO todas as
/// mensagens visíveis ao usuário. `onPostgresChanges` não traz snapshot.
final Provider<void> _chatsListRealtimeProvider = Provider<void>((ref) {
  ref.watch(authStateProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;

  Timer? debounce;
  var confirmDelivery = false;
  var subscribedOnce = false;

  // Rajadas (ex.: um recibo de leitura altera dezenas de linhas) viram um
  // único recarregamento.
  void schedule({bool delivery = false}) {
    confirmDelivery = confirmDelivery || delivery;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), () async {
      if (confirmDelivery) {
        confirmDelivery = false;
        // Segundo check do remetente: a mensagem chegou a este aparelho.
        await _markIncomingAsDelivered(userId);
      }
      ref.invalidate(chatsListProvider);
    });
  }

  final channel = supabase
      .channel('chats_list:$userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        callback: (payload) => schedule(
          delivery: payload.eventType == PostgresChangeEvent.insert &&
              payload.newRecord['sender_id'] != userId,
        ),
      )
      // Conversa nova criada por OUTRA pessoa comigo (DM ou grupo) e o
      // meu last_read_at (badge de não lidas).
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'chat_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (_) => schedule(),
      )
      .subscribe((status, _) {
        if (status != RealtimeSubscribeStatus.subscribed) return;
        // Reconexão (ex.: app voltou do segundo plano): o que chegou no
        // intervalo não gerou evento, então recarrega e confirma a entrega.
        if (subscribedOnce) schedule(delivery: true);
        subscribedOnce = true;
      });

  ref.onDispose(() {
    debounce?.cancel();
    supabase.removeChannel(channel);
  });

  // Confirma a entrega do que chegou com o app fechado/offline. Só muda o
  // check de quem enviou; a lista daqui não precisa recarregar.
  unawaited(_markIncomingAsDelivered(userId));
});

final FutureProvider<List<ChatModel>> chatsListProvider =
    FutureProvider<List<ChatModel>>((ref) async {
  // Observa mudanças de auth para invalidar o cache de chats
  // caso haja troca de conta (logout/login)
  ref.watch(authStateProvider);
  ref.watch(_chatsListRealtimeProvider);

  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  // Chama a RPC otimizada que retorna tudo em UMA query
  try {
    final result = await supabase.rpc('get_chats_with_preview');

    if (result == null) return [];

    final List<dynamic> rawChats = result is List ? result : [];

    final List<ChatModel> chats = [];
    for (final c in rawChats) {
      try {
        final chatJson = c as Map<String, dynamic>;
        final chat = ChatModel.fromJson(chatJson);

        // Parse da última mensagem
        // A RPC não retorna chat_id dentro de last_message (é redundante),
        // então injetamos o id do chat pai antes de parsear.
        MessageModel? lastMsg;
        if (chatJson['last_message'] != null) {
          final msgMap = Map<String, dynamic>.from(
            chatJson['last_message'] as Map<String, dynamic>,
          );
          msgMap['chat_id'] ??= chat.id; // Injeta chat_id se ausente
          lastMsg = MessageModel.fromJson(msgMap);
        }

        // Parse do outro usuário em DMs
        UserModel? other;
        if (chatJson['other_user'] != null) {
          other = UserModel.fromJson(
            chatJson['other_user'] as Map<String, dynamic>,
          );
        }

        // Recibo de leitura dos demais membros (para o check azul)
        final otherReadRaw = chatJson['other_read_at'] as String?;
        final otherReadAt =
            otherReadRaw != null ? DateTime.tryParse(otherReadRaw) : null;

        chats.add(chat.copyWith(
          lastMessage: lastMsg,
          unreadCount: (chatJson['unread_count'] as int?) ?? 0,
          otherUser: other,
          otherReadAt: otherReadAt,
        ));
      } catch (e) {
        debugPrint('⚠️ Ignorando chat com dados inválidos: $e');
      }
    }
    // Exibe apenas chats que já tiveram pelo menos uma mensagem trocada
    chats.removeWhere((chat) => chat.lastMessage == null);
    return chats;
  } catch (e) {
    // Loga o erro para diagnóstico — A RPC deve estar presente no banco.
    debugPrint('⚠️ Erro ao carregar chats via RPC: $e');
    return [];
  }
});

// ─── Provider de Chamadas em Andamento Global ───────────────

final activeCallsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return Stream.value([]);

  final controller = StreamController<List<Map<String, dynamic>>>();

  // Função auxiliar para filtrar chamadas ativas
  List<Map<String, dynamic>> filterActiveCalls(
      List<Map<String, dynamic>> calls) {
    final now = DateTime.now().toUtc();
    return calls.where((call) {
      final status = call['status'];
      if (status != 'in_progress' && status != 'ringing') return false;

      try {
        final createdAtStr = call['created_at'] ?? call['started_at'];
        if (createdAtStr != null) {
          final createdAt = DateTime.parse(createdAtStr).toUtc();
          if (now.difference(createdAt).inHours > 4) return false;
        }
      } catch (_) {}

      return true;
    }).toList();
  }

  // Stream de chamadas de áudio (tabela calls)
  final callsStream = supabase
      .from('calls')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(50);

  // Stream de videochamadas (tabela meetings)
  final meetingsStream = supabase
      .from('meetings')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(50);

  // Combina os streams usando Rx.combineLatest equivalente
  List<Map<String, dynamic>> cachedCalls = [];
  List<Map<String, dynamic>> cachedMeetings = [];

  callsStream.listen((calls) {
    cachedCalls = filterActiveCalls(calls);
    controller.add([...cachedCalls, ...cachedMeetings]);
  });

  meetingsStream.listen((meetings) {
    cachedMeetings = filterActiveCalls(meetings);
    controller.add([...cachedCalls, ...cachedMeetings]);
  });

  ref.onDispose(() {
    controller.close();
  });

  return controller.stream;
});

// ─── Tela de lista de chats ─────────────────────────────────

class ChatsListScreen extends ConsumerWidget {
  const ChatsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsListProvider);

    return Scaffold(
      body: Column(
        children: [
          // Banner de conectividade
          StreamBuilder<List<ConnectivityResult>>(
            stream: Connectivity().onConnectivityChanged,
            builder: (context, snap) {
              final results = snap.data ?? [ConnectivityResult.wifi];
              final isOffline =
                  results.every((r) => r == ConnectivityResult.none);
              if (!isOffline) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: AppConstants.danger,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Sem conexão com a internet',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            },
          ),

          // Banner Global de Chamadas Ativas
          Consumer(
            builder: (context, ref, child) {
              final activeCallsAsync = ref.watch(activeCallsProvider);
              final activeCalls = activeCallsAsync.valueOrNull ?? [];

              if (activeCalls.isEmpty) return const SizedBox.shrink();

              // Pega a primeira chamada ativa para exibir (pode ser adaptado para exibir várias)
              final call = activeCalls.first;
              final chatId = call['chat_id'] as String?;

              // Determina o canal: meetings usa 'room_id', calls usa 'provider_room_id'
              final channelName =
                  call['room_id'] ?? call['provider_room_id'] ?? 'call_$chatId';

              // Determina se é videochamada
              final isVideo =
                  call['room_id'] != null || call['type'] == 'video';

              // Buscamos o nome do chat no cache já carregado de chatsListProvider
              final chatsList = ref.read(chatsListProvider).valueOrNull ?? [];
              final chat = chatsList.where((c) => c.id == chatId).firstOrNull;

              final chatName = chat?.displayName ?? 'Um grupo';

              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.teal.shade800,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                          isVideo
                              ? Icons.videocam_rounded
                              : Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$chatName ${isVideo ? 'em videochamada' : 'em ligação'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const Text(
                            'Toque para entrar agora',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent.shade400,
                        foregroundColor: Colors.teal.shade900,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: () async {
                        final stringCallId = call['id']?.toString() ?? '';
                        // Junta o usuário na chamada configurando o estado
                        await CallService.instance.joinOngoingCall(stringCallId,
                            channelName, chatName, chatId ?? '', isVideo);
                        if (context.mounted) {
                          context.push(
                            '/call/${chatId ?? ''}',
                            extra: {'callerName': chatName, 'isVideo': isVideo},
                          );
                        }
                      },
                      child: const Text('Entrar',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
          ),

          // Lista de chats
          Expanded(
            child: chats.when(
              loading: () => _buildShimmerLoading(),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (allList) {
                // Filtra canais — eles têm sua própria aba
                final list =
                    allList.where((c) => c.type != ChatType.channel).toList();
                if (list.isEmpty) return const _EmptyState();
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(chatsListProvider.future),
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 80),
                    itemBuilder: (context, index) {
                      final chat = list[index];
                      return _ChatTile(
                        key: ValueKey(chat.id),
                        chat: chat,
                        onTap: () async {
                          final isDesktop = MediaQuery.of(context).size.width >=
                              kDesktopBreakpoint;
                          if (isDesktop) {
                            ProviderScope.containerOf(context)
                                    .read(desktopSelectionProvider.notifier)
                                    .state =
                                chat.type == ChatType.channel
                                    ? DesktopSelection.channel(
                                        chat.id, chat.displayName)
                                    : DesktopSelection.chat(
                                        chat.id, chat.displayName,
                                        isGroup: chat.type == ChatType.group);
                          } else {
                            await context.push(
                              '/chat/${chat.id}',
                              extra: {
                                'name': chat.displayName,
                                'isGroup': chat.type == ChatType.group,
                                'isChannel': chat.type == ChatType.channel,
                              },
                            );
                            ref.invalidate(chatsListProvider);
                          }
                        },
                        onLongPress: () {
                          _showChatOptions(context, chat);
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding:
            EdgeInsets.only(bottom: 72 + MediaQuery.of(context).padding.bottom),
        child: FloatingActionButton(
          heroTag: null,
          onPressed: () => context.push('/contacts'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Icon(Icons.chat_bubble_outline_rounded,
              color: Theme.of(context).colorScheme.onPrimary),
        ),
      ),
    );
  }

  static Widget _buildShimmerLoading() {
    return Builder(builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Shimmer.fromColors(
        baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
        child: ListView.builder(
          itemCount: 8,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                    radius: 26,
                    backgroundColor: Theme.of(context).colorScheme.surface),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          height: 14,
                          width: 140,
                          color: Theme.of(context).colorScheme.surface),
                      const SizedBox(height: 6),
                      Container(
                          height: 12,
                          width: 200,
                          color: Theme.of(context).colorScheme.surface),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  void _showChatOptions(BuildContext context, ChatModel chat) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(
                  chat.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                    chat.isPinned ? 'Desafixar conversa' : 'Fixar conversa'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final currentUserId = supabase.auth.currentUser?.id;
                    if (currentUserId == null) return;

                    await supabase
                        .from('chat_members')
                        .update({'is_pinned': !chat.isPinned})
                        .eq('chat_id', chat.id)
                        .eq('user_id', currentUserId);
                    // A revalidação ocorrerá automaticamente via realtime stream
                  } catch (e) {
                    debugPrint('Erro ao fixar/desafixar chat: $e');
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Tile de chat ────────────────────────────────────────────

class _ChatTile extends ConsumerWidget {
  final ChatModel chat;
  final GestureTapCallback onTap;
  final GestureLongPressCallback? onLongPress;

  const _ChatTile(
      {super.key, required this.chat, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = chat.type == ChatType.direct
        ? chat.otherUser?.avatarUrl
        : chat.avatarUrl;
    final name = chat.displayName;

    Widget leadingWidget;
    if (chat.type == ChatType.channel) {
      leadingWidget = CircleAvatar(
        radius: 26,
        backgroundColor: Colors.orange,
        child: Icon(Icons.campaign_rounded,
            color: Theme.of(context).colorScheme.onPrimary, size: 24),
      );
    } else if (chat.type == ChatType.group) {
      leadingWidget = CircleAvatar(
        radius: 26,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        backgroundImage:
            avatar != null ? CachedNetworkImageProvider(avatar, maxWidth: 320) : null,
        child: avatar == null
            ? Icon(Icons.groups_rounded,
                color: Theme.of(context).colorScheme.primary, size: 28)
            : null,
      );
    } else {
      final otherUserId = chat.otherUser?.id;
      final isOnline = chat.otherUser != null &&
          (chat.otherUser!.isActuallyOnline ||
              (otherUserId != null &&
                  ref.watch(onlineUsersProvider
                      .select((set) => set.contains(otherUserId)))));

      leadingWidget = _Avatar(
        uri: avatar,
        name: name,
        isOnline: isOnline,
      );
    }

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: leadingWidget,
      title: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontWeight: chat.unreadCount > 0
                          ? FontWeight.w700
                          : FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (chat.isPinned)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          if (chat.lastMessage != null)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                chat.lastMessage!.createdAt.toLocal().chatListFormatted,
                style: TextStyle(
                  fontSize: 12,
                  color: chat.unreadCount > 0
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                  fontWeight: chat.unreadCount > 0
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          if (chat.lastMessage != null && chat.lastMessage!.senderId == supabase.auth.currentUser?.id)
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: _buildStatusTick(context, chat),
            ),
          Expanded(
            child: Text(
              _preview(chat.lastMessage),
              style: TextStyle(
                color: chat.unreadCount > 0
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.outline,
                fontWeight:
                    chat.unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (chat.unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Indicador de status da última mensagem enviada por mim.
  ///
  /// Segue a mesma convenção da bolha dentro da conversa:
  /// relógio = enviando · 1 check = enviado · 2 checks = entregue ·
  /// 2 checks azuis = lido.
  Widget _buildStatusTick(BuildContext context, ChatModel chat) {
    final msg = chat.lastMessage!;
    final theme = Theme.of(context);

    if (msg.status == MessageStatus.error) {
      return Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error);
    }
    if (msg.status == MessageStatus.sending) {
      return Icon(Icons.access_time, size: 16, color: theme.colorScheme.outline);
    }

    // Leitura: ou o status já veio como 'read', ou o recibo do outro membro
    // é posterior à mensagem (cobre grupos, onde o status não é por membro).
    final readAt = chat.otherReadAt;
    final isRead = msg.status == MessageStatus.read ||
        (readAt != null && !msg.createdAt.toUtc().isAfter(readAt.toUtc()));

    if (isRead) {
      return const Icon(Icons.done_all, size: 16, color: Color(0xFF00B4D8));
    }
    if (msg.status == MessageStatus.delivered) {
      return Icon(Icons.done_all, size: 16, color: theme.colorScheme.outline);
    }
    return Icon(Icons.check, size: 16, color: theme.colorScheme.outline);
  }

  String _preview(MessageModel? msg) {
    if (msg == null) return 'Nenhuma mensagem ainda';
    switch (msg.contentType) {
      case ContentType.image:
        return '📷 Foto';
      case ContentType.audio:
        return '🎤 Áudio';
      case ContentType.file:
        return '📎 Documento';
      case ContentType.video:
        return '📹 Vídeo';
      case ContentType.text:
        return msg.content ?? '';
      case ContentType.meeting:
        return '📹 Reunião';
    }
  }
}

// ─── Avatar ──────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String? uri;
  final String name;
  final bool isOnline;

  const _Avatar({this.uri, required this.name, this.isOnline = false});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          backgroundImage:
              uri != null ? CachedNetworkImageProvider(uri!, maxWidth: 320) : null,
          child: uri == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: AppConstants.success,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Theme.of(context).colorScheme.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Estado vazio ─────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Círculo decorativo com gradiente e blur/sombra sutil
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.06),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Sua caixa de entrada está limpa',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Comece a interagir com colaboradores de qualquer filial de forma rápida e segura.',
              style: TextStyle(
                color: theme.colorScheme.outline,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push('/contacts'),
              icon: const Icon(Icons.add_comment_rounded, size: 18),
              label: const Text(
                'Iniciar Bate-Papo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
