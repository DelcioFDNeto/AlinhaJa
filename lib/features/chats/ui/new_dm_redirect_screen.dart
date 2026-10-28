import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/core/constants.dart';

class NewDmRedirectScreen extends StatefulWidget {
  final String targetUserId;
  final UserModel? targetUser;

  const NewDmRedirectScreen({
    super.key,
    required this.targetUserId,
    this.targetUser,
  });

  @override
  State<NewDmRedirectScreen> createState() => _NewDmRedirectScreenState();
}

class _NewDmRedirectScreenState extends State<NewDmRedirectScreen> {
  @override
  void initState() {
    super.initState();
    _createDm();
  }

  Future<void> _createDm() async {
    try {
      final response = await supabase.rpc(
        'create_direct_chat',
        params: {'other_user_id': widget.targetUserId},
      );
      final chatId = response as String;
      if (mounted) {
        context.pushReplacement('/chat/$chatId', extra: {
          'name': widget.targetUser?.fullName ?? 'Chat',
          'isGroup': false,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar conversa: $e'),
            backgroundColor: AppConstants.danger,
          ),
        );
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
