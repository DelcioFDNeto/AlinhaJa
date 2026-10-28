/// Classe centralizada de permissões do AlinhaJá.
///
/// Define todas as regras de acesso baseadas no [roleLevel] do usuário.
/// Substitui os checks hardcoded espalhados pelo código.
///
/// Hierarquia: super_admin > admin > manager > member
class AppPermissions {
  AppPermissions._();

  // ── Definição de Níveis ─────────────────────────────────────
  static const String superAdmin = 'super_admin';
  static const String admin = 'admin';
  static const String manager = 'manager';
  static const String member = 'member';

  /// Labels amigáveis para exibição na UI.
  static const Map<String, String> roleLabels = {
    superAdmin: 'Super Admin',
    admin: 'Administrador',
    manager: 'Gestor',
    member: 'Colaborador',
  };

  /// Ícones por nível para badges na UI.
  static const Map<String, String> roleIcons = {
    superAdmin: '🛡️',
    admin: '⚙️',
    manager: '📋',
    member: '👤',
  };

  /// Todos os níveis que podem ser atribuídos (para dropdown no admin).
  /// Ordenados do mais alto para o mais baixo.
  static const List<String> assignableRoles = [
    superAdmin,
    admin,
    manager,
    member,
  ];

  // ── Helpers de Hierarquia ───────────────────────────────────

  /// Retorna o peso numérico do nível (maior = mais privilegiado).
  static int _weight(String? role) {
    switch (role) {
      case superAdmin:
        return 4;
      case admin:
        return 3;
      case manager:
        return 2;
      case member:
        return 1;
      default:
        return 0;
    }
  }

  /// Verifica se o nível é pelo menos [requiredRole].
  static bool isAtLeast(String? userRole, String requiredRole) {
    return _weight(userRole) >= _weight(requiredRole);
  }

  // ── Permissões Específicas ──────────────────────────────────

  /// Pode acessar o Painel Administrativo.
  static bool canAccessAdmin(String? role) => isAtLeast(role, admin);

  /// Pode aprovar cadastros de novos usuários.
  static bool canApproveUsers(String? role) => isAtLeast(role, admin);

  /// Pode editar o perfil de outros usuários.
  static bool canEditOtherUsers(String? role) => isAtLeast(role, admin);

  /// Pode criar canais (workspaces).
  static bool canCreateChannel(String? role) => isAtLeast(role, admin);

  /// Pode gerenciar membros de canais.
  static bool canManageChannelMembers(String? role) => isAtLeast(role, admin);

  /// Pode acessar o painel Helpdesk admin.
  static bool canAccessHelpdesk(String? role) => isAtLeast(role, admin);

  /// Pode moderar conteúdo.
  static bool canModerate(String? role) => isAtLeast(role, admin);

  /// Pode ver relatórios de uso.
  static bool canViewReports(String? role) => isAtLeast(role, admin);

  /// Pode arquivar/desativar usuários.
  static bool canToggleUserStatus(String? role) => isAtLeast(role, admin);

  /// Pode atribuir o nível super_admin a outro usuário.
  static bool canAssignSuperAdmin(String? role) => role == superAdmin;

  /// Pode excluir canais permanentemente.
  static bool canDeleteChannel(String? role) => isAtLeast(role, admin);

  /// Pode gerenciar o rastreamento de localização.
  static bool canManageLocationTracking(String? role) => isAtLeast(role, admin);

  /// Pode criar grupos de chat (DMs com mais de 2 pessoas).
  static bool canCreateGroupChat(String? role) => isAtLeast(role, manager);

  /// Pode criar salas de reunião em grupos.
  static bool canCreateMeeting(String? role) => isAtLeast(role, manager);

  // ── Permissões de Workflow ──────────────────────────────────

  /// Pode operar (assumir, finalizar, mover, alterar) cards do workflow.
  /// Membros só podem fazer isso se o card foi atribuído a eles.
  static bool canOperateWorkflowCard(String? role) => isAtLeast(role, admin);

  /// Pode editar campos, excluir anexos ou cancelar a solicitação inteira (além do próprio solicitante).
  static bool canManageWorkflow(String? role) => isAtLeast(role, admin);

  // Módulo RH: não há mais checagem por nível aqui. O acesso vem do perfil
  // RBAC de cada módulo (rbacCanProvider), a mesma regra do banco
  // (fn_rh_pode).

  /// Retorna o label amigável do nível.
  static String getLabel(String? role) => roleLabels[role] ?? 'Colaborador';
}
