// Helpers compartilhados do módulo Workflow.
// Evita duplicação de código entre board_view e list_view.

/// Formata data relativa para exibição nos cards.
String formatWorkflowDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inSeconds < 60) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24 && diff.inDays == 0) return 'Hoje';
  if (diff.inDays == 1) return 'Ontem';
  if (diff.inDays < 7) return '${diff.inDays}d atrás';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}

/// Verifica se a data está atrasada (antes de hoje).
bool isOverdue(DateTime? date) {
  if (date == null) return false;
  final today =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  return date.isBefore(today);
}

/// Calcula dias restantes para vencimento (negativo = atrasado).
int daysUntilDue(DateTime? date) {
  if (date == null) return 0;
  final today =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final target = DateTime(date.year, date.month, date.day);
  return target.difference(today).inDays;
}

/// Formata o tempo que o card está parado no status atual.
String formatStatusAge(DateTime updatedAt) {
  final diff = DateTime.now().difference(updatedAt);
  if (diff.inMinutes < 1) return 'Agora';
  if (diff.inMinutes < 60) return 'Há ${diff.inMinutes}min';
  if (diff.inHours < 24) return 'Há ${diff.inHours}h';
  if (diff.inDays == 1) return 'Há 1 dia';
  if (diff.inDays < 7) return 'Há ${diff.inDays} dias';
  if (diff.inDays < 30) return 'Há ${(diff.inDays / 7).floor()} sem';
  return 'Há ${(diff.inDays / 30).floor()} mês${(diff.inDays / 30).floor() > 1 ? 'es' : ''}';
}

/// Retorna um valor de cor baseado em quanto tempo o card está parado.
/// 0 = normal (cinza), 1 = atenção (amarelo/laranja), 2 = crítico (vermelho)
int statusAgeSeverity(DateTime updatedAt) {
  final hours = DateTime.now().difference(updatedAt).inHours;
  if (hours >= 72) return 2; // Crítico: > 3 dias
  if (hours >= 24) return 1; // Atenção: > 1 dia
  return 0; // Normal
}

/// Retorna o limite do SLA em horas baseado na prioridade.
int getSlaLimitInHours(String priorityName) {
  final p = priorityName.toLowerCase();
  if (p == 'urgent' || p == 'urgente') return 4;
  if (p == 'high' || p == 'alta') return 12;
  if (p == 'medium' || p == 'media' || p == 'média') return 24;
  return 48; // low ou default
}

/// Verifica se o card estourou o SLA do status atual.
bool isSlaExceeded(DateTime updatedAt, String priorityName,
    {bool isFinalStatus = false}) {
  if (isFinalStatus) return false;
  final limit = getSlaLimitInHours(priorityName);
  final hours = DateTime.now().difference(updatedAt).inHours;
  return hours >= limit;
}
