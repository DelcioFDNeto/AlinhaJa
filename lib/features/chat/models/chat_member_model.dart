import 'package:alinha_ja/features/profile/models/user_model.dart';

class ChatMemberModel {
  final UserModel user;
  final bool isAdminGroup;
  final bool muted;

  const ChatMemberModel({
    required this.user,
    required this.isAdminGroup,
    this.muted = false,
  });

  bool get isAdmin => isAdminGroup;
}
