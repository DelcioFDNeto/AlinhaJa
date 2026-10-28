import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:alinha_ja/core/modules/module_access_provider.dart';
import 'package:alinha_ja/core/modules/module_registry.dart';

/// Guarda de rota para um módulo: nega acesso (redireciona para `/chats`)
/// quando o usuário não tem a permissão RBAC do módulo.
///
/// Usa [canAccessModuleRouteSync], que é permissivo enquanto o cache de
/// permissões ainda não foi populado (cold start), evitando bloquear o
/// usuário logado antes do RBAC resolver.
GoRouterRedirect moduleGuard(String moduleId) {
  return (BuildContext context, GoRouterState state) {
    return canAccessModuleRouteSync(moduleId) ? null : '/chats';
  };
}

/// Gera as rotas primárias dos módulos de painel direito (RH, Helpdesk,
/// Admin) a partir do registro, cada uma com guarda de permissão.
///
/// Sub-rotas parametrizadas (ex.: `/rh/candidato/:id`) permanecem declaradas
/// manualmente no router, mas devem reutilizar [moduleGuard] com o mesmo id.
List<GoRoute> buildModuleRoutes() {
  return rightPanelModules.map((m) {
    // Usa apenas o path (sem query string) como caminho da rota.
    final path = Uri.parse(m.route).path;
    return GoRoute(
      path: path,
      redirect: moduleGuard(m.id),
      builder: (context, state) => m.screenBuilder(context),
    );
  }).toList(growable: false);
}
