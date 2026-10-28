import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alinha_ja/core/models/announcement_spec.dart';
import 'package:alinha_ja/core/models/message_ref.dart';
import 'package:alinha_ja/core/services/media_url_resolver.dart';
import 'package:alinha_ja/core/ui/message_cards/message_action_providers.dart';

/// Card de anúncio oficial, igual em canal e em grupo.
///
/// Antes o anúncio era um bloco fixo dentro da bolha do canal — grupo não
/// tinha o recurso e não havia prioridade, prazo nem público. Agora tudo vem
/// do [AnnouncementSpec] gravado no metadata.
class AnnouncementCard extends ConsumerWidget {
  final MessageRef message;
  final AnnouncementSpec spec;
  final String? content;
  final String senderName;

  /// Autor vê o placar de confirmações; destinatário vê o botão de confirmar.
  final bool isMine;

  /// Abre o painel de quem confirmou. Quando nulo, o placar não é clicável.
  final VoidCallback? onShowAckDetails;

  final double maxWidth;

  const AnnouncementCard({
    super.key,
    required this.message,
    required this.spec,
    required this.senderName,
    this.content,
    this.isMine = false,
    this.onShowAckDetails,
    this.maxWidth = 420,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final style = spec.style;
    final expired = spec.isExpired;

    // Vencido perde a cor: continua legível no histórico sem competir com o
    // que ainda está valendo.
    final accent = expired ? theme.colorScheme.outline : style.color;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
          color: accent.withValues(alpha: expired ? 0.04 : 0.08),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme, accent, expired),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    senderName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    content ?? '',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (!spec.audience.isEveryone) ...[
                    const SizedBox(height: 10),
                    _buildAudience(theme),
                  ],
                  if (spec.attachment != null) ...[
                    const SizedBox(height: 10),
                    _AttachmentTile(attachment: spec.attachment!),
                  ],
                  if (spec.validUntil != null) ...[
                    const SizedBox(height: 8),
                    _buildValidity(theme, accent, expired),
                  ],
                ],
              ),
            ),
            if (spec.action != null || spec.requiresAck)
              _buildFooter(context, ref, theme, accent, expired),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Color accent, bool expired) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: accent.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(spec.style.icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              expired
                  ? 'ANÚNCIO ENCERRADO'
                  : 'ANÚNCIO · ${spec.style.label.toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: accent,
              ),
            ),
          ),
          if (spec.pinned && !expired)
            Icon(Icons.push_pin_rounded, size: 14, color: accent),
        ],
      ),
    );
  }

  Widget _buildAudience(ThemeData theme) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        Text(
          'Para:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final label in spec.audience.labels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
      ],
    );
  }

  Widget _buildValidity(ThemeData theme, Color accent, bool expired) {
    final validUntil = spec.validUntil!.toLocal();
    final formatted = DateFormat("d 'de' MMM 'de' y", 'pt_BR').format(validUntil);
    final days = validUntil.difference(DateTime.now()).inDays;

    final String text;
    if (expired) {
      text = 'Encerrado em $formatted';
    } else if (days <= 0) {
      text = 'Válido só até hoje';
    } else if (days == 1) {
      text = 'Válido até amanhã';
    } else {
      text = 'Válido até $formatted · faltam $days dias';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_rounded, size: 13, color: accent),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    Color accent,
    bool expired,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: accent.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        children: [
          if (spec.action != null)
            Flexible(
              child: _ActionButton(action: spec.action!, accent: accent),
            ),
          const Spacer(),
          if (spec.requiresAck)
            _AckControl(
              message: message,
              accent: accent,
              isMine: isMine,
              expired: expired,
              onShowDetails: onShowAckDetails,
            ),
        ],
      ),
    );
  }
}

/// Botão configurável do rodapé (link, documento, card do workflow, presença).
class _ActionButton extends ConsumerWidget {
  final AnnouncementAction action;
  final Color accent;

  const _ActionButton({required this.action, required this.accent});

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    switch (action.kind) {
      case AnnouncementActionKind.link:
      case AnnouncementActionKind.document:
        final raw = action.value;
        if (raw == null || raw.isEmpty) return;
        try {
          // `link` e `document` compartilham este ramo: o link aponta para fora
          // e o documento costuma morar no `chat-media`, que e privado. O
          // resolver assina o que e do bucket e devolve intacto o que nao e,
          // entao os dois casos passam pelo mesmo caminho sem se atrapalhar.
          final resolved = await MediaUrlResolver.resolve(raw);
          final uri = Uri.tryParse(resolved);
          if (uri == null) return;
          await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
            webOnlyWindowName: '_blank',
          );
        } catch (e) {
          debugPrint('Erro ao abrir destino do anúncio: $e');
        }

      case AnnouncementActionKind.confirmPresence:
      case AnnouncementActionKind.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = switch (action.kind) {
      AnnouncementActionKind.link => Icons.open_in_new_rounded,
      AnnouncementActionKind.document => Icons.description_outlined,
      AnnouncementActionKind.confirmPresence => Icons.event_available_rounded,
      AnnouncementActionKind.none => Icons.circle,
    };

    return TextButton.icon(
      onPressed: () => _run(context, ref),
      icon: Icon(icon, size: 16, color: accent),
      label: Text(
        action.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: accent),
      ),
    );
  }
}

/// Confirmação de leitura: botão para quem recebe, placar para quem publicou.
class _AckControl extends ConsumerWidget {
  final MessageRef message;
  final Color accent;
  final bool isMine;
  final bool expired;
  final VoidCallback? onShowDetails;

  const _AckControl({
    required this.message,
    required this.accent,
    required this.isMine,
    required this.expired,
    this.onShowDetails,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isMine) {
      final acked = ref.watch(messageAckedByProvider(message)).valueOrNull;
      final count = acked?.length ?? 0;

      return TextButton.icon(
        onPressed: onShowDetails,
        icon: Icon(Icons.how_to_reg_rounded, size: 16, color: accent),
        label: Text(
          count == 1 ? '1 confirmação' : '$count confirmações',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: accent),
        ),
      );
    }

    final alreadyAcked =
        ref.watch(messageAckedProvider(message)).valueOrNull ?? false;

    if (alreadyAcked) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(
            'Confirmado',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: accent),
          ),
        ],
      );
    }

    return FilledButton.icon(
      // Anúncio vencido vira histórico: não se cobra ciência depois do prazo.
      onPressed: expired ? null : () => _confirm(context, ref),
      icon: const Icon(Icons.how_to_reg_rounded, size: 16),
      label: const Text('Li e confirmo', style: TextStyle(fontSize: 12)),
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await setMessageAction(
        message,
        actionType: 'acknowledge',
        value: 'confirmed',
      );
      ref.invalidate(messageAckedProvider(message));
      ref.invalidate(messageAckedByProvider(message));
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Confirmação registrada!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao confirmar: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

class _AttachmentTile extends StatelessWidget {
  final AnnouncementAttachment attachment;

  const _AttachmentTile({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        try {
          // O anexo sobe pelo MediaService e fica no `chat-media`; com o bucket
          // privado a URL gravada so resolve depois de assinada.
          final resolved = await MediaUrlResolver.resolve(
            attachment.url,
            downloadFileName: attachment.name,
          );
          final uri = Uri.tryParse(resolved);
          if (uri == null) return;
          await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
            webOnlyWindowName: '_blank',
          );
        } catch (e) {
          debugPrint('Erro ao abrir anexo do anúncio: $e');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.description_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  if (attachment.readableSize.isNotEmpty)
                    Text(
                      attachment.readableSize,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.download_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}
