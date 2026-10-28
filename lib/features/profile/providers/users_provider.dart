import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';

/// Provider que busca todos os usuários do sistema, exceto o usuário logado atual.
/// Utilizado para a lista de contatos / novo bate-papo.
final allUsersProvider = FutureProvider<List<UserModel>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  // Se não tem usuário logado, retorna lista vazia
  if (currentUser == null) return [];

  // Busca todos os usuários ordenados pelo nome
  // E faz join com a tabela branches para pegar o nome da filial
  final response = await supabase
      .from('users')
      .select(
          'id, full_name, avatar_url, email, is_online, last_seen_at, branch_id, role_level, department_id, job_position_id, is_active, branches(id, name), departments(name), job_positions(name)')
      .order('full_name', ascending: true);

  final List<UserModel> allUsers = (response as List)
      .map((e) => UserModel.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  // Aplica as regras de visibilidade
  final myRole = currentUser.roleLevel;

  final filteredUsers = allUsers.where((u) {
    // Nunca mostra a si mesmo
    if (u.id == currentUser.id) return false;

    // Ocultar o bot de sistema da lista de contatos para evitar chats diretos sem resposta
    if (u.id == '00000000-0000-0000-0000-000000000001') return false;

    // Se o usuário está inativo/arquivado, oculta de todo mundo,
    // EXCETO para a TI e Diretores (para que possam reativar)
    if (!u.isActive) {
      if (AppPermissions.canToggleUserStatus(myRole)) return true;
      return false;
    }

    // Rede Aberta: Qualquer pessoa vê qualquer pessoa e todas as filiais e cargos
    // (A única restrição é para usuários inativos, removendo restrição de TI/Admin da rede geral)
    return true;
  }).toList();

  return filteredUsers;
});
