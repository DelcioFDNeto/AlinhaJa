/// Model do perfil de colaborador.
/// Espelha a tabela `users` do Supabase.
class UserModel {
  final String id;
  final String fullName;
  final String? email;
  final String? avatarUrl;
  final String? phone;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final String? branchId;
  final String? branchName;
  final String roleLevel;
  final String? departmentId;
  final String? departmentName;
  final String? jobPositionId;
  final String? jobPositionName;
  final bool isActive;
  final String? hrRole;
  final String? cpf;
  final DateTime? dataNascimento;
  final String? sexo;

  /// Organização (tenant) natal do usuário. Fonte do isolamento multi-tenant;
  /// no banco espelha `users.organization_id`.
  final String? organizationId;

  /// Empresa em ATUAÇÃO do dono da plataforma (`users.acting_organization_id`).
  /// Só é usada quando [isPlatformOwner]; permite alternar o contexto de
  /// empresa com o mesmo login. `null` = atuando na org natal.
  final String? actingOrganizationId;

  /// Dono da aplicação (eixo de plataforma, ortogonal a [roleLevel]).
  /// Concede acesso ao Console de Plataforma e poderes cross-tenant.
  final bool isPlatformOwner;

  const UserModel({
    required this.id,
    required this.fullName,
    this.email,
    this.avatarUrl,
    this.phone,
    this.isOnline = false,
    this.lastSeenAt,
    this.branchId,
    this.branchName,
    this.roleLevel = 'member',
    this.departmentId,
    this.departmentName,
    this.jobPositionId,
    this.jobPositionName,
    this.isActive = true,
    this.hrRole,
    this.cpf,
    this.dataNascimento,
    this.sexo,
    this.organizationId,
    this.actingOrganizationId,
    this.isPlatformOwner = false,
  });

  /// Empresa cujos dados o usuário efetivamente enxerga: a em atuação (se o
  /// dono a definiu) ou a natal. Espelha o COALESCE do `fn_current_org()`.
  String? get effectiveOrganizationId => actingOrganizationId ?? organizationId;

  /// Verifica se o usuário está realmente online (Considerando o último pulso/heartbeat)
  bool get isActuallyOnline {
    if (!isOnline) return false;
    if (lastSeenAt == null) return false;
    return DateTime.now().toUtc().difference(lastSeenAt!).inMinutes <= 5;
  }

  /// Calcula a idade automaticamente com base na data de nascimento.
  int? get age {
    if (dataNascimento == null) return null;
    final now = DateTime.now();
    int years = now.year - dataNascimento!.year;
    if (now.month < dataNascimento!.month ||
        (now.month == dataNascimento!.month && now.day < dataNascimento!.day)) {
      years--;
    }
    return years;
  }

  /// Colunas de `public.users` legíveis por qualquer autenticado.
  ///
  /// `cpf`, `data_nascimento`, `sexo` e `phone` estão **fora** de
  /// propósito: o privilégio de coluna foi revogado no banco (migrations
  /// 20260803170000 e 20260903140000), então pedir `*` ou qualquer uma
  /// delas devolve 403.
  ///
  /// Para o próprio dado sensível use `get_my_sensitive_profile()`;
  /// para o de terceiros, `admin_list_users_pii()` (admin+, auditado).
  ///
  /// `acting_organization_id` entra aqui porque [fromJson] a lê para montar
  /// [effectiveOrganizationId] — sem ela o seletor de empresa do dono da
  /// plataforma volta sempre à org natal.
  static const String selectColumns =
      'id, full_name, email, avatar_url, is_online, last_seen_at, '
      'branch_id, role_level, department_id, job_position_id, is_active, '
      'hr_role, organization_id, acting_organization_id, is_platform_owner, '
      'created_at, updated_at';

