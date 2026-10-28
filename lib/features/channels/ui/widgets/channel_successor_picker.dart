import 'package:flutter/material.dart';

import 'package:alinha_ja/features/profile/models/user_model.dart';

/// Quem sai precisa indicar um sucessor? Mesma regra de
/// `channel_member_is_sole_admin` no banco: é admin, não há outro admin e
/// ainda resta alguém no canal.
bool needsAdminSuccessor(String myId, Map<String, String> memberRoles) {
  if (memberRoles[myId] != 'admin') return false;
  final others = memberRoles.entries.where((e) => e.key != myId);
  if (others.isEmpty) return false;
  return !others.any((e) => e.value == 'admin');
}

/// Candidatos à sucessão: os demais membros, com editores primeiro (já têm
/// experiência de gestão) e depois em ordem alfabética.
List<UserModel> successorCandidates(
  String myId,
  List<UserModel> members,
  Map<String, String> memberRoles,
) {
  final list = members.where((m) => m.id != myId).toList();
  int rank(UserModel u) => memberRoles[u.id] == 'editor' ? 0 : 1;
  list.sort((a, b) {
    final byRole = rank(a).compareTo(rank(b));
    if (byRole != 0) return byRole;
    return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
  });
  return list;
}

/// Pede ao último admin quem vai administrar o canal depois que ele sair.
/// Devolve o id escolhido, ou `null` se a pessoa desistir.
Future<String?> pickChannelSuccessor(
  BuildContext context, {
  required String channelName,
  required List<UserModel> candidates,
  required Map<String, String> memberRoles,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _SuccessorDialog(
      channelName: channelName,
      candidates: candidates,
      memberRoles: memberRoles,
    ),
  );
}

class _SuccessorDialog extends StatefulWidget {
  final String channelName;
  final List<UserModel> candidates;
  final Map<String, String> memberRoles;

  const _SuccessorDialog({
    required this.channelName,
    required this.candidates,
    required this.memberRoles,
  });

  @override
  State<_SuccessorDialog> createState() => _SuccessorDialogState();
}

class _SuccessorDialogState extends State<_SuccessorDialog> {
  String? _selected;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? widget.candidates
        : widget.candidates
            .where((u) => u.fullName.toLowerCase().contains(q))
            .toList();

    return AlertDialog(
      title: const Text('Escolha quem vai administrar'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Você é o único administrador de "${widget.channelName}". '
              'Antes de sair, passe a administração para outro membro — ele '
              'poderá aprovar entradas, gerir membros e editar o canal.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (widget.candidates.length > 6)
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar membro',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: visible.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nenhum membro encontrado.'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: visible.length,
                      itemBuilder: (_, i) {
                        final user = visible[i];
                        final isEditor =
                            widget.memberRoles[user.id] == 'editor';
                        final selected = _selected == user.id;
                        return ListTile(
                          selected: selected,
                          onTap: () => setState(() => _selected = user.id),
                          leading: CircleAvatar(
                            backgroundImage: user.avatarUrl != null &&
                                    user.avatarUrl!.startsWith('http')
                                ? NetworkImage(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(user.fullName.isNotEmpty
                                    ? user.fullName[0].toUpperCase()
                                    : '?')
                                : null,
                          ),
                          title: Text(user.fullName),
                          subtitle: isEditor ? const Text('Editor') : null,
                          trailing: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: selected ? theme.colorScheme.primary : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed:
              _selected == null ? null : () => Navigator.pop(context, _selected),
          child: const Text('Transferir e sair'),
        ),
      ],
    );
  }
}
