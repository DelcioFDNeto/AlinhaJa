import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/features/channels/providers/active_channel_provider.dart';

/// Descrição de cada nível de notificação de canal.
class ChannelNotificationLevel {
  final String value;
  final String label;
  final String description;
  final IconData icon;

  const ChannelNotificationLevel({
    required this.value,
    required this.label,
    required this.description,
    required this.icon,
  });

  static const all = ChannelNotificationLevel(
    value: 'all',
    label: 'Todas as mensagens',
    description: 'Notifica qualquer mensagem publicada no canal',
    icon: Icons.notifications_active_outlined,
  );

  static const mentions = ChannelNotificationLevel(
    value: 'mentions',
    label: 'Somente menções',
    description: 'Notifica apenas quando você for citado ou usarem @canal',
    icon: Icons.alternate_email,
  );

  static const none = ChannelNotificationLevel(
    value: 'none',
    label: 'Silenciado',
    description: 'Nenhuma notificação — o canal continua na sua lista',
    icon: Icons.notifications_off_outlined,
  );

  static const values = [all, mentions, none];

  static ChannelNotificationLevel resolve(String? value) {
    return values.firstWhere(
      (level) => level.value == value,
      orElse: () => all,
    );
  }
}

/// Ícone da barra do canal que abre o seletor de notificação.
///
/// Mostra o estado atual de relance: sino cheio, arroba ou sino cortado.
class ChannelNotificationButton extends ConsumerWidget {
  final String channelId;

  const ChannelNotificationButton({super.key, required this.channelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(activeChannelProvider(ChannelArgs(channelId: channelId)));
    final level = ChannelNotificationLevel.resolve(state.notificationLevel);
    final isDefault = level.value == 'all';

    return IconButton(
      icon: Icon(
        level.icon,
        color: isDefault ? null : Theme.of(context).colorScheme.primary,
      ),
      tooltip: 'Notificações: ${level.label}',
      onPressed: () => showChannelNotificationSheet(context, ref, channelId),
    );
  }
}

/// Folha de seleção do nível de notificação do canal.
///
/// A preferência é pessoal (linha do usuário em `channel_members`), então
/// qualquer membro pode alterá-la — não é configuração de administrador.
Future<void> showChannelNotificationSheet(
  BuildContext context,
  WidgetRef ref,
  String channelId,
) async {
  final notifier =
      ref.read(activeChannelProvider(ChannelArgs(channelId: channelId)).notifier);
  final current =
      ref.read(activeChannelProvider(ChannelArgs(channelId: channelId)))
          .notificationLevel;

  final selected = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.notifications_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text('Notificações deste canal',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            ...ChannelNotificationLevel.values.map((level) {
              final isSelected = level.value == current;
              return ListTile(
                leading: Icon(level.icon,
                    color: isSelected ? theme.colorScheme.primary : null),
                title: Text(
                  level.label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w700 : null,
                    color: isSelected ? theme.colorScheme.primary : null,
                  ),
                ),
                subtitle: Text(level.description,
                    style: const TextStyle(fontSize: 12)),
                trailing: isSelected
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, level.value),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (selected == null || selected == current || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await notifier.setNotificationLevel(selected);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
            'Notificações: ${ChannelNotificationLevel.resolve(selected).label}'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Não foi possível alterar: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
