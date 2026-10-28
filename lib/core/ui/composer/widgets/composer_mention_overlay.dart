import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:alinha_ja/core/ui/composer/composer_delegate.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';

/// Sugestões de menção (@) exibidas acima do campo de texto.
///
/// As menções coletivas (`@canal`, `@aqui`) aparecem no topo, antes das
/// pessoas, porque alcançam mais gente e o usuário precisa vê-las.
class ComposerMentionOverlay extends StatelessWidget {
  final List<UserModel> members;
  final ValueChanged<UserModel> onSelected;
  final List<ComposerBroadcastMention> broadcasts;
  final ValueChanged<ComposerBroadcastMention>? onBroadcastSelected;

  const ComposerMentionOverlay({
    super.key,
    required this.members,
    required this.onSelected,
    this.broadcasts = const [],
    this.onBroadcastSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty && broadcasts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: broadcasts.length + members.length,
        itemBuilder: (context, i) {
          if (i < broadcasts.length) {
            final broadcast = broadcasts[i];
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(broadcast.icon,
                    size: 16, color: theme.colorScheme.onPrimaryContainer),
              ),
              title: Text(
                '@${broadcast.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                broadcast.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => onBroadcastSelected?.call(broadcast),
            );
          }

          final member = members[i - broadcasts.length];
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundImage: member.avatarUrl != null
                  ? CachedNetworkImageProvider(member.avatarUrl!, maxWidth: 320)
                  : null,
              child: member.avatarUrl == null
                  ? Text(member.initials, style: const TextStyle(fontSize: 12))
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
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () => onSelected(member),
          );
        },
      ),
    );
  }
}
