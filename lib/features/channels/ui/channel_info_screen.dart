import 'package:flutter/material.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/utils/icon_registry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/widgets/signed_network_image.dart';
import 'package:alinha_ja/features/channels/providers/channel_info_provider.dart';
import 'package:alinha_ja/features/channels/providers/active_channel_provider.dart';
import 'package:alinha_ja/features/channels/providers/channels_list_provider.dart';
import 'package:alinha_ja/features/channels/ui/widgets/channel_notification_selector.dart';
import 'package:alinha_ja/features/channels/ui/widgets/channel_successor_picker.dart';
import 'package:alinha_ja/features/workflow/providers/workflow_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/features/profile/providers/users_provider.dart';
import 'package:alinha_ja/core/providers/org_providers.dart';
import 'package:alinha_ja/core/providers/desktop_selection_provider.dart';

class ChannelInfoScreen extends ConsumerStatefulWidget {
  final String channelId;
  final String channelName;
  final Map<String, dynamic>? metadata;

  const ChannelInfoScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    this.metadata,
  });

  @override
  ConsumerState<ChannelInfoScreen> createState() => _ChannelInfoScreenState();
}

class _ChannelInfoScreenState extends ConsumerState<ChannelInfoScreen> {
  bool _isSaving = false;
  String _memberQuery = '';

  /// Abre o editor completo do workspace (identidade, categoria, permissão de
  /// postagem e etapas do Kanban). Substituiu o antigo diálogo que só permitia
  /// trocar nome e descrição.
  Future<void> _openWorkspaceEditor(String channelName) async {
    final changed = await context.push<bool>(
      '/channel/${widget.channelId}/edit',
      extra: {'channelName': channelName},
    );

    if (changed == true && mounted) {
      ref.invalidate(channelInfoProvider(widget.channelId));
      ref.invalidate(
          activeChannelProvider(ChannelArgs(channelId: widget.channelId)));
    }
  }

