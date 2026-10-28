import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/extensions.dart';
import 'package:alinha_ja/core/models/message_receipts.dart';
import 'package:alinha_ja/core/providers/message_receipts_provider.dart';
import 'package:alinha_ja/core/widgets/signed_network_image.dart';

/// "Informações da mensagem": quem recebeu e quem leu, nome por nome.
///
/// Os checks da bolha são um resumo de todo mundo — em grupo, dois checks
/// azuis querem dizer "alguém leu", não "todos leram". Quem manda a escala do
/// fim de semana ou o procedimento de fechamento precisa saber de QUEM está
/// faltando, e é isso que esta folha responde.
///
/// A mesma folha serve chat e canal: a diferença é só a tabela consultada,
/// que viaja no [ReceiptScope].
class MessageInfoSheet extends ConsumerWidget {
  const MessageInfoSheet({
    super.key,
    required this.messageId,
    required this.scope,
    this.preview,
  });

  final String messageId;
  final ReceiptScope scope;

  /// Trecho da mensagem, para a folha não virar uma lista de nomes solta.
  final String? preview;

  static Future<void> show(
    BuildContext context, {
    required String messageId,
    required ReceiptScope scope,
    String? preview,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MessageInfoSheet(
        messageId: messageId,
        scope: scope,
        preview: preview,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final args = MessageReceiptArgs(messageId: messageId, scope: scope);
    final receipts = ref.watch(messageReceiptsProvider(args));

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Informações da mensagem',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          if (preview != null && preview!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(
                        color: theme.colorScheme.primary, width: 3),
                  ),
                ),
                child: Text(
                  preview!.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          Expanded(
            child: receipts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorBody(
                onRetry: () =>
                    ref.invalidate(messageReceiptsProvider(args)),
              ),
              data: (summary) => _ReceiptsBody(
                summary: summary,
                scrollController: scrollController,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'Não foi possível carregar os recibos',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'A mensagem pode ter sido apagada, ou você saiu da conversa.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 12),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptsBody extends StatelessWidget {
  const _ReceiptsBody({
    required this.summary,
    required this.scrollController,
  });

  final MessageReceiptSummary summary;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final read = summary.whereState(ReceiptState.read);
    final delivered = summary.whereState(ReceiptState.delivered);
    final pending = summary.whereState(ReceiptState.pending);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        if (summary.sentAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.schedule,
                    size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text(
                  'Enviada ${summary.sentAt!.dateSeparatorFormatted.toLowerCase()} '
                  'às ${summary.sentAt!.timeFormatted}',
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),

        // Cabeçalho de contagens. Numa conversa de duas pessoas ele daria
        // "1 de 1 leu", que é pior do que a frase que a seção já diz.
        if (!summary.isOneToOne) ...[
          Row(
            children: [
              Expanded(
                child: _CountTile(
                  icon: Icons.done_all,
                  color: const Color(0xFF2196F3),
                  value: summary.readCount,
                  label: 'leram',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CountTile(
                  icon: Icons.done_all,
                  color: theme.colorScheme.outline,
                  value: summary.deliveredCount,
                  label: 'receberam',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CountTile(
                  icon: Icons.schedule,
                  color: const Color(0xFFFB8C00),
                  value: summary.pendingCount,
                  label: 'pendentes',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (summary.everyoneRead)
            const _Banner(
              icon: Icons.check_circle,
              color: Color(0xFF43A047),
              text: 'Todo mundo da conversa já leu esta mensagem.',
            )
          else
            _Banner(
              icon: Icons.info_outline,
              color: theme.colorScheme.outline,
              text: '${summary.readCount} de ${summary.recipientCount} '
                  'destinatários leram.',
            ),
          const SizedBox(height: 8),
        ],

        _Section(
          title: 'Leram',
          emptyText: 'Ninguém abriu a conversa depois desta mensagem.',
          icon: Icons.done_all,
          color: const Color(0xFF2196F3),
          people: read,
        ),
        _Section(
          title: 'Receberam, ainda não leram',
          emptyText: 'Ninguém neste estado.',
          icon: Icons.done_all,
          color: theme.colorScheme.outline,
          people: delivered,
        ),
        _Section(
          title: 'Ainda não receberam',
          emptyText: 'A mensagem chegou em todos os aparelhos.',
          icon: Icons.schedule,
          color: const Color(0xFFFB8C00),
          people: pending,
        ),

        const SizedBox(height: 12),
        Text(
          'O horário é o da última vez que a pessoa abriu a conversa, não o '
          'segundo exato da leitura.',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.outline,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text('$value',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12.5, color: color)),
          ),
        ],
      ),
    );
  }
}

/// Um grupo de destinatários.
///
/// A seção vazia continua na tela, com uma frase no lugar da lista: sumir com
/// ela deixaria "ninguém ainda leu" indistinguível de "esta parte não existe".
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.emptyText,
    required this.icon,
    required this.color,
    required this.people,
  });

  final String title;
  final String emptyText;
  final IconData icon;
  final Color color;
  final List<MessageReceipt> people;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                '$title (${people.length})',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 21, bottom: 4),
            child: Text(
              emptyText,
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.outline,
                  fontStyle: FontStyle.italic),
            ),
          )
        else
          for (final person in people) _PersonTile(person: person),
      ],
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final MessageReceipt person;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = person.avatarUrl;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        child: avatar != null && avatar.isNotEmpty
            ? ClipOval(
                child: SignedNetworkImage(
                  storedUrl: avatar,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _Initial(name: person.fullName),
                  errorWidget: (_, __, ___) => _Initial(name: person.fullName),
                ),
              )
            : _Initial(name: person.fullName),
      ),
      title: Text(person.fullName, style: const TextStyle(fontSize: 13.5)),
      trailing: person.at == null
          ? null
          : Text(
              person.at!.dateSeparatorFormatted == 'Hoje'
                  ? person.at!.timeFormatted
                  : '${person.at!.chatListFormatted} · '
                      '${person.at!.timeFormatted}',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
            ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
