import 'package:flutter/material.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/features/admin/ui/tabs/it_support_management_tab.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';

class HelpdeskAdminScreen extends ConsumerStatefulWidget {
  const HelpdeskAdminScreen({super.key});

  @override
  ConsumerState<HelpdeskAdminScreen> createState() =>
      _HelpdeskAdminScreenState();
}

class _HelpdeskAdminScreenState extends ConsumerState<HelpdeskAdminScreen> {
  @override
  void initState() {
    super.initState();
    _checkSecurity();
  }

  void _checkSecurity() {
    final user = ref.read(currentUserProvider).value;
    if (user == null || !AppPermissions.canAccessHelpdesk(user.roleLevel)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Acesso Negado: Área restrita.'),
              backgroundColor: AppConstants.danger,
            ),
          );
          context.pop();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão de Helpdesk (TI)'),
      ),
      body: const ResponsiveWidthContainer(
        child: ItSupportManagementTab(),
      ),
    );
  }
}