  Future<void> _updateChannelSetting(String key, dynamic value) async {
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final state = ref.read(channelInfoProvider(widget.channelId));
      final currentDetails = state.channelDetails;
      // Sem os detalhes carregados, o payload sairia com nome e metadata
      // vazios. O servidor agora faz merge, mas nome e descrição em branco
      // ainda sobrescreveriam os reais.
      if (currentDetails == null) {
        throw Exception(
            'As informações do canal ainda não carregaram. Tente novamente.');
      }
      final currentMetadata =
          Map<String, dynamic>.from(currentDetails['metadata'] as Map? ?? {});
      String postingPermission =
          currentDetails['posting_permission'] ?? 'everyone';

      if (key == 'posting_permission') {
        postingPermission = value as bool ? 'admins' : 'everyone';
      } else if (key == 'only_admins_edit' || key == 'ai_specialization') {
        currentMetadata[key] = value;
      }

      await supabase.rpc('update_channel_info', params: {
        'p_channel_id': widget.channelId,
        'p_name': currentDetails['name'] ?? widget.channelName,
        'p_description': currentDetails['description'] ?? '',
        'p_metadata': currentMetadata,
        'p_posting_permission': postingPermission,
      });

      ref.invalidate(channelInfoProvider(widget.channelId));
      ref.invalidate(
          activeChannelProvider(ChannelArgs(channelId: widget.channelId)));

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Configuração do canal atualizada.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar canal: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Rótulo dos papéis de `channel_members.role`.
  static const _roleLabels = <String, String>{
    'admin': 'Admin do Canal',
    'editor': 'Editor',
    'viewer': 'Leitor',
  };

  static const _roleDescriptions = <String, String>{
    'admin': 'Gerencia membros, configurações e publica',
    'editor': 'Publica mensagens no canal',
    'viewer': 'Apenas lê o canal',
  };

  /// Troca o papel de um membro. `add_channel_member` faz upsert
  /// (`ON CONFLICT DO UPDATE SET role`), então serve para promover e rebaixar.
  Future<void> _setMemberRole(UserModel user, String role) async {
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await supabase.rpc('add_channel_member', params: {
        'p_channel_id': widget.channelId,
        'p_user_id': user.id,
        'p_role': role,
      });

      ref.invalidate(channelInfoProvider(widget.channelId));
      ref.invalidate(
          activeChannelProvider(ChannelArgs(channelId: widget.channelId)));

      messenger.showSnackBar(
        SnackBar(
          content: Text(
              '${user.fullName} agora é ${_roleLabels[role] ?? role}.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao alterar permissão: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeMember(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remover do Canal'),
        content: Text(
            'Tem certeza que deseja remover ${user.fullName} deste canal?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await supabase.rpc('remove_channel_member', params: {
        'p_channel_id': widget.channelId,
        'p_user_id': user.id,
      });

      ref.invalidate(channelInfoProvider(widget.channelId));
      ref.invalidate(
          activeChannelProvider(ChannelArgs(channelId: widget.channelId)));

      messenger.showSnackBar(
        SnackBar(
          content: Text('${user.fullName} foi removido do canal.'),
          backgroundColor: Colors.green,
        ),
      );
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

  /// Menu de gestão de um membro. Só é aberto por quem gerencia o workspace
  /// (criador, admin global ou admin do canal) — o RPC revalida no banco via
  /// `can_manage_workspace`, esta checagem só evita oferecer o que vai falhar.
  void _showMemberOptions(UserModel user, String currentRole) {
    final currentUserId = supabase.auth.currentUser?.id;
    final isSelf = user.id == currentUserId;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(ctx).colorScheme.primaryContainer,
                  child: Text(user.fullName.isEmpty
                      ? 'U'
                      : user.fullName[0].toUpperCase()),
                ),
                title: Text(user.fullName.isEmpty ? 'Usuário' : user.fullName),
                subtitle: Text(_roleLabels[currentRole] ?? currentRole),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Ver Perfil'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/chat/new_dm_${user.id}',
                      extra: {'targetUser': user});
                },
              ),
              if (!isSelf) ...[
                const Divider(height: 1),
                for (final entry in _roleLabels.entries)
                  ListTile(
                    leading: Icon(
                      entry.key == currentRole
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: entry.key == currentRole
                          ? Theme.of(ctx).colorScheme.primary
                          : Theme.of(ctx).colorScheme.outline,
                    ),
                    title: Text(entry.value),
                    subtitle: Text(_roleDescriptions[entry.key] ?? '',
                        style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (entry.key == currentRole) return;
                      _setMemberRole(user, entry.key);
                    },
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_remove, color: Colors.red),
                  title: const Text('Remover do Canal',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeMember(user);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _leaveChannel() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    final info = ref.read(channelInfoProvider(widget.channelId));
    String? successorId;

    // Único admin: escolhe quem assume antes de sair. O servidor aplica a
    // mesma regra (`leave_channel`); aqui é só para perguntar na hora certa.
    if (needsAdminSuccessor(myId, info.memberRoles)) {
      successorId = await _askSuccessor(myId, info);
      if (successorId == null) return;
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Sair do Canal'),
          content: const Text('Tem certeza que deseja sair do canal?'),
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
      if (confirm != true) return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      try {
        await _callLeave(successorId);
      } on PostgrestException catch (e) {
        // Lista de papéis desatualizada (outro admin saiu nesse meio-tempo):
        // o servidor pede o sucessor e a escolha é oferecida agora.
        if (!e.message.contains('SUCCESSOR_REQUIRED') || successorId != null) {
          rethrow;
        }
        ref.invalidate(channelInfoProvider(widget.channelId));
        final fresh = await _waitChannelInfo();
        if (!mounted) return;
        final picked = await _askSuccessor(myId, fresh);
        if (picked == null) return;
        successorId = picked;
        await _callLeave(successorId);
      }

      ref.invalidate(channelsListProvider);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(successorId == null
                ? 'Você saiu do canal.'
                : 'Você saiu do canal e passou a administração.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/chats');
      }
    } catch (e) {
      final msg = e is PostgrestException ? e.message : e.toString();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao sair do canal: $msg'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _callLeave(String? successorId) =>
      supabase.rpc('leave_channel', params: {
        'p_channel_id': widget.channelId,
        'p_successor_id': successorId,
      });

  Future<String?> _askSuccessor(String myId, ChannelInfoState info) {
    final candidates =
        successorCandidates(myId, info.channelMembers, info.memberRoles);
    return pickChannelSuccessor(
      context,
      channelName:
          info.channelDetails?['name'] as String? ?? widget.channelName,
      candidates: candidates,
      memberRoles: info.memberRoles,
    );
  }

  /// Espera o provider recarregar os membros depois de invalidado.
  Future<ChannelInfoState> _waitChannelInfo() async {
    for (var i = 0; i < 50; i++) {
      final state = ref.read(channelInfoProvider(widget.channelId));
      if (!state.isLoading) return state;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return ref.read(channelInfoProvider(widget.channelId));
  }

  Future<void> _showAddMemberDialog(List<UserModel> currentMembers) async {
    final messenger = ScaffoldMessenger.of(context);
    final Set<String> selectedUserIds = {};
    String searchQuery = '';
    String? filterBranchId;
    String? filterDeptId;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Adicionar Participantes',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 480,
                height: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Barra de busca
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Pesquisar por nome ou cargo...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setDialogState(() {
                                    searchQuery = '';
                                  });
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    // Dropdowns de filtros (Filial e Departamento)
                    Consumer(
                      builder: (context, ref, _) {
                        final branchesAsync = ref.watch(branchesProvider);
                        final deptsAsync = ref.watch(departmentsProvider);

                        return Row(
                          children: [
                            Expanded(
                              child: branchesAsync.when(
                                loading: () => const SizedBox(height: 48),
                                error: (_, __) => const SizedBox(),
                                data: (branches) {
                                  return DropdownButtonFormField<String>(
                                    initialValue: filterBranchId,
                                    decoration: const InputDecoration(
                                      labelText: 'Filial',
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('Todas Filiais',
                                            style: TextStyle(fontSize: 12)),
                                      ),
                                      ...branches.map((b) =>
                                          DropdownMenuItem<String>(
                                            value: b['id']?.toString(),
                                            child: Text(
                                              b['name']?.toString() ?? '',
                                              style:
                                                  const TextStyle(fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          )),
                                    ],
                                    onChanged: (val) {
                                      setDialogState(() {
                                        filterBranchId = val;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: deptsAsync.when(
                                loading: () => const SizedBox(height: 48),
                                error: (_, __) => const SizedBox(),
                                data: (depts) {
                                  return DropdownButtonFormField<String>(
                                    initialValue: filterDeptId,
                                    decoration: const InputDecoration(
                                      labelText: 'Setor',
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('Todos Setores',
                                            style: TextStyle(fontSize: 12)),
                                      ),
                                      ...depts.map((d) =>
                                          DropdownMenuItem<String>(
                                            value: d['id']?.toString(),
                                            child: Text(
                                              d['name']?.toString() ?? '',
                                              style:
                                                  const TextStyle(fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          )),
                                    ],
                                    onChanged: (val) {
                                      setDialogState(() {
                                        filterDeptId = val;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Consumer(
                        builder: (context, ref, child) {
                          final allUsersAsync = ref.watch(allUsersProvider);
                          final currentMemberIds =
                              currentMembers.map((m) => m.id).toSet();

                          return allUsersAsync.when(
                            loading: () => const Center(
                                child: CircularProgressIndicator()),
                            error: (err, _) =>
                                Center(child: Text('Erro: $err')),
                            data: (users) {
                              final nonMembers = users
                                  .where(
                                      (u) => !currentMemberIds.contains(u.id))
                                  .toList();

                              final filtered = nonMembers.where((u) {
                                final matchesSearch = u.fullName
                                        .toLowerCase()
                                        .contains(searchQuery.toLowerCase()) ||
                                    (u.email?.toLowerCase().contains(
                                            searchQuery.toLowerCase()) ??
                                        false) ||
                                    u.displaySubtitle
                                        .toLowerCase()
                                        .contains(searchQuery.toLowerCase());
                                final matchesBranch = filterBranchId == null ||
                                    u.branchId == filterBranchId;
                                final matchesDept = filterDeptId == null ||
                                    u.departmentId == filterDeptId;
                                return matchesSearch &&
                                    matchesBranch &&
                                    matchesDept;
                              }).toList();

                              if (filtered.isEmpty) {
                                return const Center(
                                  child: Text(
                                    'Nenhum contato correspondente',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                );
                              }

                              final allSelected = filtered.isNotEmpty &&
                                  filtered.every(
                                      (u) => selectedUserIds.contains(u.id));

                              return Column(
                                children: [
                                  CheckboxListTile(
                                    value: allSelected,
                                    dense: true,
                                    title: Text(
                                      allSelected
                                          ? 'Desmarcar todos'
                                          : 'Selecionar todos (${filtered.length} contatos)',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    onChanged: (val) {
                                      setDialogState(() {
                                        if (val == true) {
                                          selectedUserIds.addAll(
                                              filtered.map((u) => u.id));
                                        } else {
                                          selectedUserIds.removeAll(
                                              filtered.map((u) => u.id));
                                        }
                                      });
                                    },
                                  ),
                                  const Divider(height: 1),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: filtered.length,
                                      itemBuilder: (itemCtx, index) {
                                        final user = filtered[index];
                                        final isSelected =
                                            selectedUserIds.contains(user.id);

                                        return CheckboxListTile(
                                          value: isSelected,
                                          title: Text(user.fullName),
                                          subtitle: Text(user.displaySubtitle),
                                          secondary: CircleAvatar(
                                            backgroundImage: user.avatarUrl !=
                                                    null
                                                ? CachedNetworkImageProvider(
                                                    user.avatarUrl!, maxWidth: 320)
                                                : null,
                                            child: user.avatarUrl == null
                                                ? Text(user.initials)
                                                : null,
                                          ),
                                          onChanged: (val) {
                                            setDialogState(() {
                                              if (val == true) {
                                                selectedUserIds.add(user.id);
                                              } else {
                                                selectedUserIds.remove(user.id);
                                              }
                                            });
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                Consumer(
                  builder: (context, dialogRef, child) {
                    final isEnabled = selectedUserIds.isNotEmpty;
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isEnabled
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        foregroundColor: isEnabled ? Colors.white : null,
                      ),
                      onPressed: !isEnabled
                          ? null
                          : () async {
                              final selected =
                                  List<String>.from(selectedUserIds);
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              setState(() => _isSaving = true);
                              try {
                                await Future.wait(selected.map((uid) {
                                  return supabase
                                      .rpc('add_channel_member', params: {
                                    'p_channel_id': widget.channelId,
                                    'p_user_id': uid,
                                    'p_role': 'viewer',
                                  });
                                }));

                                if (mounted) {
                                  ref.invalidate(
                                      channelInfoProvider(widget.channelId));
                                  ref.invalidate(channelsListProvider);

                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${selected.length} participante(s) adicionado(s) ao canal.'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Erro ao adicionar participantes: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _isSaving = false);
                              }
                            },
                      child: Text('Adicionar (${selectedUserIds.length})'),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<String> _operatorIdsFromMetadata(Map<String, dynamic>? metadata) {
    final raw = metadata?['operator_ids'];
    if (raw is List) {
      return raw
          .map((id) => id.toString())
          .where((id) => id.isNotEmpty)
          .toList();
    }
    return const [];
  }

  String _assignmentModeFromMetadata(Map<String, dynamic>? metadata) {
    final mode = metadata?['assignment_mode']?.toString();
    if (mode == 'single_operator' || mode == 'operator_pool') {
      return mode!;
    }
    return 'operator_pool';
  }

  Future<void> _showOperatorsSheet(
    BuildContext context,
    WidgetRef ref,
    ChannelInfoState state,
    ChannelState activeState,
  ) async {
    final theme = Theme.of(context);
    final metadata =
        activeState.metadata ?? widget.metadata ?? <String, dynamic>{};
    var assignmentMode = _assignmentModeFromMetadata(metadata);
    var operatorIds = _operatorIdsFromMetadata(metadata).toSet();
    String? defaultOperatorId = metadata['default_operator_id']?.toString();
    if (defaultOperatorId != null && defaultOperatorId.isEmpty) {
      defaultOperatorId = null;
    }
    if (assignmentMode == 'single_operator' &&
        defaultOperatorId == null &&
        operatorIds.length == 1) {
      defaultOperatorId = operatorIds.first;
    }
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> save() async {
              if (assignmentMode == 'single_operator' &&
                  defaultOperatorId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Escolha o operador unico do canal.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (assignmentMode == 'operator_pool' && operatorIds.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('Escolha pelo menos um operador para a equipe.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final savedOperatorIds = assignmentMode == 'single_operator'
                  ? <String>[defaultOperatorId!]
                  : operatorIds.toList();

              setSheetState(() => isSaving = true);
              try {
                await ref
                    .read(activeChannelProvider(
                            ChannelArgs(channelId: widget.channelId))
                        .notifier)
                    .updateWorkflowOperators(
                      assignmentMode: assignmentMode,
                      operatorIds: savedOperatorIds,
                      defaultOperatorId: assignmentMode == 'single_operator'
                          ? defaultOperatorId
                          : null,
                    );
                await ref
                    .read(workflowProvider(widget.channelId).notifier)
                    .loadChannelMetadata();

                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Operadores atualizados com sucesso.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erro ao salvar operadores: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              } finally {
                if (context.mounted) {
                  setSheetState(() => isSaving = false);
                }
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.82,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.engineering_outlined,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Operadores do Workflow',
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'single_operator',
                            icon: Icon(Icons.person_outline),
                            label: Text('1 operador'),
                          ),
                          ButtonSegment(
                            value: 'operator_pool',
                            icon: Icon(Icons.groups_outlined),
                            label: Text('Equipe'),
                          ),
                        ],
                        selected: {assignmentMode},
                        onSelectionChanged: (values) {
                          setSheetState(() {
                            assignmentMode = values.first;
                            if (assignmentMode == 'single_operator') {
                              defaultOperatorId ??= operatorIds.isNotEmpty
                                  ? operatorIds.first
                                  : null;
                              if (defaultOperatorId != null) {
                                operatorIds = {defaultOperatorId!};
                              }
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        assignmentMode == 'single_operator'
                            ? 'Cards novos serao atribuidos automaticamente ao operador escolhido.'
                            : 'Somente usuarios marcados como operadores poderao assumir cards em fila.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: state.channelMembers.length,
                          itemBuilder: (context, index) {
                            final user = state.channelMembers[index];
                            final selected = assignmentMode == 'single_operator'
                                ? defaultOperatorId == user.id
                                : operatorIds.contains(user.id);

                            return assignmentMode == 'single_operator'
                                ? RadioListTile<String>(
                                    value: user.id,
                                    // ignore: deprecated_member_use
                                    groupValue: defaultOperatorId,
                                    // ignore: deprecated_member_use
                                    onChanged: (value) {
                                      setSheetState(() {
                                        defaultOperatorId = value;
                                        operatorIds = value == null
                                            ? <String>{}
                                            : <String>{value};
                                      });
                                    },
                                    title: Text(user.fullName),
                                    subtitle: Text(user.displaySubtitle),
                                  )
                                : CheckboxListTile(
                                    value: selected,
                                    onChanged: (value) {
                                      setSheetState(() {
                                        if (value == true) {
                                          operatorIds.add(user.id);
                                        } else {
                                          operatorIds.remove(user.id);
                                        }
                                      });
                                    },
                                    title: Text(user.fullName),
                                    subtitle: Text(user.displaySubtitle),
                                  );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: isSaving ? null : save,
                        icon: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(isSaving ? 'Salvando...' : 'Salvar'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(channelInfoProvider(widget.channelId));
    final activeChannelState = ref
        .watch(activeChannelProvider(ChannelArgs(channelId: widget.channelId)));
    final workflowState = ref.watch(workflowProvider(widget.channelId));

    final totalMembers = state.channelMembers.length;
    final totalMessages =
        state.messageCounts.values.fold(0, (sum, count) => sum + count);
    final totalMedia = state.sharedMedia.length;
    final totalCards = workflowState.cards.length;
    final finalStatuses = workflowState.statusConfig
        .where((s) => s.isFinal)
        .map((s) => s.status)
        .toSet();
    final activeCards = workflowState.cards
        .where((c) =>
            !workflowState.isCancelledStatus(c.status) &&
            !finalStatuses.contains(c.status))
        .length;
    final channelMetadata =
        state.channelDetails?['metadata'] as Map<String, dynamic>? ??
            widget.metadata ??
            <String, dynamic>{};
    final workflowEnabled = channelMetadata['workflow_enabled'] == true ||
        channelMetadata['workflow_enabled']?.toString() == 'true';
    final currentUserId = supabase.auth.currentUser?.id;
    final isCreator = activeChannelState.createdBy == currentUserId;
    final isGlobalAdmin = activeChannelState.currentUserRoleLevel == 'admin' ||
        activeChannelState.currentUserRoleLevel == 'super_admin';
    final isChannelAdmin = activeChannelState.currentUserRole == 'admin';
    final isWorkspaceManager = isCreator || isGlobalAdmin || isChannelAdmin;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: Text('# ${widget.channelName}'),
                centerTitle: true,
                backgroundColor: theme.colorScheme.surface,
                elevation: 0,
                actions: [
                  if (workflowEnabled && isWorkspaceManager)
                    IconButton(
                      icon: const Icon(Icons.engineering_outlined),
                      tooltip: 'Gerenciar operadores',
                      onPressed: () => _showOperatorsSheet(
                        context,
                        ref,
                        state,
                        activeChannelState,
                      ),
                    ),
                ],
              ),
              if (_isSaving)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(),
                ),
              SliverToBoxAdapter(
                child: _buildHeaderView(
                    context, state, activeChannelState, workflowState),
              ),
              if (activeChannelState.createdBy != null &&
                  supabase.auth.currentUser?.id == activeChannelState.createdBy)
                SliverToBoxAdapter(
                  child: _buildCreatorActions(context, ref),
                ),
              // Preferência pessoal: vale para qualquer membro, não só para
              // quem administra o workspace.
              _buildMyNotificationPreference(context, activeChannelState),
              if (isWorkspaceManager) ...[
                _buildChannelSettings(context, state, activeChannelState),
                ..._buildPendingRequestsSection(context, state),
              ],
              _buildSectionTitle(context, 'Visão Geral'),
              SliverToBoxAdapter(
                child: _buildOverviewStats(
                  context,
                  totalMembers,
                  totalMessages,
                  totalMedia,
                  totalCards,
                  activeCards,
                  theme.colorScheme.primary,
                ),
              ),
              _buildSectionTitle(context, 'Membros'),
              _buildMembersSearchBar(context),
              _buildMembersRanking(context, state, activeChannelState),
              _buildSectionTitle(context, 'Mídias Recentes'),
              _buildSharedMediaGrid(context, state),
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _leaveChannel,
                    icon: const Icon(Icons.exit_to_app_rounded),
                    label: const Text('Sair do Canal',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
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

  Widget _buildHeaderView(BuildContext context, ChannelInfoState state,
      ChannelState activeState, WorkflowState workflowState) {
    final theme = Theme.of(context);
    final channelDetails = state.channelDetails;
    final channelNameVal =
        channelDetails?['name'] as String? ?? widget.channelName;
    final channelDescVal =
        channelDetails?['description'] as String? ?? 'Sem descrição';

    IconData channelIcon;
    Color channelColor;

    final metadata = channelDetails?['metadata'] as Map<String, dynamic>? ??
        widget.metadata ??
        <String, dynamic>{};

    if (metadata['icon'] != null) {
      channelIcon = IconRegistry.resolve(metadata['icon'].toString());
      final colorHex = metadata['color']?.toString();
      channelColor = colorHex != null
          ? Color(
              int.parse(colorHex.replaceFirst('#', ''), radix: 16) + 0xFF000000)
          : theme.colorScheme.primary;
    } else {
      final nameLower = channelNameVal.toLowerCase();
      channelColor = theme.colorScheme.primary;
      channelIcon = Icons.workspaces_rounded;

      if (nameLower.contains('contas a pagar')) {
        channelColor = const Color(0xFF2E7D32);
        channelIcon = Icons.payments_outlined;
      } else if (nameLower.contains('fat moto') ||
          nameLower.contains('pedido') ||
          nameLower.contains('liberação')) {
        channelColor = const Color(0xFF7B1FA2);
        channelIcon = Icons.fact_check_outlined;
      } else if (nameLower.contains('emplacamento') ||
          nameLower.contains('documentação') ||
          nameLower.contains('cadastro')) {
        channelColor = const Color(0xFF1565C0);
        channelIcon = Icons.description_outlined;
      } else if (nameLower.contains('faturamento')) {
        channelColor = const Color(0xFFE65100);
        channelIcon = Icons.receipt_long_outlined;
      } else if (nameLower.contains('avisos')) {
        channelColor = const Color(0xFFC62828);
        channelIcon = Icons.campaign_outlined;
      }
    }

    final currentUserId = supabase.auth.currentUser?.id;
    final isCreator = activeState.createdBy == currentUserId;
    final isGlobalAdmin = activeState.currentUserRoleLevel == 'admin' ||
        activeState.currentUserRoleLevel == 'super_admin';
    final isChannelAdmin = activeState.currentUserRole == 'admin';
    final isWorkspaceManager = isCreator || isGlobalAdmin || isChannelAdmin;
    final onlyAdminsEdit = metadata['only_admins_edit'] == true ||
        metadata['only_admins_edit']?.toString() == 'true';
    final canEditInfo = isWorkspaceManager || !onlyAdminsEdit;

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
                    channelColor.withValues(alpha: 0.8),
                    channelColor,
                    theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.25),
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
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        channelColor.withValues(alpha: 0.15),
                        channelColor.withValues(alpha: 0.35)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      channelIcon,
                      size: 50,
                      color: channelColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 60),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              channelNameVal,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (canEditInfo)
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                tooltip: 'Editar workspace',
                onPressed: () => _openWorkspaceEditor(channelNameVal),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: channelColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                workflowState.cards.isNotEmpty
                    ? Icons.dashboard_customize
                    : Icons.forum,
                size: 14,
                color: channelColor,
              ),
              const SizedBox(width: 6),
              Text(
                workflowState.cards.isNotEmpty
                    ? 'Workflow Ativo'
                    : 'Canal de Conversa',
                style: TextStyle(
                  fontSize: 12,
                  color: channelColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            channelDescVal,
            style: TextStyle(fontSize: 14, color: theme.colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Nível de notificação do usuário neste canal.
  ///
  /// Fica fora do cartão "Configurações do Canal" de propósito: aquele é
  /// gerido por quem administra o workspace, enquanto isto é preferência
  /// individual gravada na própria linha de `channel_members`.
  Widget _buildMyNotificationPreference(
      BuildContext context, ChannelState activeState) {
    final theme = Theme.of(context);
    final level =
        ChannelNotificationLevel.resolve(activeState.notificationLevel);
    final isDefault = level.value == 'all';

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isDefault
                        ? theme.colorScheme.primary
                        : theme.colorScheme.tertiary)
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(level.icon,
                  size: 20,
                  color: isDefault
                      ? theme.colorScheme.primary
                      : theme.colorScheme.tertiary),
            ),
            title: const Text('Minhas notificações',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text('${level.label} — ${level.description}',
                style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showChannelNotificationSheet(
                context, ref, widget.channelId),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelSettings(
      BuildContext context, ChannelInfoState state, ChannelState activeState) {
    final theme = Theme.of(context);
    final channelDetails = state.channelDetails;
    final metadata = channelDetails?['metadata'] as Map<String, dynamic>? ?? {};
    final postingPermission =
        channelDetails?['posting_permission'] ?? 'everyone';
    final onlyAdminsSend = postingPermission == 'admins';
    final onlyAdminsEdit = metadata['only_admins_edit'] == true ||
        metadata['only_admins_edit']?.toString() == 'true';
    // Só oferece a persona se o bot for membro do canal — nele o assistente
    // responde apenas quando mencionado (@assistente) ou respondido.
    final hasAiAssistant =
        state.channelMembers.any((u) => u.id == AiAssistant.botId);
    final specialization =
        AiAssistant.normalizeSpecialization(metadata['ai_specialization']);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                      'Configurações do Canal',
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
                    : (val) => _updateChannelSetting('posting_permission', val),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile.adaptive(
                title: const Text('Editar Dados do Canal',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: const Text(
                    'Apenas administradores podem alterar nome e descrição',
                    style: TextStyle(fontSize: 12)),
                value: onlyAdminsEdit,
                onChanged: _isSaving
                    ? null
                    : (val) => _updateChannelSetting('only_admins_edit', val),
              ),
              if (hasAiAssistant) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: const Text('Especialidade do Assistente IA',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: const Text(
                      'Define a persona usada quando o bot é mencionado neste canal',
                      style: TextStyle(fontSize: 12)),
                  trailing: DropdownButton<String>(
                    value: specialization,
                    underline: const SizedBox.shrink(),
                    onChanged: _isSaving
                        ? null
                        : (val) {
                            if (val == null) return;
                            _updateChannelSetting('ai_specialization', val);
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

  Widget _buildOverviewStats(BuildContext context, int members, int messages,
      int media, int cards, int activeCards, Color channelColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          _buildStatChip(context, Icons.people_outline, '$members', 'Membros',
              channelColor),
          _buildStatChip(context, Icons.forum_outlined, '$messages',
              'Mensagens', Theme.of(context).colorScheme.tertiary),
          _buildStatChip(context, Icons.perm_media_outlined, '$media', 'Mídias',
              Colors.orange),
          if (cards > 0) ...[
            _buildStatChip(context, Icons.dashboard_customize_outlined,
                '$cards', 'Cards', const Color(0xFF2E7D32)),
            if (activeCards > 0)
              _buildStatChip(context, Icons.pending_actions_outlined,
                  '$activeCards', 'Em andamento', const Color(0xFFF59E0B)),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(BuildContext context, IconData icon, String value,
      String label, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 16,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreatorActions(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.admin_panel_settings,
                    color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Text('Modo Administrador',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.orange)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Arquivar Canal?'),
                        content: const Text(
                            'O canal sairá da lista ativa mas os dados serão mantidos.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancelar')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Arquivar',
                                  style: TextStyle(color: Colors.orange))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (c) =>
                            const Center(child: CircularProgressIndicator()),
                      );
                      try {
                        await ref
                            .read(activeChannelProvider(
                                    ChannelArgs(channelId: widget.channelId))
                                .notifier)
                            .archiveChannel();

                        final selection = ref.read(desktopSelectionProvider);
                        if (selection != null &&
                            selection.id == widget.channelId) {
                          ref.read(desktopSelectionProvider.notifier).state =
                              null;
                        }

                        if (context.mounted) {
                          Navigator.pop(context); // Pop loading dialog
                          context.go('/chats');
                          // Invalidar após navegação para evitar rebuild com dados stale
                          ref.invalidate(channelsListProvider);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.pop(context); // Pop loading dialog
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Erro ao arquivar canal: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  icon:
                      const Icon(Icons.archive_outlined, color: Colors.orange),
                  label: const Text('Arquivar',
                      style: TextStyle(color: Colors.orange)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Excluir Definitivamente?'),
                        content: const Text(
                            'Cuidado: Isso apagará TODOS os dados permanentemente.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancelar')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Excluir',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (c) =>
                            const Center(child: CircularProgressIndicator()),
                      );
                      try {
                        await ref
                            .read(activeChannelProvider(
                                    ChannelArgs(channelId: widget.channelId))
                                .notifier)
                            .deleteChannel();

                        final selection = ref.read(desktopSelectionProvider);
                        if (selection != null &&
                            selection.id == widget.channelId) {
                          ref.read(desktopSelectionProvider.notifier).state =
                              null;
                        }

                        if (context.mounted) {
                          Navigator.pop(context); // Pop loading dialog
                          context.go('/chats');
                          // Invalidar após navegação para evitar rebuild com dados stale
                          ref.invalidate(channelsListProvider);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.pop(context); // Pop loading dialog
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Erro ao excluir canal: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text('Excluir',
                      style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red)),
                ),
              ),
            ],
          ),
        ],
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

  Widget _buildMembersRanking(
      BuildContext context, ChannelInfoState state, ChannelState activeState) {
    if (state.isLoading) {
      return const SliverToBoxAdapter(
          child: Center(child: CircularProgressIndicator()));
    }

    final members = state.channelMembers;
    final operatorIds = _operatorIdsFromMetadata(activeState.metadata).toSet();

    final currentUserId = supabase.auth.currentUser?.id;
    final isCreator = activeState.createdBy == currentUserId;
    final isGlobalAdmin = activeState.currentUserRoleLevel == 'admin' ||
        activeState.currentUserRoleLevel == 'super_admin';
    final isChannelAdmin = activeState.currentUserRole == 'admin';
    final isWorkspaceManager = isCreator || isGlobalAdmin || isChannelAdmin;

    if (members.isEmpty) {
      if (isWorkspaceManager) {
        return SliverToBoxAdapter(
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(Icons.person_add,
                  color: Theme.of(context).colorScheme.primary),
            ),
            title: Text(
              'Adicionar participante',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            onTap: () => _showAddMemberDialog(members),
          ),
        );
      }
      return const SliverToBoxAdapter(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhum membro encontrado')));
    }

    final filteredMembers = members.where((user) {
      if (_memberQuery.isEmpty) return true;
      final q = _memberQuery.toLowerCase();
      return user.fullName.toLowerCase().contains(q) ||
          user.displaySubtitle.toLowerCase().contains(q);
    }).toList();

    if (filteredMembers.isEmpty) {
      return SliverList(
        delegate: SliverChildListDelegate([
          if (isWorkspaceManager)
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                child: Icon(Icons.person_add,
                    color: Theme.of(context).colorScheme.primary),
              ),
              title: Text(
                'Adicionar participante',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              onTap: () => _showAddMemberDialog(members),
            ),
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Nenhum membro corresponde à pesquisa.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ]),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (isWorkspaceManager && index == 0) {
            final theme = Theme.of(context);
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

          final user = filteredMembers[isWorkspaceManager ? index - 1 : index];
          final memberRole = state.memberRoles[user.id] ?? 'viewer';
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                  user.fullName.isEmpty ? 'U' : user.fullName[0].toUpperCase()),
            ),
            title: Text(user.fullName.isEmpty ? 'Usuário' : user.fullName),
            subtitle: Text(user.displaySubtitle),
            onTap: isWorkspaceManager
                ? () => _showMemberOptions(user, memberRole)
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (memberRole != 'viewer') ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (memberRole == 'admin'
                              ? Colors.green
                              : Theme.of(context).colorScheme.tertiary)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: memberRole == 'admin'
                            ? Colors.green
                            : Theme.of(context).colorScheme.tertiary,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      _roleLabels[memberRole] ?? memberRole,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: memberRole == 'admin'
                            ? Colors.green
                            : Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (operatorIds.contains(user.id)) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Operador'),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${state.messageCounts[user.id] ?? 0} msgs'),
                ),
              ],
            ),
          );
        },
        childCount: isWorkspaceManager
            ? filteredMembers.length + 1
            : filteredMembers.length,
      ),
    );
  }

  Widget _buildSharedMediaGrid(BuildContext context, ChannelInfoState state) {
    if (state.isLoading) {
      return const SliverToBoxAdapter(
          child: Center(child: CircularProgressIndicator()));
    }

    if (state.sharedMedia.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.perm_media_outlined,
                  size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 8),
              Text('Nenhuma mídia compartilhada',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline)),
            ],
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: SizedBox(
        height: 120,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: state.sharedMedia.length,
          itemBuilder: (context, index) {
            final media = state.sharedMedia[index];
            return Container(
              width: 100,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: media.mediaUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SignedNetworkImage(
                          storedUrl: media.mediaUrl!, fit: BoxFit.cover),
                    )
                  : const Icon(Icons.image, size: 40),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildPendingRequestsSection(
      BuildContext context, ChannelInfoState state) {
    if (state.pendingRequests.isEmpty) {
      return [];
    }

    final theme = Theme.of(context);

    return [
      _buildSectionTitle(
          context, 'Solicitações de Entrada (${state.pendingRequests.length})'),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final req = state.pendingRequests[index];
              final userMap = req['users'] as Map<String, dynamic>? ?? const {};
              final requestId = req['id'] as String;
              final userName = userMap['full_name']?.toString() ?? 'Usuário';
              final avatarUrl = userMap['avatar_url']?.toString();
              final email = userMap['email']?.toString() ?? 'Sem e-mail';
              final displayRole = _mapRoleLevelToDisplay(
                  userMap['role_level']?.toString() ?? 'member');

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage:
                            avatarUrl != null && avatarUrl.isNotEmpty
                                ? CachedNetworkImageProvider(avatarUrl, maxWidth: 320)
                                : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? Text(userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?')
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '$displayRole • $email',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton.filledTonal(
                            onPressed: () =>
                                _handleRequest(requestId, 'approved', userName),
                            icon: const Icon(Icons.check, color: Colors.green),
                            tooltip: 'Aprovar',
                          ),
                          const SizedBox(width: 6),
                          IconButton.filledTonal(
                            onPressed: () =>
                                _handleRequest(requestId, 'rejected', userName),
                            icon: const Icon(Icons.close, color: Colors.red),
                            tooltip: 'Recusar',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
            childCount: state.pendingRequests.length,
          ),
        ),
      ),
    ];
  }

  String _mapRoleLevelToDisplay(String roleLevel) {
    switch (roleLevel) {
      case 'super_admin':
        return 'Super Admin';
      case 'admin':
        return 'Diretoria';
      case 'manager':
        return 'Gestor(a)';
      default:
        return 'Colaborador(a)';
    }
  }

  Future<void> _handleRequest(
      String requestId, String status, String userName) async {
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (status == 'approved') {
        // RLS sem permissão não dá erro: atualiza zero linhas. Sem este
        // teste a tela confirmava uma aprovação que não aconteceu.
        final updated = await supabase
            .from('channel_join_requests')
            .update({'status': 'approved'})
            .eq('id', requestId)
            .select('id');
        if ((updated as List).isEmpty) {
          throw Exception('sem permissão para aprovar esta solicitação.');
        }

        messenger.showSnackBar(
          SnackBar(
            content: Text('Solicitação de $userName aprovada!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final deleted = await supabase
            .from('channel_join_requests')
            .delete()
            .eq('id', requestId)
            .select('id');
        if ((deleted as List).isEmpty) {
          throw Exception('sem permissão para recusar esta solicitação.');
        }

        messenger.showSnackBar(
          SnackBar(
            content: Text('Solicitação de $userName recusada.'),
            backgroundColor: Colors.red,
          ),
        );
      }

      ref.invalidate(channelInfoProvider(widget.channelId));
      ref.invalidate(
          activeChannelProvider(ChannelArgs(channelId: widget.channelId)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao processar solicitação: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
