import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Cartão de contato compartilhado na conversa.
class ContactCard extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String? phone;
  final String? email;
  final String? avatarUrl;

  /// UUID do usuário — se presente, habilita o botão "Mensagem" para DM direta.
  final String? userId;

  final double maxWidth;

  const ContactCard({
    super.key,
    required this.name,
    this.subtitle,
    this.phone,
    this.email,
    this.avatarUrl,
    this.userId,
    this.maxWidth = 280,
  });

  String get _initials => name.isNotEmpty ? name[0].toUpperCase() : '?';

  Future<void> _call(BuildContext context) async {
    final digits = phone!.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$digits');
    try {
      if (!await launchUrl(uri, mode: LaunchMode.platformDefault) &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível iniciar a chamada.')),
        );
      }
    } catch (e) {
      debugPrint('Erro ao ligar: $e');
    }
  }

  Future<void> _copy(BuildContext context) async {
    final value = phone ?? email ?? name;
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copiado: $value')),
      );
    }
  }

  void _openDm(BuildContext context) {
    if (userId == null || userId!.isEmpty) return;
    context.push('/chat/new_dm_$userId', extra: {'name': name});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUserId = userId != null && userId!.isNotEmpty;
    final hasPhone = phone != null && phone!.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar + info ──
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: hasUserId ? () => _openDm(context) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundImage:
                          avatarUrl != null && avatarUrl!.isNotEmpty
                              ? CachedNetworkImageProvider(avatarUrl!, maxWidth: 320)
                              : null,
                      child: avatarUrl == null || avatarUrl!.isEmpty
                          ? Text(_initials,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          if (hasPhone)
                            Text(
                              phone!,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          // ── Botões de ação ──
          Row(
            children: [
              // Botão de Mensagem direta (DM)
              if (hasUserId)
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _openDm(context),
                    icon: Icon(Icons.chat_bubble_outline_rounded,
                        size: 16, color: theme.colorScheme.primary),
                    label: Text('Mensagem',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary)),
                  ),
                ),
              // Botão de Ligar
              if (hasPhone)
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _call(context),
                    icon: const Icon(Icons.call_rounded, size: 16),
                    label:
                        const Text('Ligar', style: TextStyle(fontSize: 12)),
                  ),
                ),
              // Botão de Copiar
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label:
                      const Text('Copiar', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
