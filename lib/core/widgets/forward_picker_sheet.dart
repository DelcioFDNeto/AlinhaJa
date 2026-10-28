import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/services/message_forward_service.dart';
import 'package:alinha_ja/features/channels/providers/channels_list_provider.dart';
import 'package:alinha_ja/features/chats/ui/chats_list_screen.dart';

/// Abre o seletor de destino do encaminhamento e devolve a escolha.
///
/// Lista conversas e canais na mesma folha para que encaminhar de uma DM para
/// um canal (e vice-versa) seja o mesmo gesto.
Future<ForwardTarget?> showForwardPicker(
  BuildContext context, {
  String? excludeId,
}) {
  return showModalBottomSheet<ForwardTarget>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, scrollController) => _ForwardPickerBody(
        scrollController: scrollController,
        excludeId: excludeId,
      ),
    ),
  );
}

class _ForwardPickerBody extends ConsumerWidget {
  final ScrollController scrollController;
  final String? excludeId;

  const _ForwardPickerBody({
    required this.scrollController,
    this.excludeId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chats = ref.watch(chatsListProvider);
    final channels = ref.watch(channelsListProvider);

    final chatTargets = (chats.valueOrNull ?? [])
        .where((c) => c.id != excludeId)
        .map((c) =>
            ForwardTarget(id: c.id, name: c.displayName, isChannel: false))
        .toList();

    final channelTargets = (channels.valueOrNull ?? [])
        .where((c) => c.id != excludeId)
        .map((c) => ForwardTarget(id: c.id, name: c.name, isChannel: true))
        .toList();

    final isLoading = chats.isLoading || channels.isLoading;

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Encaminhar para...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: isLoading && chatTargets.isEmpty && channelTargets.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: scrollController,
                  children: [
                    if (chatTargets.isNotEmpty)
                      _SectionHeader(label: 'Conversas', theme: theme),
                    ...chatTargets.map((t) => _TargetTile(target: t)),
                    if (channelTargets.isNotEmpty)
                      _SectionHeader(label: 'Canais', theme: theme),
                    ...channelTargets.map((t) => _TargetTile(target: t)),
                    if (chatTargets.isEmpty && channelTargets.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child:
                            Center(child: Text('Nenhum destino disponível.')),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _SectionHeader({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  final ForwardTarget target;

  const _TargetTile({required this.target});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: target.isChannel
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.primary,
        child: target.isChannel
            ? Icon(Icons.tag, color: theme.colorScheme.onSecondaryContainer)
            : Text(
                target.name.isNotEmpty ? target.name[0].toUpperCase() : '?',
                style: TextStyle(color: theme.colorScheme.onPrimary),
              ),
      ),
      title: Text(target.name),
      onTap: () => Navigator.pop(context, target),
    );
  }
}
