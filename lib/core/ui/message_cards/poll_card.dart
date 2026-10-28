import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/models/message_ref.dart';
import 'package:alinha_ja/core/ui/message_cards/message_action_providers.dart';

/// Card de enquete com votação ao vivo.
///
/// Serve chat 1:1, grupos e canais: só precisa do id da mensagem, da pergunta
/// e das opções — o resto vem de `message_actions`.
class PollCard extends ConsumerWidget {
  final MessageRef message;
  final String question;
  final List<String> options;
  final bool allowsMultiple;

  /// Largura máxima do card dentro da bolha.
  final double maxWidth;

  const PollCard({
    super.key,
    required this.message,
    required this.question,
    required this.options,
    this.allowsMultiple = false,
    this.maxWidth = 320,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final myVote = ref.watch(pollMyVoteProvider(message)).valueOrNull ?? [];
    final results = ref.watch(pollResultsProvider(message)).valueOrNull ?? {};
    final totalVotes = results.values.fold<int>(0, (sum, v) => sum + v);
    final hasVoted = myVote.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.poll_rounded, size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                allowsMultiple ? 'Enquete · múltipla' : 'Enquete',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            question,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          for (final option in options)
            _PollOption(
              label: option,
              votes: results[option] ?? 0,
              total: totalVotes,
              selected: myVote.contains(option),
              revealResults: hasVoted,
              onTap: () => _vote(ref, myVote, option),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                totalVotes == 1 ? '1 voto' : '$totalVotes votos',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (hasVoted) ...[
                const SizedBox(width: 8),
                Text(
                  '· toque para alterar',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.8),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _vote(
    WidgetRef ref,
    List<String> currentVote,
    String option,
  ) async {
    final List<String> next;
    if (allowsMultiple) {
      next = currentVote.contains(option)
          ? (List<String>.from(currentVote)..remove(option))
          : [...currentVote, option];
    } else {
      next = currentVote.contains(option) ? const [] : [option];
    }

    try {
      await submitPollVote(message, next);
      ref.invalidate(pollMyVoteProvider(message));
      ref.invalidate(pollResultsProvider(message));
    } catch (e) {
      debugPrint('Erro ao votar na enquete: $e');
    }
  }
}

class _PollOption extends StatelessWidget {
  final String label;
  final int votes;
  final int total;
  final bool selected;
  final bool revealResults;
  final VoidCallback onTap;

  const _PollOption({
    required this.label,
    required this.votes,
    required this.total,
    required this.selected,
    required this.revealResults,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = total == 0 ? 0.0 : votes / total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: revealResults
                  ? theme.colorScheme.primary
                      .withValues(alpha: selected ? 0.25 : 0.08)
                  : null,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 17,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (revealResults)
                  Text(
                    '${(percent * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
