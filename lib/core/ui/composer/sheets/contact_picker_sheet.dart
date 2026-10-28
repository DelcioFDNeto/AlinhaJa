import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:alinha_ja/features/profile/models/user_model.dart';

/// Seleção de um membro para compartilhar como cartão de contato.
class ContactPickerSheet extends StatefulWidget {
  final List<UserModel> members;

  const ContactPickerSheet({super.key, required this.members});

  static Future<UserModel?> show(
    BuildContext context, {
    required List<UserModel> members,
  }) {
    return showModalBottomSheet<UserModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ContactPickerSheet(members: members),
    );
  }

  @override
  State<ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<ContactPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<UserModel> get _filtered {
    final query = _query.trim().toLowerCase();
    final list = query.isEmpty
        ? List<UserModel>.from(widget.members)
        : widget.members
            .where((m) =>
                m.fullName.toLowerCase().contains(query) ||
                (m.departmentName ?? '').toLowerCase().contains(query) ||
                (m.jobPositionName ?? '').toLowerCase().contains(query))
            .toList();
    list.sort((a, b) => a.fullName.compareTo(b.fullName));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = _filtered;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.person_rounded,
                        color: theme.colorScheme.primary, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Compartilhar contato',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nome, setor ou cargo',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: members.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum contato encontrado',
                          style: TextStyle(color: theme.colorScheme.outline),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: members.length,
                        itemBuilder: (context, i) {
                          final member = members[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: member.avatarUrl != null
                                  ? CachedNetworkImageProvider(
                                      member.avatarUrl!, maxWidth: 320)
                                  : null,
                              child: member.avatarUrl == null
                                  ? Text(member.initials)
                                  : null,
                            ),
                            title: Text(
                              member.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              member.displaySubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.of(context).pop(member),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
