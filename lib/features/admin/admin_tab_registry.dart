import 'package:flutter/material.dart';

import 'package:alinha_ja/features/admin/ui/tabs/user_management_tab.dart';
import 'package:alinha_ja/features/admin/ui/tabs/user_create_tab.dart';
import 'package:alinha_ja/features/admin/ui/tabs/audit_management_tab.dart';
import 'package:alinha_ja/features/admin/ui/moderation_screen.dart';
import 'package:alinha_ja/features/admin/ui/usage_reports_screen.dart';
import 'package:alinha_ja/features/admin/ui/tabs/it_support_management_tab.dart';
import 'package:alinha_ja/features/location/ui/location_dashboard_screen.dart';
import 'package:alinha_ja/features/admin/ui/tabs/backup_management_tab.dart';
import 'package:alinha_ja/features/admin/ui/tabs/ai_keys_management_tab.dart';
import 'package:alinha_ja/features/admin/ui/tabs/legal_profile_tab.dart';
import 'package:alinha_ja/features/admin/ui/tabs/identidade_visual_tab.dart';
import 'package:alinha_ja/core/rbac/ui/access_management_screen.dart';

/// Descreve uma aba do Dashboard Administrativo.
///
/// Cada aba é gated individualmente por uma permissão RBAC ([module]/[action]).
/// Se o usuário logado não tiver a permissão, a aba nem é renderizada.
///
/// Fonte única de verdade das abas do painel: a barra de abas e o corpo do
/// [AdminDashboardScreen] derivam desta lista. Adicionar uma aba nova = 1
/// [AdminTabDescriptor] aqui + a permissão RBAC correspondente no banco
/// (ver a migration `..._rbac_admin_tabs.sql`).
@immutable
class AdminTabDescriptor {
  /// Chave `module` do RBAC exigida para ver a aba. **Deve** casar com uma
  /// linha de `rbac_permissions.module` no banco.
  final String module;

  /// Ação RBAC exigida para ver a aba (padrão `view`).
  final String action;

  /// Ícone exibido no item da aba.
  final IconData icon;

  /// Título exibido no item da aba.
  final String title;

  /// Construtor do conteúdo da aba (widgets sem Scaffold, embutíveis).
  final Widget Function() builder;

  const AdminTabDescriptor({
    required this.module,
    required this.icon,
    required this.title,
    required this.builder,
    this.action = 'view',
  });
}

/// Catálogo das abas do Dashboard Administrativo, na ordem de exibição.
///
/// `helpdesk` e `location` reusam módulos RBAC já existentes; as demais abas
/// usam chaves `admin_*` semeadas na migration de alinhamento das abas.
const List<AdminTabDescriptor> kAdminTabRegistry = <AdminTabDescriptor>[
  AdminTabDescriptor(
    module: 'admin_users',
    icon: Icons.people_alt_outlined,
    title: 'Gestão de Usuários',
    builder: _userManagement,
  ),
  AdminTabDescriptor(
    module: 'admin_cadastro',
    icon: Icons.person_add_outlined,
    title: 'Novo Cadastro',
    builder: _userCreate,
  ),
  AdminTabDescriptor(
    module: 'admin_acessos',
    icon: Icons.lock_person_outlined,
    title: 'Acessos',
    builder: _accessManagement,
  ),
  AdminTabDescriptor(
    module: 'admin_auditoria',
    icon: Icons.policy_outlined,
    title: 'Auditoria',
    builder: _auditManagement,
  ),
  AdminTabDescriptor(
    module: 'admin_moderacao',
    icon: Icons.shield_outlined,
    title: 'Moderação',
    builder: _moderation,
  ),
  AdminTabDescriptor(
    module: 'admin_relatorios',
    icon: Icons.analytics_outlined,
    title: 'Relatórios',
    builder: _usageReports,
  ),
  AdminTabDescriptor(
    module: 'helpdesk',
    icon: Icons.headset_mic_rounded,
    title: 'Helpdesk (TI)',
    builder: _itSupport,
  ),
  AdminTabDescriptor(
    module: 'admin_ai_keys',
    icon: Icons.vpn_key,
    title: 'Chave de IA',
    builder: _aiKeys,
  ),
  AdminTabDescriptor(
    module: 'location',
    icon: Icons.location_on_rounded,
    title: 'Localização',
    builder: _location,
  ),
  AdminTabDescriptor(
    module: 'admin_backup',
    icon: Icons.save_alt_rounded,
    title: 'Backup',
    builder: _backup,
  ),
  AdminTabDescriptor(
    module: 'admin_legal',
    icon: Icons.gavel_rounded,
    title: 'Dados Legais',
    builder: _legalProfile,
  ),
  AdminTabDescriptor(
    module: 'admin_identidade',
    icon: Icons.palette_outlined,
    title: 'Identidade Visual',
    builder: _identidadeVisual,
  ),
];

// ── Builders (funções top-level para permitir descriptors `const`) ──

Widget _userManagement() => const UserManagementTab();
Widget _userCreate() => const UserCreateTab();
Widget _accessManagement() => const AccessManagementScreen();
Widget _auditManagement() => const AuditManagementTab();
Widget _moderation() => const ModerationScreen();
Widget _usageReports() => const UsageReportsScreen();
Widget _itSupport() => const ItSupportManagementTab();
Widget _aiKeys() => const AiKeysManagementTab();
Widget _location() => const LocationDashboardScreen();
Widget _backup() => const BackupManagementTab();
Widget _legalProfile() => const LegalProfileTab();
Widget _identidadeVisual() => const IdentidadeVisualTab();
