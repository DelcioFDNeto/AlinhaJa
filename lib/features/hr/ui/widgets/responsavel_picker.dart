import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/features/hr/providers/talent_bank_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-13 — Seletor de responsável (usuários da org, com busca).
/// Aberto como bottom sheet; retorna o id do usuário, '' para
/// "remover responsável", ou null quando cancelado.
class ResponsavelPicker extends ConsumerStatefulWidget {
  const ResponsavelPicker({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ResponsavelPicker(),
    );
  }

  @override
  ConsumerState<ResponsavelPicker> createState() => _ResponsavelPickerState();
}

class _ResponsavelPickerState extends ConsumerState<ResponsavelPicker> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(orgUsersProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Text('Atribuir responsável',
              style: Theme.of(context).textTheme.titleMedium),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _busca = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Buscar por nome ou e-mail…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: usersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: ${friendlyError(e)}')),
              data: (users) {
                final filtrados = users.where((u) {
                  if (_busca.isEmpty) return true;
                  final nome = (u['full_name'] as String? ?? '').toLowerCase();
                  final email = (u['email'] as String? ?? '').toLowerCase();
                  return nome.contains(_busca) || email.contains(_busca);
                }).toList();
                return ListView(
                  controller: scrollController,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('Remover responsável'),
                      onTap: () => Navigator.pop(context, ''),
                    ),
                    const Divider(height: 1),
                    for (final u in filtrados)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            ((u['full_name'] as String? ?? '?').isNotEmpty
                                    ? (u['full_name'] as String)[0]
                                    : '?')
                                .toUpperCase(),
                          ),
                        ),
                        title: Text((u['full_name'] as String?) ?? 'Sem nome'),
                        subtitle: Text((u['email'] as String?) ?? ''),
                        onTap: () => Navigator.pop(context, u['id'] as String),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
