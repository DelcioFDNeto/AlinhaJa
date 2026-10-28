import 'package:flutter/material.dart';

/// Registry centralizado que mapeia nomes de ícones para instâncias `const` de [IconData].
///
/// Isso permite que o Flutter faça tree-shaking dos ícones de Material não utilizados,
/// já que todas as referências são const em tempo de compilação.
///
/// Para adicionar novos ícones disponíveis nos canais, basta incluir aqui.
class IconRegistry {
  IconRegistry._();

  static const IconData defaultIcon = Icons.workspaces_rounded;

  /// Mapa de nomes → IconData const.
  static const Map<String, IconData> _icons = {
    // Financeiro
    'payments': Icons.payments_outlined,
    'payments_outlined': Icons.payments_outlined,
    'account_balance': Icons.account_balance_outlined,
    'credit_card': Icons.credit_card_outlined,
    'attach_money': Icons.attach_money,
    'savings': Icons.savings_outlined,

    // Veículos / Motos
    'two_wheeler': Icons.two_wheeler,
    'directions_car': Icons.directions_car_outlined,
    'directions_car_outlined': Icons.directions_car_outlined,
    'local_shipping': Icons.local_shipping_outlined,
    'garage': Icons.garage_outlined,

    // Faturamento / OS
    'receipt_long': Icons.receipt_long_outlined,
    'receipt_long_outlined': Icons.receipt_long_outlined,
    'receipt': Icons.receipt_outlined,
    'receipt_outlined': Icons.receipt_outlined,
    'assignment': Icons.assignment_outlined,
    'description': Icons.description_outlined,

    // Operacional / Ferramentas
    'build_circle': Icons.build_circle_outlined,
    'build_circle_outlined': Icons.build_circle_outlined,
    'build': Icons.build_outlined,
    'engineering': Icons.engineering_outlined,
    'construction': Icons.construction_outlined,
    'handyman': Icons.handyman_outlined,

    // Comunicação / Informativo
    'campaign': Icons.campaign_outlined,
    'campaign_outlined': Icons.campaign_outlined,
    'announcement': Icons.announcement_outlined,
    'forum': Icons.forum_outlined,
    'chat': Icons.chat_outlined,
    'notifications': Icons.notifications_outlined,

    // RH / Pessoas
    'people': Icons.people_outline,
    'people_outline': Icons.people_outline,
    'group': Icons.group_outlined,
    'person': Icons.person_outlined,
    'badge': Icons.badge_outlined,
    'support_agent': Icons.support_agent_rounded,

    // Geral / Workspace
    'workspaces': Icons.workspaces_rounded,
    'workspaces_rounded': Icons.workspaces_rounded,
    'dashboard': Icons.dashboard_outlined,
    'dashboard_customize': Icons.dashboard_customize_outlined,
    'inventory': Icons.inventory_outlined,
    'category': Icons.category_outlined,
    'settings': Icons.settings_outlined,
    'task': Icons.task_outlined,
    'checklist': Icons.checklist_outlined,
    'fact_check': Icons.fact_check_outlined,
    'verified': Icons.verified_outlined,
    'star': Icons.star_outlined,
    'flag': Icons.flag_outlined,

    // Status / Workflow
    'circle': Icons.circle_outlined,
    'check_circle': Icons.check_circle_outlined,
    'task_alt': Icons.task_alt,
    'done_all': Icons.done_all,
    'pending': Icons.pending_outlined,
    'hourglass_empty': Icons.hourglass_empty,
    'schedule': Icons.schedule_outlined,
    'cancel': Icons.cancel_outlined,
    'block': Icons.block_outlined,
    'error': Icons.error_outlined,
    'error_outline': Icons.error_outline,
    'warning': Icons.warning_amber_outlined,
    'info': Icons.info_outlined,
    'add_circle': Icons.add_circle_outlined,
    'search': Icons.search_outlined,
    'autorenew': Icons.autorenew,
    'play_circle': Icons.play_circle_outline,
    'pause_circle': Icons.pause_circle_outline,
    'rate_review': Icons.rate_review_outlined,
    'thumb_up': Icons.thumb_up_outlined,
    'sync': Icons.sync_outlined,
    'publish': Icons.publish_outlined,
    'archive': Icons.archive_outlined,
    'rocket_launch': Icons.rocket_launch_outlined,
    'bolt': Icons.bolt_outlined,
    'science': Icons.science_outlined,
    'shopping_cart': Icons.shopping_cart_outlined,
    'storefront': Icons.storefront_outlined,
    'gavel': Icons.gavel_outlined,
    'school': Icons.school_outlined,
    'headset_mic': Icons.headset_mic_outlined,
    'bug_report': Icons.bug_report_outlined,
    'code': Icons.code_outlined,
    'calendar_month': Icons.calendar_month_outlined,
    'map': Icons.map_outlined,
    'lightbulb': Icons.lightbulb_outline,
  };

  /// Resolve um nome de ícone para um [IconData] const.
  /// Retorna [defaultIcon] se o nome não for encontrado ou for null.
  static IconData resolve(String? iconName) {
    if (iconName == null || iconName.isEmpty) return defaultIcon;
    return _icons[iconName] ?? defaultIcon;
  }

  /// `true` quando o nome existe no registry — usado para não gravar em banco
  /// um ícone que a UI não conseguiria desenhar.
  static bool isRegistered(String? iconName) =>
      iconName != null && _icons.containsKey(iconName);

  /// Retorna a lista de ícones disponíveis para seleção na criação de canais.
  /// Cada entrada tem 'name' (key) e 'icon' (IconData).
  static List<MapEntry<String, IconData>> get availableIcons =>
      _icons.entries.toList();

  /// Ícones sugeridos para a identidade de um workspace (sem os aliases
  /// duplicados, para o seletor não repetir o mesmo desenho).
  static const List<String> workspaceIconNames = [
    'workspaces_rounded',
    'dashboard',
    'payments_outlined',
    'account_balance',
    'credit_card',
    'receipt_long_outlined',
    'receipt_outlined',
    'fact_check',
    'description',
    'assignment',
    'checklist',
    'task',
    'build_circle_outlined',
    'engineering',
    'construction',
    'handyman',
    'two_wheeler',
    'directions_car_outlined',
    'local_shipping',
    'garage',
    'campaign_outlined',
    'announcement',
    'forum',
    'chat',
    'people_outline',
    'group',
    'badge',
    'support_agent',
    'headset_mic',
    'inventory',
    'category',
    'storefront',
    'shopping_cart',
    'gavel',
    'school',
    'science',
    'code',
    'bug_report',
    'calendar_month',
    'map',
    'lightbulb',
    'rocket_launch',
    'bolt',
    'star',
    'flag',
    'verified',
  ];

  /// Ícones sugeridos para etapas do Kanban.
  static const List<String> stageIconNames = [
    'circle',
    'add_circle',
    'search',
    'autorenew',
    'sync',
    'play_circle',
    'pause_circle',
    'hourglass_empty',
    'schedule',
    'pending',
    'rate_review',
    'thumb_up',
    'checklist',
    'task_alt',
    'check_circle',
    'done_all',
    'verified',
    'publish',
    'archive',
    'error_outline',
    'warning',
    'block',
    'cancel',
    'flag',
  ];
}
