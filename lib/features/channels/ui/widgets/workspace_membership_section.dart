import 'package:flutter/material.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';

/// Seleção de membros e de operadores do workflow na criação do workspace.
///
/// Componente controlado: todo o estado vive na tela pai, que decide como
/// persistir. Os operadores elegíveis são sempre um subconjunto dos membros —
/// o backend recusa operador que não seja membro do canal.
class WorkspaceMembershipSection extends StatefulWidget {
  final List<UserModel> contacts;
  final bool isLoadingContacts;

  final bool addEveryone;
  final ValueChanged<bool> onAddEveryoneChanged;

  final Set<String> selectedIds;
  final VoidCallback onSelectionChanged;

  /// Quando falso, a parte de operadores fica oculta (canal sem workflow).
  final bool showOperators;

  final String assignmentMode;
  final ValueChanged<String> onAssignmentModeChanged;

  final Set<String> operatorIds;
  final VoidCallback onOperatorsChanged;

  /// Usuário logado — sempre elegível como operador, já que vira admin do canal.
  final UserModel? currentUser;

  const WorkspaceMembershipSection({
    super.key,
    required this.contacts,
    required this.isLoadingContacts,
    required this.addEveryone,
    required this.onAddEveryoneChanged,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.showOperators,
    required this.assignmentMode,
    required this.onAssignmentModeChanged,
    required this.operatorIds,
    required this.onOperatorsChanged,
    required this.currentUser,
  });

  @override
  State<WorkspaceMembershipSection> createState() =>
      _WorkspaceMembershipSectionState();
}

class _WorkspaceMembershipSectionState
    extends State<WorkspaceMembershipSection> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Membros que podem ser marcados como operadores.
  List<UserModel> _eligibleOperators() {
    final byId = <String, UserModel>{};
    for (final user in widget.contacts) {
      if (widget.addEveryone || widget.selectedIds.contains(user.id)) {
        byId[user.id] = user;
      }
    }
    final me = widget.currentUser;
    if (me != null) byId[me.id] = me;

    final users = byId.values.toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return users;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Membros',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            TextButton.icon(
              onPressed: () =>
                  widget.onAddEveryoneChanged(!widget.addEveryone),
              icon: Icon(widget.addEveryone
                  ? Icons.check_circle
                  : Icons.add_circle_outline),
              label: Text(widget.addEveryone
                  ? 'Todos selecionados'
                  : 'Adicionar todos'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildMembersList(theme),
        if (widget.showOperators) ...[
          const SizedBox(height: 24),
          Text('Operadores do workflow',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildOperators(theme),
        ],
      ],
    );
  }

  Widget _buildMembersList(ThemeData theme) {
    if (widget.isLoadingContacts) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (widget.addEveryone) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.group, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  'Todos os ${widget.contacts.length} usuários ativos serão adicionados',
                  style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      );
    }

    final filtered = _query.isEmpty
        ? widget.contacts
        : widget.contacts
            .where((u) =>
                u.fullName.toLowerCase().contains(_query) ||
                u.displaySubtitle.toLowerCase().contains(_query))
            .toList();

    return Column(
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v.toLowerCase()),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Buscar colaborador...',
            prefixIcon: const Icon(Icons.search, size: 20),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.selectedIds.length} selecionado(s)',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        SizedBox(
          height: 240,
          child: filtered.isEmpty
              ? Center(
                  child: Text('Nenhum colaborador encontrado.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final user = filtered[index];
                    final isSelected = widget.selectedIds.contains(user.id);

                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (v) {
                        if (v == true) {
                          widget.selectedIds.add(user.id);
                        } else {
                          widget.selectedIds.remove(user.id);
                          // Quem sai da lista de membros não pode seguir operador.
                          widget.operatorIds.remove(user.id);
                        }
                        widget.onSelectionChanged();
                        setState(() {});
                      },
                      title: Text(
                          user.fullName.isEmpty ? 'Usuário' : user.fullName),
                      subtitle: Text(user.displaySubtitle),
                      secondary: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(user.initials),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildOperators(ThemeData theme) {
    final operators = _eligibleOperators();
    final eligibleIds = operators.map((u) => u.id).toSet();
    final selectedSingle = widget.operatorIds.length == 1 &&
            eligibleIds.contains(widget.operatorIds.first)
        ? widget.operatorIds.first
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                selected: widget.assignmentMode == 'single_operator',
                label: const Text('1 operador'),
                avatar: const Icon(Icons.person_outline, size: 18),
                onSelected: (_) {
                  if (widget.operatorIds.length > 1) {
                    final first = widget.operatorIds.first;
                    widget.operatorIds
                      ..clear()
                      ..add(first);
                    widget.onOperatorsChanged();
                  }
                  widget.onAssignmentModeChanged('single_operator');
                },
              ),
              ChoiceChip(
                selected: widget.assignmentMode == 'operator_pool',
                label: const Text('Equipe'),
                avatar: const Icon(Icons.groups_outlined, size: 18),
                onSelected: (_) =>
                    widget.onAssignmentModeChanged('operator_pool'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.assignmentMode == 'single_operator'
                ? 'Cards novos entram direto para o operador escolhido.'
                : 'Cards novos ficam sem responsável até um operador da equipe assumir.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (widget.assignmentMode == 'single_operator')
            DropdownButtonFormField<String>(
              // Campo controlado: `selectedSingle` é derivado de `operatorIds` e
              // pode virar null quando o operador deixa de ser elegível (ex.:
              // membro removido). A ValueKey força o re-seed do `initialValue`
              // nesses casos, evitando o assert de "exactly one item with value"
              // quando a lista de items encolhe.
              key: ValueKey(selectedSingle),
              initialValue: selectedSingle,
              decoration: const InputDecoration(
                labelText: 'Operador padrão',
                border: OutlineInputBorder(),
              ),
              items: operators
                  .map((user) => DropdownMenuItem(
                        value: user.id,
                        child: Text(user.fullName),
                      ))
                  .toList(),
              onChanged: (value) {
                widget.operatorIds.clear();
                if (value != null) widget.operatorIds.add(value);
                widget.onOperatorsChanged();
                setState(() {});
              },
            )
          else ...[
            if (operators.isEmpty)
              Text('Selecione membros para definir operadores.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: operators.map((user) {
                  final selected = widget.operatorIds.contains(user.id);
                  return FilterChip(
                    selected: selected,
                    avatar: CircleAvatar(child: Text(user.initials)),
                    label: Text(user.fullName),
                    onSelected: (value) {
                      if (value) {
                        widget.operatorIds.add(user.id);
                      } else {
                        widget.operatorIds.remove(user.id);
                      }
                      widget.onOperatorsChanged();
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 8),
            Text(
              widget.operatorIds.isEmpty
                  ? 'Sem operadores marcados: qualquer membro do canal poderá assumir.'
                  : '${widget.operatorIds.length} operador(es) poderão assumir cards.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }
}