  /// [selectColumns] com os relacionamentos que a UI costuma precisar.
  static const String selectWithOrg =
      '$selectColumns, branches(name), departments(name), job_positions(name)';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('Usuário com id nulo ignorado');
    }

    return UserModel(
      id: id,
      fullName: (json['full_name'] as String?) ?? 'Usuário',
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      phone: json['phone'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : (json['last_seen'] != null
              ? DateTime.parse(json['last_seen'] as String)
              : null),
      branchId: json['branch_id'] as String?,
      branchName:
          json['branches'] != null ? json['branches']['name'] as String? : null,
      roleLevel: json['role_level'] as String? ?? 'member',
      departmentId: json['department_id'] as String?,
      departmentName: json['departments'] != null
          ? (json['departments'] is Map
              ? json['departments']['name'] as String?
              : null)
          : null,
      jobPositionId: json['job_position_id'] as String?,
      jobPositionName: json['job_positions'] != null
          ? (json['job_positions'] is Map
              ? json['job_positions']['name'] as String?
              : null)
          : null,
      isActive: json['is_active'] as bool? ?? true,
      hrRole: json['hr_role'] as String?,
      cpf: json['cpf'] as String?,
      dataNascimento: json['data_nascimento'] != null
          ? DateTime.tryParse(json['data_nascimento'] as String)
          : null,
      sexo: json['sexo'] as String?,
      organizationId: json['organization_id'] as String?,
      actingOrganizationId: json['acting_organization_id'] as String?,
      isPlatformOwner: json['is_platform_owner'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'avatar_url': avatarUrl,
        'phone': phone,
        'is_online': isOnline,
        'last_seen': lastSeenAt?.toIso8601String(),
        'branch_id': branchId,
        'role_level': roleLevel,
        'department_id': departmentId,
        'job_position_id': jobPositionId,
        'is_active': isActive,
        'hr_role': hrRole,
        'cpf': cpf,
        'data_nascimento': dataNascimento?.toIso8601String().split('T').first,
        'sexo': sexo,
        'organization_id': organizationId,
        'acting_organization_id': actingOrganizationId,
        'is_platform_owner': isPlatformOwner,
      };

  String get initials => fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';

  /// Formata o CPF mascarado para exibição: ***.***.***-XX
  String get cpfMasked {
    if (cpf == null || cpf!.length < 11) return cpf ?? '';
    final digits = cpf!.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return cpf!;
    return '***.***.${digits.substring(6, 9)}-${digits.substring(9)}';
  }

  /// Formata a data de nascimento para exibição dd/MM/yyyy
  String get dataNascimentoFormatted {
    if (dataNascimento == null) return '';
    final d = dataNascimento!;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Label amigável do sexo
  String get sexoLabel {
    switch (sexo) {
      case 'M':
        return 'Masculino';
      case 'F':
        return 'Feminino';
      case 'O':
        return 'Outro';
      default:
        return 'Não informado';
    }
  }

  /// Label amigável do nível de acesso
  /// Hierarquia: super_admin > admin > manager > member
  String get displayRoleLevel {
    switch (roleLevel) {
      case 'super_admin':
        return 'TI - Super Admin'; // Exclusivo para TI ou dono do sistema
      case 'admin':
        return 'Diretoria'; // Admin para diretoria e gerentes
      case 'manager':
        return 'Gestor(a)'; // Manager para supervisores e gestores
      default:
        return 'Colaborador(a)'; // Member para colaboradores em geral
    }
  }

  /// Retorna o cargo, ou departamento, ou fallback para o nível de acesso
  String get displaySubtitle {
    if (jobPositionName != null && jobPositionName!.isNotEmpty) {
      return jobPositionName!;
    }
    if (departmentName != null && departmentName!.isNotEmpty) {
      return departmentName!;
    }
    return displayRoleLevel;
  }

  UserModel copyWith({
    String? fullName,
    String? email,
    bool? isOnline,
    String? avatarUrl,
    String? phone,
    String? branchId,
    String? branchName,
    String? roleLevel,
    String? departmentId,
    String? departmentName,
    String? jobPositionId,
    String? jobPositionName,
    bool? isActive,
    String? hrRole,
    String? cpf,
    DateTime? dataNascimento,
    String? sexo,
    String? organizationId,
    String? actingOrganizationId,
    bool? isPlatformOwner,
  }) =>
      UserModel(
        id: id,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        phone: phone ?? this.phone,
        isOnline: isOnline ?? this.isOnline,
        lastSeenAt: lastSeenAt,
        branchId: branchId ?? this.branchId,
        branchName: branchName ?? this.branchName,
        roleLevel: roleLevel ?? this.roleLevel,
        departmentId: departmentId ?? this.departmentId,
        departmentName: departmentName ?? this.departmentName,
        jobPositionId: jobPositionId ?? this.jobPositionId,
        jobPositionName: jobPositionName ?? this.jobPositionName,
        isActive: isActive ?? this.isActive,
        hrRole: hrRole ?? this.hrRole,
        cpf: cpf ?? this.cpf,
        dataNascimento: dataNascimento ?? this.dataNascimento,
        sexo: sexo ?? this.sexo,
        organizationId: organizationId ?? this.organizationId,
        actingOrganizationId: actingOrganizationId ?? this.actingOrganizationId,
        isPlatformOwner: isPlatformOwner ?? this.isPlatformOwner,
      );
}
