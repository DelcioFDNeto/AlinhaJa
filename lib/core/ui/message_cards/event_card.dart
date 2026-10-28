import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Card de evento agendado.
class EventCard extends StatelessWidget {
  final String title;
  final DateTime date;
  final double maxWidth;

  const EventCard({
    super.key,
    required this.title,
    required this.date,
    this.maxWidth = 300,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = date.toLocal();
    final isPast = local.isBefore(DateTime.now());
    final accent = isPast ? theme.colorScheme.outline : const Color(0xFF0A84FF);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bloco de calendário: dia grande, mês abreviado.
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('MMM', 'pt_BR').format(local).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  DateFormat('dd').format(local),
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isPast ? 'EVENTO REALIZADO' : 'EVENTO AGENDADO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_note_rounded,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        DateFormat("EEEE, d 'de' MMMM · HH:mm", 'pt_BR')
                            .format(local),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
