import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/models/message_extras.dart';

/// Evento pronto para virar mensagem.
class EventDraft {
  final String title;
  final DateTime date;

  const EventDraft({required this.title, required this.date});

  /// Prefixo 📅 mantém a prévia da lista de conversas legível sem abrir o card.
  String get content => '📅 $title';

  Map<String, dynamic> get metadata =>
      MessageExtras.event(title: title, date: date);
}

/// Agendamento de evento em uma folha só.
///
/// A versão anterior encadeava três diálogos (data → hora → título); aqui tudo
/// fica visível na mesma tela e dá para corrigir antes de publicar.
class ScheduleEventSheet extends StatefulWidget {
  const ScheduleEventSheet({super.key});

  static Future<EventDraft?> show(BuildContext context) {
    return showModalBottomSheet<EventDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ScheduleEventSheet(),
    );
  }

  @override
  State<ScheduleEventSheet> createState() => _ScheduleEventSheetState();
}

class _ScheduleEventSheetState extends State<ScheduleEventSheet> {
  final _titleCtrl = TextEditingController();
  late DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  DateTime get _dateTime => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'Data do evento',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Horário do evento',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dê um título ao evento.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Navigator.of(context).pop(EventDraft(title: title, date: _dateTime));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted =
        DateFormat("EEEE, d 'de' MMMM 'de' y", 'pt_BR').format(_dateTime);

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.event_rounded,
                    color: theme.colorScheme.primary, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Agendar evento',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Título do evento',
                hintText: 'Ex: Reunião de alinhamento',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _PickerTile(
                    icon: Icons.calendar_today_rounded,
                    label: DateFormat('dd/MM/yyyy').format(_dateTime),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PickerTile(
                    icon: Icons.schedule_rounded,
                    label: _time.format(context),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              formatted,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Publicar evento',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
