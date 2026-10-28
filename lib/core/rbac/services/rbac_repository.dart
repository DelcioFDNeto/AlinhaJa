import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rbac_role.dart';
import '../models/rbac_permission.dart';
import '../models/user_role_assignment.dart';

final rbacRepositoryProvider = Provider<RbacRepository>((ref) {
  return RbacRepository(Supabase.instance.client);
});

class RbacRepository {
  final SupabaseClient _supabase;

  RbacRepository(this._supabase);

  /// Carrega todas as permissões do sistema
  Future<List<RbacPermission>> getSystemPermissions() async {
    final response = await _supabase.from('rbac_permissions').select().order('module');
    return response.map((e) => RbacPermission.fromJson(e)).toList();
  }

  /// Carrega os perfis (roles) da organização atual
  Future<List<RbacRole>> getOrganizationRoles() async {
    final response = await _supabase.from('rbac_roles').select().order('name');
    return response.map((e) => RbacRole.fromJson(e)).toList();
  }

  /// Carrega os IDs de permissão de um determinado perfil
  Future<List<String>> getRolePermissions(String roleId) async {
    final response = await _supabase
        .from('rbac_role_permissions')
        .select('permission_id')
        .eq('role_id', roleId);
    
    return response.map((e) => e['permission_id'] as String).toList();
  }

  /// Atualiza as permissões de um perfil numa única transação no banco.
  ///
  /// Antes eram duas requisições (apaga tudo, depois insere): se a segunda
  /// falhasse, o perfil ficava sem permissão nenhuma.
  Future<void> updateRolePermissions(String roleId, List<String> permissionIds) async {
    await _supabase.rpc('rbac_set_role_permissions', params: {
      'p_role_id': roleId,
      'p_permission_ids': permissionIds,
    });
  }

  /// Garante os 4 perfis-padrão da organização (usado no estado vazio).
  Future<void> setupDefaultRoles() async {
    await _supabase.rpc('rbac_setup_default_roles');
  }

  /// Cria um novo perfil na organização atual; retorna o id gerado.
  Future<String> createRole(String name, {String? description}) async {
    final id = await _supabase.rpc('rbac_create_role', params: {
      'p_name': name,
      'p_description': description,
    });
    return id as String;
  }

  /// Exclui um perfil (não-sistema) da organização atual.
  Future<void> deleteRole(String roleId) async {
    await _supabase.rpc('rbac_delete_role', params: {'p_role_id': roleId});
  }

  /// Usuários da organização com os ids de perfil (RBAC) atribuídos a cada um.
  Future<List<UserRoleAssignment>> getUsersWithRoles() async {
    final users = await _supabase
        .from('users')
        .select('id, full_name, avatar_url, role_level, job_positions(name)')
        .order('full_name');

    final links = await _supabase
        .from('rbac_user_roles')
        .select('user_id, role_id');

    final byUser = <String, List<String>>{};
    for (final l in links) {
      (byUser[l['user_id'] as String] ??= []).add(l['role_id'] as String);
    }

    return (users as List).map((u) {
      final job = u['job_positions'];
      return UserRoleAssignment(
        userId: u['id'] as String,
        fullName: (u['full_name'] as String?) ?? 'Sem nome',
        avatarUrl: u['avatar_url'] as String?,
        roleLevel: (u['role_level'] as String?) ?? 'member',
        jobTitle: job is Map ? job['name'] as String? : null,
        roleIds: byUser[u['id']] ?? const [],
      );
    }).toList();
  }

  /// Substitui os perfis atribuídos a um usuário.
  Future<void> setUserRoles(String userId, List<String> roleIds) async {
    await _supabase.rpc('rbac_set_user_roles', params: {
      'p_user_id': userId,
      'p_role_ids': roleIds,
    });
  }

  /// Carrega as permissões ativas (consolidadas) do usuário logado.
  ///
  /// Espelha o banco (`fn_rh_pode`): super_admin tem tudo; admin tem tudo
  /// FORA do RH — não fica trancado fora do Painel Admin, onde corrige o
  /// RBAC — mas o RH (salários, documentos, holerites) vem do perfil, como
  /// para qualquer usuário.
  Future<List<RbacPermission>> getMyPermissions() async {
    final userId = _supabase.auth.currentUser!.id;

    final me = await _supabase
        .from('users')
        .select('role_level')
        .eq('id', userId)
        .maybeSingle();
    final level = me?['role_level'] as String?;
    if (level == 'super_admin') return getSystemPermissions();

    final assigned = await _assignedPermissions(userId);
    if (level != 'admin') return assigned;
    return adminEffectivePermissions(await getSystemPermissions(), assigned);
  }

  /// Permissões vindas dos perfis atribuídos ao usuário.
  Future<List<RbacPermission>> _assignedPermissions(String userId) async {
    // Busca os perfis do usuário
    final userRoles = await _supabase
        .from('rbac_user_roles')
        .select('role_id')
        .eq('user_id', userId);

    if (userRoles.isEmpty) return [];

    final roleIds = userRoles.map((r) => r['role_id']).toList();

    // Busca as permissões ligadas a esses perfis
    final rolePermissions = await _supabase
        .from('rbac_role_permissions')
        .select('permission_id')
        .inFilter('role_id', roleIds);

    if (rolePermissions.isEmpty) return [];

    final permissionIds = rolePermissions.map((rp) => rp['permission_id']).toSet().toList();

    // Busca os detalhes das permissões
    final permissions = await _supabase
        .from('rbac_permissions')
        .select()
        .inFilter('id', permissionIds);

    return permissions.map((e) => RbacPermission.fromJson(e)).toList();
  }
}

/// Módulo do RH: só o perfil RBAC libera, nem para admin.
bool isHrModule(String module) => module.startsWith('rh_');

/// Permissões efetivas de um admin: todas as do sistema fora do RH, mais as
/// do RH que os perfis dele concedem.
List<RbacPermission> adminEffectivePermissions(
    List<RbacPermission> all, List<RbacPermission> assigned) {
  final byId = <String, RbacPermission>{
    for (final p in all.where((p) => !isHrModule(p.module))) p.id: p,
  };
  for (final p in assigned) {
    byId[p.id] = p;
  }
  return byId.values.toList();
}
