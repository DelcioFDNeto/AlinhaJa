import 'package:flutter/material.dart';

import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/core/status_tokens.dart';

/// Selo de status compartilhado pelas listas do RH (funcionários,
/// candidatos). A cor vem dos tokens do tema via [StatusRole]; o texto é a
/// label já centralizada em cada model. Unifica os antigos `_StatusBadge`
/// duplicados de employees_screen e talent_bank_screen.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.role});

  final String label;
  final StatusRole role;

  @override
  Widget build(BuildContext context) {
    final color = context.statusTokens.color(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
