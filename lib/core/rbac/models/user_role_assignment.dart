library;

/// Um usuário da organização com os ids de perfil (RBAC) atribuídos a ele.
/// Usado no painel de Gerenciamento de Acessos → aba "Usuários".
class UserRoleAssignment {
  final String userId;
  final String fullName;
  final String? avatarUrl;

  /// Nível de sistema herdado (super_admin/admin/manager/member).
  final String roleLevel;
  final String? jobTitle;

  /// Ids dos perfis dinâmicos (rbac_roles) atribuídos ao usuário.
  final List<String> roleIds;

  const UserRoleAssignment({
    required this.userId,
    required this.fullName,
    this.avatarUrl,
    required this.roleLevel,
    this.jobTitle,
    this.roleIds = const [],
  });

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
