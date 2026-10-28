import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/router.dart';

void main() {
  testWidgets('GoRouter possui a rota de thread em canal (/channel/:id/thread/:messageId)', (WidgetTester tester) async {
    final shellRoutes = goRouter.configuration.routes.whereType<ShellRoute>().first.routes;
    final threadRoute = shellRoutes.firstWhere(
      (r) => r is GoRoute && r.path == '/channel/:id/thread/:messageId',
    ) as GoRoute;

    expect(threadRoute, isNotNull);
    expect(threadRoute.path, equals('/channel/:id/thread/:messageId'));
  });

  testWidgets('GoRouter possui as rotas de self-service (/meu-onboarding e /meu-desempenho)', (WidgetTester tester) async {
    final shellRoutes = goRouter.configuration.routes.whereType<ShellRoute>().first.routes;

    final onboardingRoute = shellRoutes.firstWhere(
      (r) => r is GoRoute && r.path == '/meu-onboarding',
    ) as GoRoute;

    final desempenhoRoute = shellRoutes.firstWhere(
      (r) => r is GoRoute && r.path == '/meu-desempenho',
    ) as GoRoute;

    expect(onboardingRoute, isNotNull);
    expect(desempenhoRoute, isNotNull);
  });

  testWidgets('GoRouter possui a rota de troca obrigatória de senha (/force-change-password)', (WidgetTester tester) async {
    final topRoutes = goRouter.configuration.routes.whereType<GoRoute>();
    final forceChangeRoute = topRoutes.firstWhere(
      (r) => r.path == '/force-change-password',
    );

    expect(forceChangeRoute, isNotNull);
    expect(forceChangeRoute.path, equals('/force-change-password'));
  });
}
