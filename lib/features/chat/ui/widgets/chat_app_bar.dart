import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:collection/collection.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/chat/providers/chat_provider.dart';
import 'package:alinha_ja/features/chat/providers/chat_members_provider.dart';
import 'package:alinha_ja/features/chats/ui/chats_list_screen.dart';
import 'package:alinha_ja/core/providers/presence_service.dart';
import 'package:alinha_ja/core/providers/desktop_selection_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatAppBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  final String chatId;
  final String chatName;
  final bool isGroup;
  final int? groupMemberCount;
  final VoidCallback onCreateMeetingRoom;
  final VoidCallback onJoinMeetingRoom;

  const ChatAppBar({
    super.key,
    required this.chatId,
    required this.chatName,
    required this.isGroup,
    this.groupMemberCount,
    required this.onCreateMeetingRoom,
    required this.onJoinMeetingRoom,
  });

  @override
  ConsumerState<ChatAppBar> createState() => _ChatAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1.0);
}

class _ChatAppBarState extends ConsumerState<ChatAppBar> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Voltar da conversa.
  ///
  /// No mobile a tela é uma rota empilhada — basta desempilhar. No desktop a
  /// conversa é um painel do layout master-detail, não uma rota: chamar `pop()`
  /// ali desempilhava a própria home e deixava a tela preta. Nesse caso
  /// devolvemos os menus (sai do Modo Foco) e limpamos a seleção.
  void _handleBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    ref.read(desktopFocusModeProvider.notifier).state = false;
    ref.read(desktopSelectionProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider(ChatArgs(chatId: widget.chatId)));
    final currentUser = ref.read(currentUserProvider).valueOrNull;

    // Verifica se o usuario pode criar reuniao (apenas gestores e admins)
    final canCreateMeeting = currentUser != null &&
        AppPermissions.canCreateMeeting(currentUser.roleLevel);

    if (_isSearching) {
      return AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Fechar busca',
          onPressed: () {
            setState(() {
              _isSearching = false;
              _searchController.clear();
              ref.read(chatProvider(ChatArgs(chatId: widget.chatId)).notifier).setSearchQuery('');
            });
          },
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Buscar na conversa...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          onChanged: (value) {
            ref.read(chatProvider(ChatArgs(chatId: widget.chatId)).notifier).setSearchQuery(value);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              ref.read(chatProvider(ChatArgs(chatId: widget.chatId)).notifier).setSearchQuery('');
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
            height: 1.0,
          ),
        ),
      );
    }

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
      centerTitle: false,
      titleSpacing: kIsWeb ? 24.0 : 4.0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '', // Remove o tooltip nativo indesejado
        onPressed: _handleBack,
      ),
      title: Builder(
        builder: (context) {
          final chatsList = ref.watch(chatsListProvider).valueOrNull ?? [];
          final chatModel = chatsList.firstWhereOrNull((c) => c.id == widget.chatId);
          final otherUser = chatModel?.otherUser;
          final avatarUrl = widget.isGroup ? null : otherUser?.avatarUrl;
          final isOnline = otherUser != null &&
              ref.watch(onlineUsersProvider.select((set) => set.contains(otherUser.id)));
          
          final memberModels = ref.watch(chatMembersProvider(widget.chatId)).valueOrNull ?? [];
          final currentMember = memberModels.firstWhereOrNull((m) => m.user.id == currentUser?.id);
          final isMuted = currentMember?.muted ?? false;

          return Row(
            children: [
              GestureDetector(
                onTap: () {
                  context.push('/chat/${widget.chatId}/info', extra: {
                    'name': widget.chatName,
                    'isGroup': widget.isGroup,
                    'targetUser': otherUser,
                  });
                },
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl, maxWidth: 320) : null,
                      child: avatarUrl == null
                          ? Icon(
                              widget.isGroup ? Icons.groups_rounded : Icons.person_rounded,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            )
                          : null,
                    ),
                    if (isOnline)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppConstants.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isGroup)
                          Icon(Icons.lock_person_rounded,
                              size: 16, color: Theme.of(context).colorScheme.primary),
                        if (widget.isGroup) const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.chatName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ),
                        if (isMuted)
                          Padding(
                            padding: const EdgeInsets.only(left: 6.0),
                            child: Icon(Icons.volume_off_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                    if (widget.isGroup && widget.groupMemberCount != null && state.typingUsers.isEmpty)
                      Text(
                        '${widget.groupMemberCount} membros',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (!widget.isGroup && state.typingUsers.isEmpty && otherUser != null)
                      Builder(
                        builder: (context) {
                          if (isOnline) {
                            return const Text(
                              'Online',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: AppConstants.success),
                            );
                          } else if (otherUser.lastSeenAt != null) {
                            final timeStr = timeago.format(otherUser.lastSeenAt!,
                                locale: 'pt_BR_short');
                            return Text(
                              'Visto por último: $timeStr',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    if (state.typingUsers.isNotEmpty)
                      Text(
                        '${state.typingUsers.values.join(', ')} digitando...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Buscar na conversa',
          onPressed: () {
            setState(() => _isSearching = true);
          },
        ),
        if (!widget.isGroup || canCreateMeeting)
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: widget.isGroup ? 'Criar Huddle de Áudio' : 'Ligar (1:1)',
            onPressed: () async {
              if (widget.isGroup) {
                widget.onCreateMeetingRoom();
                return;
              }

              if (!kIsWeb) {
                final micStatus = await Permission.microphone.request();
                if (!micStatus.isGranted) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Permissão de Microfone necessária para ligar.')),
                    );
                  }
                  return;
                }
              }

              if (currentUser == null) return;
              final chatsList = ref.read(chatsListProvider).valueOrNull ?? [];
              final chatModel =
                  chatsList.firstWhereOrNull((c) => c.id == widget.chatId);
              final calleeId = chatModel?.otherUser?.id;
              await CallService.instance.startCall(
                chatId: widget.chatId,
                callerName: currentUser.fullName,
                calleeName: widget.chatName,
                calleeId: calleeId,
              );
            },
          ),
        if (!widget.isGroup || canCreateMeeting)
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip:
                widget.isGroup ? 'Iniciar Videoconferência' : 'Ligar por Vídeo (1:1)',
            onPressed: () async {
              if (widget.isGroup) {
                widget.onCreateMeetingRoom();
                return;
              }

              if (!kIsWeb) {
                final micStatus = await Permission.microphone.request();
                final camStatus = await Permission.camera.request();

                if (!micStatus.isGranted || !camStatus.isGranted) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Permissões de Câmera e Microfone necessárias para Videoconferência.')),
                    );
                  }
                  return;
                }
              }

              if (currentUser == null) return;
              final chatsList = ref.read(chatsListProvider).valueOrNull ?? [];
              final chatModel =
                  chatsList.firstWhereOrNull((c) => c.id == widget.chatId);
              final calleeId = chatModel?.otherUser?.id;
              await CallService.instance.startCall(
                chatId: widget.chatId,
                callerName: currentUser.fullName,
                calleeName: widget.chatName,
                calleeId: calleeId,
                isVideoEnabled: true,
              );
            },
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            if (value == 'info') {
              final chatsList = ref.read(chatsListProvider).valueOrNull ?? [];
              final chatModel =
                  chatsList.firstWhereOrNull((c) => c.id == widget.chatId);
              context.push('/chat/${widget.chatId}/info', extra: {
                'name': widget.chatName,
                'isGroup': widget.isGroup,
                'targetUser': chatModel?.otherUser,
              });
            } else if (value == 'create_room') {
              widget.onCreateMeetingRoom();
            } else if (value == 'join_room') {
              widget.onJoinMeetingRoom();
            } else if (value == 'clear') {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Limpar janela?'),
                  content: const Text('Isso removerá as mensagens apenas da sua tela, mas elas continuarão no servidor.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        ref.read(chatProvider(ChatArgs(chatId: widget.chatId)).notifier).clearLocalMessages();
                      },
                      child: const Text('Limpar'),
                    ),
                  ],
                ),
              );
            } else if (value == 'mute') {
              ref.read(chatProvider(ChatArgs(chatId: widget.chatId)).notifier).toggleMute();
            } else if (value == 'leave') {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sair do grupo?'),
                  content: const Text('Você não receberá mais mensagens deste grupo e ele sumirá da sua lista.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        ref.read(chatProvider(ChatArgs(chatId: widget.chatId)).notifier).leaveGroup();
                        if (context.mounted) {
                          context.go('/chats'); // Volta para a lista de chats
                        }
                      },
                      style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                      child: const Text('Sair'),
                    ),
                  ],
                ),
              );
            }
          },
          itemBuilder: (BuildContext context) {
            final memberModels = ref.watch(chatMembersProvider(widget.chatId)).valueOrNull ?? [];
            final currentMember = memberModels.firstWhereOrNull((m) => m.user.id == currentUser?.id);
            final isMuted = currentMember?.muted ?? false;

            return [
              PopupMenuItem<String>(
                value: 'info',
                child: Text(widget.isGroup ? 'Visão geral do grupo' : 'Ver perfil'),
              ),
              if (widget.isGroup && canCreateMeeting)
                const PopupMenuItem<String>(
                  value: 'create_room',
                  child: Row(
                    children: [
                      Icon(Icons.video_call, size: 20),
                      SizedBox(width: 8),
                      Text('Criar Sala de Reunião'),
                    ],
                  ),
                ),
              if (widget.isGroup)
                const PopupMenuItem<String>(
                  value: 'join_room',
                  child: Row(
                    children: [
                      Icon(Icons.login, size: 20),
                      SizedBox(width: 8),
                      Text('Entrar em Sala'),
                    ],
                  ),
                ),
              PopupMenuItem<String>(
                value: 'mute',
                child: Text(isMuted ? 'Ativar notificações' : 'Silenciar notificações'),
              ),
              const PopupMenuItem<String>(
                value: 'clear',
                child: Text('Limpar janela'),
              ),
              if (widget.isGroup)
                PopupMenuItem<String>(
                  value: 'leave',
                  child: Text(
                    'Sair do grupo',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ];
          },
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.3),
          height: 1.0,
        ),
      ),
    );
  }
}
