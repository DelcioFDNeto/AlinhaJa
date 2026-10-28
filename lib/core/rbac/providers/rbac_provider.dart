import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rbac_permission.dart';
import '../services/rbac_repository.dart';
import '../../../features/auth/providers/auth_provider.dart';

/// Provedor que mantém a lista de permissões ativas do usuário logado
final myPermissionsProvider = FutureProvider<List<RbacPermission>>((ref) async {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return [];

  final repo = ref.read(rbacRepositoryProvider);
  return repo.getMyPermissions();
});

/// Extensão para checar permissões facilmente
extension RbacPermissionChecker on List<RbacPermission> {
  /// `manage` implica `view` — a mesma regra do banco (`fn_rh_pode`): quem
  /// gere um módulo não pode ficar sem enxergá-lo.
  bool hasPermission(String module, String action) {
    return any((p) =>
        p.module == module &&
        (p.action == action || (action == 'view' && p.action == 'manage')));
  }
}

/// Permissão RBAC do usuário logado para um (módulo, ação).
///
/// Enquanto as permissões carregam o resultado é `false`: melhor esconder a
/// ação por um instante do que oferecer algo que o banco vai recusar.
final rbacCanProvider =
    Provider.family<bool, ({String module, String action})>((ref, key) {
  final permissions = ref.watch(myPermissionsProvider).valueOrNull ?? const [];
  return permissions.hasPermission(key.module, key.action);
});

/// Módulo RBAC dos anúncios oficiais.
///
/// Publicar comunicado deixou de ser sinônimo de administrar o canal: com uma
/// permissão própria, RH e Comunicação anunciam sem gerir membros, e um admin
/// de canal pode não ter esse poder.
class AnnouncementPermissions {
  AnnouncementPermissions._();

  static const String module = 'comunicacao_anuncios';
  static const String create = 'create';
  static const String manage = 'manage';
  static const String viewStats = 'view_stats';
}

/// Se o usuário logado pode publicar anúncio oficial.
///
/// Enquanto as permissões carregam o resultado é `false` — melhor esconder a
/// ação por um instante do que oferecer algo que o banco vai recusar.
final canPublishAnnouncementProvider = Provider<bool>((ref) {
  final permissions = ref.watch(myPermissionsProvider).valueOrNull ?? const [];
  return permissions.hasPermission(
    AnnouncementPermissions.module,
    AnnouncementPermissions.create,
  );
});

/// Se o usuário logado pode ver o painel de confirmações de qualquer anúncio.
final canViewAnnouncementStatsProvider = Provider<bool>((ref) {
  final permissions = ref.watch(myPermissionsProvider).valueOrNull ?? const [];
  return permissions.hasPermission(
        AnnouncementPermissions.module,
        AnnouncementPermissions.viewStats,
      ) ||
      permissions.hasPermission(
        AnnouncementPermissions.module,
        AnnouncementPermissions.manage,
      );
});
