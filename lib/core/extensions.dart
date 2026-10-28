import 'package:timeago/timeago.dart' as timeago;

extension DateTimeExtensions on DateTime {
  /// Formata como "14:30"
  String get timeFormatted {
    final local = toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// "Hoje", "Ontem" ou "dd/MM/yyyy"
  String get chatListFormatted {
    final now = DateTime.now();
    final local = toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(local.year, local.month, local.day);
    final diff = today.difference(dateOnly).inDays;
    if (diff == 0) return timeFormatted;
    if (diff == 1) return 'Ontem';
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  /// "há 5 minutos", "ontem" etc.
  String get timeAgo => timeago.format(toLocal(), locale: 'pt_BR');

  /// Separador de data para chat: "Hoje", "Ontem", "Segunda-feira", ou "10 de março de 2026"
  String get dateSeparatorFormatted {
    final now = DateTime.now();
    final local = toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(local.year, local.month, local.day);
    final diff = today.difference(dateOnly).inDays;

    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    if (diff < 7) {
      const days = [
        'Segunda-feira',
        'Terça-feira',
        'Quarta-feira',
        'Quinta-feira',
        'Sexta-feira',
        'Sábado',
        'Domingo'
      ];
      return days[local.weekday - 1];
    }

    const months = [
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro'
    ];
    return '${local.day} de ${months[local.month - 1]} de ${local.year}';
  }
}

extension IntExtensions on int {
  String get fileSizeFormatted {
    if (this < 1024) return '$this B';
    if (this < 1024 * 1024) return '${(this / 1024).toStringAsFixed(0)} KB';
    return '${(this / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
