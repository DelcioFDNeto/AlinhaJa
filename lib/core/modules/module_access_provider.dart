import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/core/modules/module_descriptor.dart';
import 'package:alinha_ja/core/modules/module_registry.dart';
import 'package:alinha_ja/core/rbac/models/rbac_permission.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/core/models/org_settings.dart';

/// Conjunto de ids de módulos **licenciáveis** habilitados para a empresa
/// (tenant) do usuário logado. Espelha `organizations.settings.modules`,
/// gravado pelo dono da plataforma no Console.
///
/// Módulos baseline (Comunicação/Admin) não dependem deste conjunto. O gate é
/// **estrito**: um módulo licenciável ausente daqui é tratado como não
/// contratado (invisível). Enquanto o usuário/org não resolvem, emite `null`
/// e o consumidor mantém o comportamento permissivo de cold-start.
final enabledModuleIdsProvider = FutureProvider<Set<String>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  // Org EFETIVA: reflete a empresa em atuação do dono da plataforma, casando
  // com o `fn_current_org()` do servidor (senão os módulos seriam os da natal).
  final orgId = user?.effectiveOrganizationId;
  if (orgId == null) return const <String>{};

  final row = await supabase
      .from('organizations')
      .select('settings')
      .eq('id', orgId)
      .maybeSingle();

  // Chave ausente/nula → nenhum módulo licenciável liberado (gate estrito).
  return OrgSettings.fromJson(row?['settings']).modulos;
});

/// Regra de visibilidade de um módulo dado o RBAC e o entitlement do tenant.
///
/// Módulos de [ModuleSection.comunicacao] são baseline do produto (chat,
/// canais, chamadas) e ficam **sempre** visíveis. Módulos licenciáveis (RH,
/// Helpdesk, futuros deptos) exigem que a empresa os tenha contratado
/// ([enabledIds]) **e** que o usuário tenha a permissão `view` no RBAC. Os
/// demais baseline (Admin) exigem apenas o RBAC.
bool _isModuleVisible(
    ModuleDescriptor m, List<RbacPermission> perms, Set<String> enabledIds) {
  if (m.section == ModuleSection.comunicacao) return true;
  // Licença e RBAC são checados pela chave de acesso (accessKey), permitindo
  // que múltiplos itens (ex.: Central de Ajuda + Helpdesk TI) compartilhem a
  // mesma licença `helpdesk`, diferenciados apenas pela ação exigida.
  if (m.isLicensable && !enabledIds.contains(m.accessKey)) return false;
  return perms.hasPermission(m.accessKey, m.viewAction);
}

/// Lista de módulos que o usuário logado pode ver, na ordem do registro.
///
/// Como efeito colateral, mantém [Globals.accessibleModuleIds] sincronizado
/// para que as guardas de rota do GoRouter (síncronas) possam consultá-lo.
final accessibleModulesProvider = Provider<List<ModuleDescriptor>>((ref) {
  final perms = ref.watch(myPermissionsProvider).valueOrNull;
  final enabled = ref.watch(enabledModuleIdsProvider).valueOrNull;

  // Enquanto RBAC ou entitlement do tenant não resolvem, exponha só o baseline
  // de comunicação e deixe o cache síncrono como `null` (guardas tratam como
  // permissivo, evitando flicker de bloqueio no cold start).
  if (perms == null || enabled == null) {
    Globals.accessibleModuleIds = null;
    return kModuleRegistry
        .where((m) => m.section == ModuleSection.comunicacao)
        .toList(growable: false);
  }

  final visible = kModuleRegistry
      .where((m) => _isModuleVisible(m, perms, enabled))
      .toList(growable: false);

  Globals.accessibleModuleIds = visible.map((m) => m.id).toSet();
  return visible;
});

/// Conjunto de ids de módulos acessíveis (conveniência para consumidores).
final accessibleModuleIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(accessibleModulesProvider).map((m) => m.id).toSet();
});

/// Indica se o usuário pode *gerenciar* (ação `manage`) um dado módulo.
final canManageModuleProvider = Provider.family<bool, String>((ref, moduleId) {
  final module = moduleById(moduleId);
  if (module == null || module.manageAction == null) return false;
  final perms = ref.watch(myPermissionsProvider).valueOrNull;
  if (perms == null) return false;
  return perms.hasPermission(moduleId, module.manageAction!);
});

/// Verificação síncrona usada pelas guardas de rota do GoRouter.
///
/// Retorna `true` (permissivo) quando o cache ainda não foi populado (cold
/// start), evitando redirecionar o usuário logado antes do RBAC resolver.
/// A UI revalida assim que [accessibleModulesProvider] emite.
bool canAccessModuleRouteSync(String moduleId) {
  final ids = Globals.accessibleModuleIds;
  if (ids == null) return true; // ainda carregando — não bloquear
  return ids.contains(moduleId);
}
