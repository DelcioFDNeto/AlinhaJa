import 'package:flutter/material.dart';

/// Pílula compacta de estatística usada nos cabeçalhos do módulo RH
/// (headcount de funcionários, funil do banco de talentos).
///
/// Componente único para manter consistência visual entre as telas do
/// produto — importante num CRM/SaaS multi-tenant onde a identidade da
/// interface precisa ser previsível em todos os módulos.
class HrStatPill extends StatelessWidget {
  const HrStatPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15, color: c)),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.outline)),
            ],
          ),
        ],
      ),
    );
  }
}
