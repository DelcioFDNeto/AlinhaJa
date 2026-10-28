import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/features/chat/models/chat_member_model.dart';

final chatMembersProvider =
    FutureProvider.family<List<ChatMemberModel>, String>((ref, chatId) async {
  final membersRes = await supabase
      .from('chat_members')
      .select('user_id, admingroup, muted')
      .eq('chat_id', chatId);

  if ((membersRes as List).isEmpty) return [];

  final List<Map<String, dynamic>> membersList =
      (membersRes as List).map((m) => m as Map<String, dynamic>).toList();

  final memberIds = membersList.map((m) => m['user_id'] as String).toList();
  if (memberIds.isEmpty) return [];

  final usersRes = await supabase
      .from('users')
      .select(
          'id, full_name, avatar_url, department_id, job_position_id, role_level, is_online, last_seen_at, branches(id, name), departments(name), job_positions(name)')
      .inFilter('id', memberIds);

  final List<Map<String, dynamic>> usersList =
      (usersRes as List).map((u) => u as Map<String, dynamic>).toList();

  final userModels = usersList.map((u) => UserModel.fromJson(u)).toList();

  final List<ChatMemberModel> members = [];
  for (final user in userModels) {
    final memberData = membersList.firstWhere(
      (m) => m['user_id'] == user.id,
      orElse: () => {'admingroup': false},
    );
    members.add(ChatMemberModel(
      user: user,
      isAdminGroup: memberData['admingroup'] as bool? ?? false,
      muted: memberData['muted'] as bool? ?? false,
    ));
  }

  // Ordena colocação de admins no topo, depois alfabética
  members.sort((a, b) {
    if (a.isAdmin && !b.isAdmin) return -1;
    if (!a.isAdmin && b.isAdmin) return 1;
    return a.user.fullName.compareTo(b.user.fullName);
  });

  return members;
});
