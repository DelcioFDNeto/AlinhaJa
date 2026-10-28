import 'package:shared_preferences/shared_preferences.dart';

/// Controla se o usuário já viu a introdução + tour guiado do app.
///
/// A marca é **por dispositivo** (SharedPreferences), chaveada pelo id do
/// usuário: `onboarding_seen_<userId>`. Assim, cada aparelho mostra o tour da
/// sua própria interface uma vez, e trocar de conta no mesmo device não
/// reaproveita a marca de outro usuário.
class OnboardingService {
  const OnboardingService();

  static String _key(String userId) => 'onboarding_seen_$userId';

  /// `true` se o usuário já concluiu (ou pulou) a introdução neste dispositivo.
  Future<bool> hasSeen(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  /// Marca a introdução como vista para não reabrir automaticamente.
  Future<void> markSeen(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }

  /// Limpa a marca — usado para "Rever tutorial" a partir do menu.
  Future<void> reset(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }
}
