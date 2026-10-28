import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/widgets/signed_network_image.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/features/chat/models/chat_member_model.dart';
import 'package:alinha_ja/features/chat/providers/chat_info_provider.dart';
import 'package:alinha_ja/features/chat/providers/chat_members_provider.dart';
import 'package:alinha_ja/features/profile/providers/users_provider.dart';
import 'package:alinha_ja/features/chat/data/media_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatInfoScreen extends ConsumerStatefulWidget {
  final String chatId;
  final bool isGroup;
  final String chatName;
  final UserModel? targetUser;

  const ChatInfoScreen({
    super.key,
    required this.chatId,
    required this.isGroup,
    required this.chatName,
    this.targetUser,
  });

  @override
  ConsumerState<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends ConsumerState<ChatInfoScreen>
    with TickerProviderStateMixin {
  bool _isSaving = false;
  final _mediaService = MediaService();
  late AnimationController _pulseController;
  String _memberQuery = '';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _editGroupInfo(
      String currentName, String currentDesc, String? currentAvatar) async {
    final nameCtrl = TextEditingController(text: currentName);
    final descCtrl = TextEditingController(text: currentDesc);
    final messenger = ScaffoldMessenger.of(context);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Editar Dados do Grupo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome do Grupo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descrição do Grupo',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (updated == true) {
      setState(() => _isSaving = true);
      try {
        await supabase.rpc('update_group_info', params: {
          'p_chat_id': widget.chatId,
          'p_name': nameCtrl.text.trim(),
          'p_description': descCtrl.text.trim(),
          'p_avatar_url': currentAvatar,
        });

        final args = ChatInfoArgs(
          chatId: widget.chatId,
          isGroup: widget.isGroup,
          targetUserId: widget.targetUser?.id,
        );
        ref.invalidate(chatInfoProvider(args));

        messenger.showSnackBar(
          const SnackBar(
            content: Text('Informações do grupo atualizadas.'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickAndUploadGroupAvatar(
      String currentName, String currentDesc) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      setState(() => _isSaving = true);

      final result = await _mediaService.compressAndUploadImage(
        chatId: widget.chatId,
        file: file,
      );

      await supabase.rpc('update_group_info', params: {
        'p_chat_id': widget.chatId,
        'p_name': currentName,
        'p_description': currentDesc,
        'p_avatar_url': result.publicUrl,
      });

      final args = ChatInfoArgs(
        chatId: widget.chatId,
        isGroup: widget.isGroup,
        targetUserId: widget.targetUser?.id,
      );
      ref.invalidate(chatInfoProvider(args));

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Foto do grupo atualizada.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar foto: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _updateGroupMetadataKey(String key, dynamic value) async {
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final args = ChatInfoArgs(
        chatId: widget.chatId,
        isGroup: widget.isGroup,
        targetUserId: widget.targetUser?.id,
      );
      final currentDetails = ref.read(chatInfoProvider(args)).chatDetails;
      final currentMetadata =
          Map<String, dynamic>.from(currentDetails?['metadata'] as Map? ?? {});
      currentMetadata[key] = value;

      await supabase.rpc('update_group_settings', params: {
        'p_chat_id': widget.chatId,
        'p_metadata': currentMetadata,
      });

      ref.invalidate(chatInfoProvider(args));

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Configuração atualizada.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar configuração: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sair do Grupo'),
        content: const Text('Tem certeza que deseja sair do grupo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      setState(() => _isSaving = true);
      final messenger = ScaffoldMessenger.of(context);
      try {
        final myId = supabase.auth.currentUser?.id;
        if (myId == null) return;

        await supabase.rpc('remove_group_member', params: {
          'p_chat_id': widget.chatId,
          'p_user_id': myId,
        });

        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Você saiu do grupo.'),
              backgroundColor: Colors.green,
            ),
          );
          context.go('/chats');
        }
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Erro ao sair do grupo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showAddMemberDialog(
      List<ChatMemberModel> currentMembers) async {
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Adicionar Participante'),
              content: Consumer(
                builder: (context, ref, child) {
                  final allUsersAsync = ref.watch(allUsersProvider);
                  final currentMemberIds =
                      currentMembers.map((m) => m.user.id).toSet();

                  return allUsersAsync.when(
                    loading: () => const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) => Text('Erro: $err'),
                    data: (users) {
                      final nonMembers = users
                          .where((u) => !currentMemberIds.contains(u.id))
                          .toList();

                      if (nonMembers.isEmpty) {
                        return const SizedBox(
                          height: 100,
                          child: Center(
                            child: Text(
                              'Nenhum contato disponível',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        );
                      }

                      return SizedBox(
                        width: double.maxFinite,
                        height: 300,
                        child: ListView.builder(
                          itemCount: nonMembers.length,
                          itemBuilder: (itemCtx, index) {
                            final user = nonMembers[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: user.avatarUrl != null
                                    ? CachedNetworkImageProvider(
                                        user.avatarUrl!, maxWidth: 320)
                                    : null,
                                child: user.avatarUrl == null
                                    ? Text(user.initials)
                                    : null,
                              ),
                              title: Text(user.fullName),
                              subtitle: Text(user.displaySubtitle),
                              onTap: () async {
                                final name = user.fullName;
                                Navigator.pop(ctx);
                                if (!mounted) return;
                                setState(() => _isSaving = true);
                                try {
                                  await supabase
                                      .rpc('add_group_member', params: {
                                    'p_chat_id': widget.chatId,
                                    'p_user_id': user.id,
                                  });
                                  if (mounted) {
                                    ref.invalidate(
                                        chatMembersProvider(widget.chatId));

                                    messenger.showSnackBar(
                                      SnackBar(
                                        content:
                                            Text('$name adicionado.'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Erro ao adicionar: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _isSaving = false);
                                  }
                                }
                              },
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMemberOptions(ChatMemberModel member, bool isCurrentUserAdmin) {
    final currentUserId = supabase.auth.currentUser?.id;
    final showAdminActions =
        isCurrentUserAdmin && member.user.id != currentUserId;
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Ver Perfil'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/chat/new_dm_${member.user.id}',
                      extra: {'targetUser': member.user});
                },
              ),
              if (showAdminActions) ...[
                if (!member.isAdminGroup)
                  ListTile(
                    leading:
                        const Icon(Icons.shield_outlined, color: Colors.green),
                    title: const Text('Promover a Admin'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      setState(() => _isSaving = true);
                      try {
                        await supabase.rpc('set_group_member_role', params: {
                          'p_chat_id': widget.chatId,
                          'p_user_id': member.user.id,
                          'p_role': true,
                        });
                        ref.invalidate(chatMembersProvider(widget.chatId));
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Erro ao promover: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        if (mounted) setState(() => _isSaving = false);
                      }
                    },
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.shield_moon_outlined,
                        color: Colors.orange),
                    title: const Text('Remover privilégios de Admin'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      setState(() => _isSaving = true);
                      try {
                        await supabase.rpc('set_group_member_role', params: {
                          'p_chat_id': widget.chatId,
                          'p_user_id': member.user.id,
                          'p_role': false,
                        });
                        ref.invalidate(chatMembersProvider(widget.chatId));
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Erro ao despromover: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        if (mounted) setState(() => _isSaving = false);
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.person_remove, color: Colors.red),
                  title: const Text('Remover do Grupo',
                      style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Remover do Grupo'),
                        content: Text(
                            'Tem certeza que deseja remover ${member.user.fullName}?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancelar')),
                          FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Remover')),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      setState(() => _isSaving = true);
                      try {
                        await supabase.rpc('remove_group_member', params: {
                          'p_chat_id': widget.chatId,
                          'p_user_id': member.user.id,
                        });
                        ref.invalidate(chatMembersProvider(widget.chatId));
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Erro ao remover: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        if (mounted) setState(() => _isSaving = false);
                      }
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Color> _getAvatarGradient(String name) {
    if (name.isEmpty) return [Colors.grey, Colors.blueGrey];
    final colors = [
      [const Color(0xFFE57373), const Color(0xFFFF8A80)], // Red
      [const Color(0xFFF06292), const Color(0xFFFF80AB)], // Pink
      [const Color(0xFFBA68C8), const Color(0xFFEA80FC)], // Purple
      [const Color(0xFF9575CD), const Color(0xFFB388FF)], // Deep Purple
      [const Color(0xFF7986CB), const Color(0xFF8C9EFF)], // Indigo
      [const Color(0xFF64B5F6), const Color(0xFF82B1FF)], // Blue
      [const Color(0xFF4FC3F7), const Color(0xFF80D8FF)], // Light Blue
      [const Color(0xFF4DD0E1), const Color(0xFF84FFFF)], // Cyan
      [const Color(0xFF4DB6AC), const Color(0xFFA7FFEB)], // Teal
      [const Color(0xFF81C784), const Color(0xFFB9F6CA)], // Green
      [const Color(0xFFFFB74D), const Color(0xFFFFD180)], // Orange
      [const Color(0xFFFF8A65), const Color(0xFFFF9E80)], // Deep Orange
    ];

    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    final index = hash.abs() % colors.length;
    return colors[index];
  }

  Widget _buildAvatar(ThemeData theme, UserModel? targetUser) {
    final avatarUrl = targetUser?.avatarUrl;
    final name = targetUser?.fullName ?? widget.chatName;
    final initials = targetUser?.initials ?? '?';

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 56,
        backgroundColor: theme.colorScheme.primaryContainer,
        backgroundImage: CachedNetworkImageProvider(avatarUrl, maxWidth: 320),
      );
    }

    final gradientColors = _getAvatarGradient(name);
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final args = ChatInfoArgs(
        chatId: widget.chatId,
        isGroup: widget.isGroup,
        targetUserId: widget.targetUser?.id);
    final state = ref.watch(chatInfoProvider(args));
    final membersAsync = ref.watch(chatMembersProvider(widget.chatId));

    final currentUserId = supabase.auth.currentUser?.id;
    final members = membersAsync.valueOrNull ?? [];
    final isCurrentUserAdmin =
        members.any((m) => m.user.id == currentUserId && m.isAdminGroup);

    final targetUser = state.targetUser ?? widget.targetUser;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: Text(
                    widget.isGroup ? 'Dados do Grupo' : 'Perfil do Usuário'),
                centerTitle: true,
                backgroundColor: widget.isGroup
                    ? theme.colorScheme.surface
                    : Colors.transparent,
                elevation: 0,
              ),
              if (_isSaving)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(),
                ),
              SliverToBoxAdapter(
                child: _buildHeaderView(
                    context, state, isCurrentUserAdmin, targetUser),
              ),
              if (!widget.isGroup && targetUser != null) ...[
                _buildActionButtons(context, targetUser),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                _buildDmDetails(context, theme, targetUser),
              ],
              if (!widget.isGroup && state.commonChats.isNotEmpty) ...[
                _buildSectionTitle(context, 'Grupos e Canais em Comum'),
                _buildCommonChatsList(context, state),
              ],
              if (widget.isGroup && isCurrentUserAdmin) ...[
                _buildGroupSettings(context, state, members),
              ],
              if (widget.isGroup) ...[
                _buildSectionTitle(context, 'Membros do Grupo'),
                _buildMembersSearchBar(context),
                membersAsync.when(
                  loading: () => const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => SliverToBoxAdapter(child: Text('Erro: $e')),
                  data: (membersList) => _buildGroupMembersList(
                      context, ref, state, membersList, isCurrentUserAdmin),
                ),
              ],
              _buildSectionTitle(context, 'Mídias Compartilhadas'),
              _buildSharedMediaGrid(context, state),
              if (widget.isGroup) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _leaveGroup,
                      icon: const Icon(Icons.exit_to_app_rounded),
                      label: const Text('Sair do Grupo',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
              const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
            ],
          ),
          if (_isSaving)
            const ModalBarrier(
              dismissible: false,
              color: Colors.black12,
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderView(BuildContext context, ChatInfoState state,
      bool isCurrentUserAdmin, UserModel? targetUser) {
    final theme = Theme.of(context);
    if (widget.isGroup) {
      final chatDetails = state.chatDetails;
      final chatNameVal = chatDetails?['name'] as String? ?? widget.chatName;
      final chatDescVal =
          chatDetails?['description'] as String? ?? 'Sem descrição';
      final avatarUrl = chatDetails?['avatar_url'] as String?;
      final metadata = chatDetails?['metadata'] as Map<String, dynamic>? ?? {};
      final onlyAdminsEdit = metadata['only_admins_edit'] == true ||
          metadata['only_admins_edit']?.toString() == 'true';
      final canEditInfo = isCurrentUserAdmin || !onlyAdminsEdit;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  backgroundImage: avatarUrl != null
                      ? CachedNetworkImageProvider(avatarUrl, maxWidth: 320)
                      : null,
                  child: avatarUrl == null
                      ? Icon(Icons.group,
                          size: 50, color: theme.colorScheme.onPrimaryContainer)
                      : null,
                ),
                if (canEditInfo)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: InkWell(
                        onTap: () =>
                            _pickAndUploadGroupAvatar(chatNameVal, chatDescVal),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  chatNameVal,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                if (canEditInfo)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () =>
                        _editGroupInfo(chatNameVal, chatDescVal, avatarUrl),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                chatDescVal,
                style:
                    TextStyle(fontSize: 14, color: theme.colorScheme.outline),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    final isOnline = targetUser?.isActuallyOnline ?? false;

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.tertiary.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -40,
                    right: -20,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -30,
                    left: -30,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: -50,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    _buildAvatar(theme, targetUser),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = 1.0 + (_pulseController.value * 0.15);
                          final opacity = 0.8 - (_pulseController.value * 0.4);
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              if (isOnline)
                                Transform.scale(
                                  scale: scale,
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: Colors.green
                                          .withValues(alpha: opacity),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: isOnline ? Colors.green : Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: theme.colorScheme.surface,
                                      width: 3),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 60),
        Text(
          targetUser?.fullName ?? widget.chatName,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          targetUser?.displaySubtitle ?? 'Colaborador',
          style: TextStyle(fontSize: 16, color: theme.colorScheme.outline),
          textAlign: TextAlign.center,
        ),
        if (targetUser?.branchName != null)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on_rounded,
                      size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    targetUser!.branchName!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildQuickActionItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.08),
                border: Border.all(
                  color: color.withValues(alpha: 0.15),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: color,
                size: 26,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, UserModel targetUser) {
    final theme = Theme.of(context);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildQuickActionItem(
              context: context,
              icon: Icons.chat_bubble_rounded,
              label: 'Conversar',
              color: theme.colorScheme.primary,
              onTap: () => Navigator.pop(context),
            ),
            _buildQuickActionItem(
              context: context,
              icon: Icons.phone_rounded,
              label: 'Ligar',
              color: Colors.green,
              onTap: () async {
                if (targetUser.phone != null && targetUser.phone!.isNotEmpty) {
                  final uri = Uri.parse('tel:${targetUser.phone}');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Não foi possível iniciar a chamada')),
                      );
                    }
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Número de telefone não disponível')),
                  );
                }
              },
            ),
            _buildQuickActionItem(
              context: context,
              icon: Icons.email_rounded,
              label: 'E-mail',
              color: Colors.blue,
              onTap: () async {
                if (targetUser.email != null && targetUser.email!.isNotEmpty) {
                  final uri = Uri.parse('mailto:${targetUser.email}');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Não foi possível abrir o e-mail')),
                      );
                    }
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('E-mail não cadastrado')),
                  );
                }
              },
            ),
            _buildQuickActionItem(
              context: context,
              icon: Icons.copy_all_rounded,
              label: 'Copiar',
              color: Colors.orange,
              onTap: () {
                final data = 'Nome: ${targetUser.fullName}\n'
                    'Telefone: ${targetUser.phone ?? "Não informado"}\n'
                    'E-mail: ${targetUser.email ?? "Não informado"}\n'
                    'Cargo: ${targetUser.jobPositionName ?? "Não informado"}\n'
                    'Departamento: ${targetUser.departmentName ?? "Não informado"}\n'
                    'Filial: ${targetUser.branchName ?? "Não informado"}';
                Clipboard.setData(ClipboardData(text: data));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Dados de contato copiados para a área de transferência!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildDmDetails(
      BuildContext context, ThemeData theme, UserModel targetUser) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _InfoCard(
              title: 'Corporativo',
              icon: Icons.business_center_rounded,
              iconColor: theme.colorScheme.primary,
              children: [
                _DetailRowItem(
                  icon: Icons.work_outline_rounded,
                  iconColor: theme.colorScheme.primary,
                  label: 'Cargo',
                  value: targetUser.jobPositionName ?? 'Não informado',
                  onTap: () {
                    if (targetUser.jobPositionName != null) {
                      Clipboard.setData(
                          ClipboardData(text: targetUser.jobPositionName!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Cargo "${targetUser.jobPositionName}" copiado!')),
                      );
                    }
                  },
                ),
                _DetailRowItem(
                  icon: Icons.domain_rounded,
                  iconColor: theme.colorScheme.primary,
                  label: 'Departamento',
                  value: targetUser.departmentName ?? 'Não informado',
                  onTap: () {
                    if (targetUser.departmentName != null) {
                      Clipboard.setData(
                          ClipboardData(text: targetUser.departmentName!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Departamento "${targetUser.departmentName}" copiado!')),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoCard(
              title: 'Contato',
              icon: Icons.contact_phone_rounded,
              iconColor: Colors.blue,
              children: [
                _DetailRowItem(
                  icon: Icons.phone_android_rounded,
                  iconColor: Colors.blue,
                  label: 'Telefone',
                  value: targetUser.phone ?? 'Não informado',
                  onTap: () {
                    if (targetUser.phone != null) {
                      Clipboard.setData(ClipboardData(text: targetUser.phone!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Telefone "${targetUser.phone}" copiado!')),
                      );
                    }
                  },
                ),
                _DetailRowItem(
                  icon: Icons.alternate_email_rounded,
                  iconColor: Colors.blue,
                  label: 'E-mail',
                  value: targetUser.email ?? 'Não informado',
                  onTap: () {
                    if (targetUser.email != null) {
                      Clipboard.setData(ClipboardData(text: targetUser.email!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text('E-mail "${targetUser.email}" copiado!')),
                      );
                    }
                  },
                ),
              ],
            ),
            // O card "Informações Pessoais" (nascimento, sexo e CPF do
            // colega) foi removido: qualquer `member` abria a info de um
            // colega e via esses dados, sem nenhuma checagem de papel — e o
            // CPF, embora exibido mascarado, era copiado INTEIRO para a área
            // de transferência ao toque, o que tornava a máscara decorativa.
            //
            // Não há finalidade legítima para dado sensível de terceiro numa
            // tela de conversa. Consulta de CPF pelo RH/administração segue
            // disponível no Painel Admin, agora auditada
            // (admin_list_users_pii → rh_access_log).
          ],
        ),
      ),
    );
  }

  Widget _buildCommonChatsList(BuildContext context, ChatInfoState state) {
    if (state.isLoading) {
      return const SliverToBoxAdapter(
          child: Center(child: CircularProgressIndicator()));
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final chat = state.commonChats[index];
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.forum,
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            title: Text(chat.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: chat.description != null
                ? Text(chat.description!, maxLines: 1)
                : null,
            onTap: () {
              context.push('/chat/${chat.id}',
                  extra: {'name': chat.name, 'isGroup': true});
            },
          );
        },
        childCount: state.commonChats.length,
      ),
    );
  }

  Widget _buildGroupMembersList(
      BuildContext context,
      WidgetRef ref,
      ChatInfoState state,
      List<ChatMemberModel> members,
      bool isCurrentUserAdmin) {
    final theme = Theme.of(context);

    final filteredMembers = members.where((m) {
      if (_memberQuery.isEmpty) return true;
      final q = _memberQuery.toLowerCase();
      return m.user.fullName.toLowerCase().contains(q) ||
          m.user.displaySubtitle.toLowerCase().contains(q);
    }).toList();

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (isCurrentUserAdmin && index == 0) {
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: CircleAvatar(
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(Icons.person_add, color: theme.colorScheme.primary),
              ),
              title: Text(
                'Adicionar participante',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              onTap: () => _showAddMemberDialog(members),
            );
          }

          final member =
              filteredMembers[isCurrentUserAdmin ? index - 1 : index];
          final count = state.messageCounts[member.user.id] ?? 0;

          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: CircleAvatar(
              backgroundImage: member.user.avatarUrl != null
                  ? CachedNetworkImageProvider(member.user.avatarUrl!, maxWidth: 320)
                  : null,
              child: member.user.avatarUrl == null
                  ? Text(member.user.initials)
                  : null,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    member.user.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (member.isAdminGroup)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green, width: 0.5),
                    ),
                    child: const Text(
                      'Admin do Grupo',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(member.user.displaySubtitle),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count msgs',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            onTap: () => _showMemberOptions(member, isCurrentUserAdmin),
          );
        },
        childCount: isCurrentUserAdmin
            ? filteredMembers.length + 1
            : filteredMembers.length,
      ),
    );
  }

  Widget _buildMembersSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          onChanged: (val) {
            setState(() {
              _memberQuery = val;
            });
          },
          decoration: InputDecoration(
            hintText: 'Pesquisar participantes...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _memberQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      setState(() {
                        _memberQuery = '';
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupSettings(BuildContext context, ChatInfoState state,
      List<ChatMemberModel> members) {
    final theme = Theme.of(context);
    final chatDetails = state.chatDetails;
    final metadata = chatDetails?['metadata'] as Map<String, dynamic>? ?? {};
    final onlyAdminsSend = metadata['only_admins_send'] == true ||
        metadata['only_admins_send']?.toString() == 'true';
    final onlyAdminsEdit = metadata['only_admins_edit'] == true ||
        metadata['only_admins_edit']?.toString() == 'true';
    // A persona só faz sentido se o bot participar do grupo — é ele quem lê
    // `metadata.ai_specialization` ao ser mencionado.
    final hasAiAssistant =
        members.any((m) => m.user.id == AiAssistant.botId);
    final specialization =
        AiAssistant.normalizeSpecialization(metadata['ai_specialization']);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.settings_suggest_rounded,
                          size: 18, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Configurações do Grupo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile.adaptive(
                title: const Text('Enviar Mensagens',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: const Text(
                    'Apenas administradores podem enviar mensagens',
                    style: TextStyle(fontSize: 12)),
                value: onlyAdminsSend,
                onChanged: _isSaving
                    ? null
                    : (val) => _updateGroupMetadataKey('only_admins_send', val),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile.adaptive(
                title: const Text('Editar Dados do Grupo',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: const Text(
                    'Apenas administradores podem alterar nome, descrição e foto',
                    style: TextStyle(fontSize: 12)),
                value: onlyAdminsEdit,
                onChanged: _isSaving
                    ? null
                    : (val) => _updateGroupMetadataKey('only_admins_edit', val),
              ),
              if (hasAiAssistant) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: const Text('Especialidade do Assistente IA',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: const Text(
                      'Define a persona usada quando o bot é mencionado neste grupo',
                      style: TextStyle(fontSize: 12)),
                  trailing: DropdownButton<String>(
                    value: specialization,
                    underline: const SizedBox.shrink(),
                    onChanged: _isSaving
                        ? null
                        : (val) {
                            if (val == null) return;
                            _updateGroupMetadataKey('ai_specialization', val);
                          },
                    items: AiAssistant.specializations.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value,
                                  style: const TextStyle(fontSize: 14)),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSharedMediaGrid(BuildContext context, ChatInfoState state) {
    if (state.isLoading) {
      return const SliverToBoxAdapter(
          child: Center(child: CircularProgressIndicator()));
    }
    if (state.sharedMedia.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Text(
              'Nenhuma mídia compartilhada.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final media = state.sharedMedia[index];
            if (media.contentTypeString == 'image') {
              return GestureDetector(
                onTap: () {
                  // Abrir visualizador de imagem full screen
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SignedNetworkImage(
                    storedUrl: media.mediaUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            } else {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    media.contentTypeString == 'video'
                        ? Icons.videocam
                        : Icons.insert_drive_file,
                    size: 32,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              );
            }
          },
          childCount: state.sharedMedia.length,
        ),
      ),
    );
  }
}

class _DetailRowItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _DetailRowItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: iconColor.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null && value != 'Não informado')
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Icon(
                Icons.copy_rounded,
                size: 16,
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );

    if (onTap != null && value != 'Não informado') {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      );
    }
    return content;
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
