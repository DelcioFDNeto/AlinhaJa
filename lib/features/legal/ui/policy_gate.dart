import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/features/legal/providers/legal_provider.dart';
import 'package:alinha_ja/features/legal/ui/policy_acceptance_screen.dart';

/// Portão de aceite: envolve a área autenticada e substitui o app pela tela de
/// aceite enquanto houver documento pendente.
///
/// Por que envolver a shell em vez de usar `redirect` do GoRouter: a checagem é
/// assíncrona e depende do servidor. Um redirect assíncrono rodaria a cada
/// navegação e transformaria uma falha de rede em tela de login. Aqui a
/// verificação acontece uma vez por sessão, com cache do Riverpod.
///
/// **Falha de rede libera o acesso de propósito.** Barrar quem já aceitou por
/// causa de uma consulta que não respondeu seria pior do que atrasar o aceite
/// de quem ainda não aceitou — e o servidor continua registrando o que foi
/// aceito, então nada se perde.
class PolicyGate extends ConsumerWidget {
  const PolicyGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingPoliciesProvider);

    return pending.maybeWhen(
      data: (docs) => docs.isEmpty
          ? child
          : PolicyAcceptanceScreen(pending: docs),
      orElse: () => child,
    );
  }
}
