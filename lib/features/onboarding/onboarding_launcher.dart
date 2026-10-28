import 'package:flutter/material.dart';

import 'package:alinha_ja/core/supabase_client.dart';
import 'services/onboarding_service.dart';
import 'ui/welcome_intro_screen.dart';
import 'ui/home_tour.dart';

const _service = OnboardingService();

/// Executa o fluxo de introdução: carrossel de boas-vindas → (se o usuário
/// aceitar) tour guiado com coach marks sobre a interface atual.
///
/// Ponto único usado pelo disparo automático no 1º login e pelo "Rever
/// tutorial" (mobile e desktop). Passe [reset] = `true` para reexibir mesmo
/// que o usuário já tenha visto.
///
/// O [context] deve pertencer à tela home (MainScaffold/Sidebar) para que os
/// alvos do tour estejam montados; caso contrário só o carrossel é exibido.
Future<void> launchOnboarding(BuildContext context, {bool reset = false}) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;

  if (reset) {
    await _service.reset(userId);
  } else if (await _service.hasSeen(userId)) {
    return;
  }
  if (!context.mounted) return;

  final startTour = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const WelcomeIntroScreen(),
    ),
  );

  await _service.markSeen(userId);
  if (!context.mounted) return;

  if (startTour == true) {
    // Aguarda a transição de saída do carrossel + layout dos alvos.
    await Future.delayed(const Duration(milliseconds: 450));
    if (context.mounted) await showHomeTour(context);
  }
}
