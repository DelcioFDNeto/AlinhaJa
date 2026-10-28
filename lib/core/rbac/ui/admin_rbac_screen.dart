import 'package:flutter/material.dart';

import 'access_management_screen.dart';

/// Wrapper de compatibilidade. O Gerenciamento de Acessos agora vive
/// como aba dentro do Painel Admin (AdminDashboardScreen). Esta tela
/// apenas embrulha [AccessManagementScreen] num Scaffold para rotas/
/// referências antigas que ainda a abram isoladamente.
class AdminRbacScreen extends StatelessWidget {
  const AdminRbacScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AccessManagementScreen(),
    );
  }
}
