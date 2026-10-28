import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show Importance;

import 'package:alinha_ja/core/modules/module_descriptor.dart';

// Telas dos módulos (painel direito / rota).
import 'package:alinha_ja/features/hr/ui/talent_bank_screen.dart';
import 'package:alinha_ja/features/hr/ui/employees_screen.dart';
import 'package:alinha_ja/features/hr/ui/onboarding_templates_screen.dart';
import 'package:alinha_ja/features/hr/ui/hr_alerts_screen.dart';
import 'package:alinha_ja/features/hr/ui/hr_documentos_screen.dart';
import 'package:alinha_ja/features/hr/ui/absences/hr_absences_screen.dart';
import 'package:alinha_ja/features/hr/ui/settings/automations_screen.dart';
import 'package:alinha_ja/features/hr/ui/hr_holerites_screen.dart';
import 'package:alinha_ja/features/hr/ui/hr_ponto_screen.dart';
import 'package:alinha_ja/features/hr/ui/hr_beneficios_screen.dart';
import 'package:alinha_ja/features/hr/ui/hr_desempenho_screen.dart';
import 'package:alinha_ja/features/finance/ui/finance_dashboard_screen.dart';
import 'package:alinha_ja/features/finance/ui/finance_payable_screen.dart';
import 'package:alinha_ja/features/finance/ui/finance_receivable_screen.dart';
import 'package:alinha_ja/features/finance/ui/finance_cashflow_screen.dart';
import 'package:alinha_ja/features/support/ui/helpdesk_admin_screen.dart';
import 'package:alinha_ja/features/support/ui/help_center_screen.dart';
import 'package:alinha_ja/features/admin/ui/admin_dashboard_screen.dart';

/// Catálogo central de módulos do AlinhaJá.
///
/// Fonte única de verdade: sidebar, drawer mobile, painel desktop, rotas
/// (com guarda), canais/tópicos FCM e toggles de notificação derivam desta
/// lista. Cada `id` **deve** casar com a chave `module` do RBAC no banco.
///
/// Os módulos de comunicação usam [ModuleActivation.leftTab] (alternam a aba
/// do painel esquerdo). Os módulos de departamento usam
/// [ModuleActivation.rightPanel] (abrem tela no painel direito / rota).
const List<ModuleDescriptor> kModuleRegistry = <ModuleDescriptor>[
  // ─────────────────────────── COMUNICAÇÃO ───────────────────────────
  ModuleDescriptor(
    id: 'comunicacao_canais',
    section: ModuleSection.comunicacao,
    title: 'Canais',
    icon: Icons.campaign_outlined,
    activeIcon: Icons.campaign_rounded,
    badgeColor: null, // usa cor primária no consumidor
    route: '/chats?tab=canais',
    activation: ModuleActivation.leftTab,
    leftTabIndex: 0,
    screenBuilder: _unsupportedLeftTab,
    tourHint:
        'Avisos e comunicados oficiais da empresa. Explore, siga e acompanhe '
        'os canais do seu interesse.',
  ),
  ModuleDescriptor(
    id: 'comunicacao_conversas',
    section: ModuleSection.comunicacao,
    title: 'Conversas',
    icon: Icons.chat_bubble_outline_rounded,
    activeIcon: Icons.chat_bubble_rounded,
    badgeColor: Color(0xFFE65100),
    route: '/chats?tab=conversas',
    activation: ModuleActivation.leftTab,
    leftTabIndex: 1,
    screenBuilder: _unsupportedLeftTab,
    tourHint:
        'Mensagens diretas e grupos com seus colegas. É o canal do dia a dia '
        '— rápido e privado.',
  ),
  ModuleDescriptor(
    id: 'comunicacao_chamadas',
    section: ModuleSection.comunicacao,
    title: 'Chamadas',
    icon: Icons.videocam_outlined,
    activeIcon: Icons.videocam_rounded,
    route: '/chats?tab=chamadas',
    activation: ModuleActivation.leftTab,
    leftTabIndex: 2,
    screenBuilder: _unsupportedLeftTab,
    tourHint:
        'Faça e receba chamadas de voz e vídeo, individuais ou em grupo, sem '
        'sair do app.',
  ),

  // ─────────────────────────── RECURSOS HUMANOS ───────────────────────────
  ModuleDescriptor(
    id: 'rh_banco_talentos',
    section: ModuleSection.rh,
    title: 'Banco de Talentos',
    icon: Icons.badge_outlined,
    activeIcon: Icons.badge_rounded,
    route: '/rh',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _talentBank,
    tourHint:
        'Cadastre vagas, receba candidaturas e gerencie seu banco de talentos '
        'e processos seletivos.',
  ),
  ModuleDescriptor(
    id: 'rh_funcionarios',
    section: ModuleSection.rh,
    title: 'Funcionários',
    icon: Icons.contact_page_outlined,
    activeIcon: Icons.contact_page_rounded,
    route: '/rh/funcionarios',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _employees,
    tourHint:
        'Ficha completa de cada colaborador: dados, documentos, histórico e '
        'situação cadastral.',
  ),
  ModuleDescriptor(
    id: 'rh_documentos',
    section: ModuleSection.rh,
    title: 'Documentos',
    icon: Icons.folder_shared_outlined,
    activeIcon: Icons.folder_shared_rounded,
    route: '/rh/documentos',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _hrDocs,
    tourHint:
        'Solicite, envie e acompanhe a aprovação de documentos entre o RH e os '
        'colaboradores.',
    notification: ModuleNotificationSpec(
      androidChannelId: 'mod_rh_documentos',
      channelName: 'Documentos RH',
      description: 'Solicitações e aprovações de documentos',
      topic: 'mod_rh_documentos',
      importance: Importance.defaultImportance,
    ),
  ),
  ModuleDescriptor(
    id: 'rh_ausencias',
    section: ModuleSection.rh,
    title: 'Ausências e Férias',
    icon: Icons.event_busy_outlined,
    activeIcon: Icons.event_busy_rounded,
    route: '/rh/ausencias',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _hrAbsences,
    tourHint:
        'Aprove solicitações de folgas, atestados e férias enviadas pelos funcionários.',
  ),
  ModuleDescriptor(
    id: 'rh_onboarding',
    section: ModuleSection.rh,
    title: 'Onboarding',
    icon: Icons.assignment_outlined,
    activeIcon: Icons.assignment_rounded,
    route: '/rh/onboarding-templates',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _onboardingTemplates,
    tourHint:
        'Modelos de integração com etapas e checklists para receber novos '
        'colaboradores com segurança.',
    notification: ModuleNotificationSpec(
      androidChannelId: 'mod_rh_onboarding',
      channelName: 'Onboarding',
      description: 'Etapas e checklists de integração',
      topic: 'mod_rh_onboarding',
      importance: Importance.defaultImportance,
    ),
  ),
  ModuleDescriptor(
    id: 'rh_alertas',
    section: ModuleSection.rh,
    title: 'Alertas RH',
    icon: Icons.warning_amber_rounded,
    activeIcon: Icons.warning_rounded,
    route: '/rh/alertas',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _hrAlerts,
    tourHint:
        'Vencimentos, pendências e prazos do RH reunidos para você não perder '
        'nenhum.',
    notification: ModuleNotificationSpec(
      androidChannelId: 'mod_rh_alertas',
      channelName: 'Alertas RH',
      description: 'Vencimentos e pendências do RH',
      topic: 'mod_rh_alertas',
      importance: Importance.high,
    ),
  ),
  ModuleDescriptor(
    id: 'rh_holerites',
    section: ModuleSection.rh,
    title: 'Holerites',
    icon: Icons.request_quote_outlined,
    activeIcon: Icons.request_quote_rounded,
    route: '/rh/holerites',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _hrHolerites,
    tourHint: 'Emita, faça upload e gerencie os recibos de pagamento dos colaboradores.',
  ),
  ModuleDescriptor(
    id: 'rh_ponto',
    section: ModuleSection.rh,
    title: 'Controle de Ponto',
    icon: Icons.access_time_outlined,
    activeIcon: Icons.access_time_filled_rounded,
    route: '/rh/ponto',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _hrPonto,
    tourHint: 'Acompanhe espelhos de ponto, horas extras e aprovações de batidas.',
  ),
  ModuleDescriptor(
    id: 'rh_beneficios',
    section: ModuleSection.rh,
    title: 'Benefícios',
    icon: Icons.card_giftcard_outlined,
    activeIcon: Icons.card_giftcard_rounded,
    route: '/rh/beneficios',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _hrBeneficios,
    tourHint: 'Gerencie plano de saúde, VR, VA e controle descontos.',
  ),
  ModuleDescriptor(
    id: 'rh_desempenho',
    section: ModuleSection.rh,
    title: 'Desempenho',
    icon: Icons.insights_outlined,
    activeIcon: Icons.insights_rounded,
    route: '/rh/desempenho',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _hrDesempenho,
    tourHint: 'Ciclos de avaliação, metas e feedbacks 1:1.',
  ),

  // ─────────────────────────── FINANCEIRO ───────────────────────────
  ModuleDescriptor(
    id: 'fin_dashboard',
    section: ModuleSection.financeiro,
    title: 'Visão Geral (Financeiro)',
    icon: Icons.account_balance_wallet_outlined,
    activeIcon: Icons.account_balance_wallet_rounded,
    route: '/finance/dashboard',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _finDashboard,
    tourHint: 'Acompanhe o saldo, contas a pagar e a receber em tempo real.',
  ),
  ModuleDescriptor(
    id: 'fin_pagar',
    section: ModuleSection.financeiro,
    title: 'Contas a Pagar',
    icon: Icons.money_off_outlined,
    activeIcon: Icons.money_off_rounded,
    route: '/finance/payable',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _finPayable,
    tourHint: 'Gerencie despesas, boletos e pagamentos agendados.',
  ),
  ModuleDescriptor(
    id: 'fin_receber',
    section: ModuleSection.financeiro,
    title: 'Contas a Receber',
    icon: Icons.attach_money_outlined,
    activeIcon: Icons.attach_money_rounded,
    route: '/finance/receivable',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _finReceivable,
    tourHint: 'Acompanhe faturamentos, cobranças e inadimplência.',
  ),
  ModuleDescriptor(
    id: 'fin_movimentacoes',
    section: ModuleSection.financeiro,
    title: 'Fluxo de Caixa',
    icon: Icons.sync_alt_outlined,
    activeIcon: Icons.sync_alt_rounded,
    route: '/finance/cashflow',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _finCashflow,
    tourHint: 'Extrato bancário, movimentações e conciliação.',
  ),

  // ─────────────────────────── HELPDESK ───────────────────────────
  // Dois itens de navegação sobre a MESMA permissão/licença `helpdesk`:
  // • Central de Ajuda (`helpdesk:view`)  — abrir/acompanhar chamados + FAQ.
  // • Helpdesk TI      (`helpdesk:manage`) — fila de atendimento (resolver).
  ModuleDescriptor(
    id: 'helpdesk_central',
    permissionKey: 'helpdesk',
    section: ModuleSection.helpdesk,
    title: 'Central de Ajuda',
    icon: Icons.help_outline,
    activeIcon: Icons.help,
    route: '/support/help',
    activation: ModuleActivation.rightPanel,
    // Item de "consumo" do módulo: só visível (não gerenciável).
    manageAction: null,
    screenBuilder: _helpCenter,
    tourHint:
        'Abra chamados para o TI e acompanhe o andamento, além de consultar a '
        'base de perguntas frequentes.',
  ),
  ModuleDescriptor(
    id: 'helpdesk',
    section: ModuleSection.helpdesk,
    title: 'Helpdesk TI',
    icon: Icons.support_agent_outlined,
    activeIcon: Icons.support_agent_rounded,
    route: '/support/admin',
    activation: ModuleActivation.rightPanel,
    // Só quem pode RESOLVER (helpdesk:manage) vê o painel de atendimento.
    viewAction: 'manage',
    screenBuilder: _helpdeskAdmin,
    tourHint:
        'Fila de atendimento do suporte: receba, priorize e resolva os '
        'chamados internos da equipe.',
    notification: ModuleNotificationSpec(
      androidChannelId: 'mod_helpdesk',
      channelName: 'Helpdesk TI',
      description: 'Novos tickets e respostas do suporte',
      topic: 'mod_helpdesk',
      importance: Importance.high,
    ),
  ),

  ModuleDescriptor(
    id: 'admin_panel',
    section: ModuleSection.admin,
    title: 'Painel Admin',
    icon: Icons.admin_panel_settings_outlined,
    activeIcon: Icons.admin_panel_settings_rounded,
    route: '/admin',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _adminDashboard,
    tourHint:
        'Gestão da empresa: usuários, permissões, moderação e relatórios de '
        'uso da plataforma.',
  ),
  ModuleDescriptor(
    id: 'rh_automacoes',
    section: ModuleSection.admin,
    title: 'Comunicação e Automações',
    icon: Icons.mark_email_read_outlined,
    activeIcon: Icons.mark_email_read_rounded,
    route: '/rh/automacoes',
    activation: ModuleActivation.rightPanel,
    screenBuilder: _hrAutomations,
    tourHint:
        'Gerencie templates de e-mail, automações de recrutamento e o servidor SMTP da empresa.',
  ),
];

// ── Builders (funções top-level para permitir descriptors `const`) ──

Widget _unsupportedLeftTab(BuildContext context) => const SizedBox.shrink();
Widget _talentBank(BuildContext context) => const TalentBankScreen();
Widget _employees(BuildContext context) => const EmployeesScreen();
Widget _onboardingTemplates(BuildContext c) => const OnboardingTemplatesScreen();
Widget _hrAlerts(BuildContext context) => const HrAlertsScreen();
Widget _hrAbsences(BuildContext context) => const HrAbsencesScreen();
Widget _hrAutomations(BuildContext context) => const AutomationsScreen();
Widget _hrHolerites(BuildContext context) => const HrHoleritesScreen();
Widget _hrPonto(BuildContext context) => const HrPontoScreen();
Widget _hrBeneficios(BuildContext context) => const HrBeneficiosScreen();
Widget _hrDesempenho(BuildContext context) => const HrDesempenhoScreen();
Widget _finDashboard(BuildContext context) => const FinanceDashboardScreen();
Widget _finPayable(BuildContext context) => const FinancePayableScreen();
Widget _finReceivable(BuildContext context) => const FinanceReceivableScreen();
Widget _finCashflow(BuildContext context) => const FinanceCashflowScreen();
Widget _hrDocs(BuildContext context) => const HrDocumentosScreen();
Widget _helpdeskAdmin(BuildContext context) => const HelpdeskAdminScreen();
Widget _helpCenter(BuildContext context) => const HelpCenterScreen();
Widget _adminDashboard(BuildContext context) => const AdminDashboardScreen();

// ── Helpers de consulta ──

/// Retorna o módulo pelo [id], ou `null` se não existir.
ModuleDescriptor? moduleById(String id) {
  for (final m in kModuleRegistry) {
    if (m.id == id) return m;
  }
  return null;
}

/// Retorna todos os módulos de uma [section], na ordem de declaração.
List<ModuleDescriptor> modulesInSection(ModuleSection section) =>
    kModuleRegistry.where((m) => m.section == section).toList(growable: false);

/// Módulos que declaram especificação de notificação FCM (canal + tópico).
List<ModuleDescriptor> get modulesWithNotification =>
    kModuleRegistry.where((m) => m.notification != null).toList(growable: false);

/// Módulos ativados via painel direito do Desktop (departamentos/admin).
List<ModuleDescriptor> get rightPanelModules => kModuleRegistry
    .where((m) => m.activation == ModuleActivation.rightPanel)
    .toList(growable: false);

/// Módulos do menu "Módulos" do header mobile, na ordem do registro: os de
/// painel direito, exceto Helpdesk (que tem atalho próprio no header).
/// Fonte única para o menu e para o tour guiado não divergirem.
List<ModuleDescriptor> mobileMenuModules(List<ModuleDescriptor> accessible) =>
    accessible
        .where((m) =>
            m.activation == ModuleActivation.rightPanel &&
            m.section != ModuleSection.helpdesk)
        .toList(growable: false);

/// Rótulo da seção para agrupar módulos em menus (inclusive as seções que a
/// sidebar mostra sem cabeçalho).
String moduleSectionLabel(ModuleSection section) =>
    section.title ??
    switch (section) {
      ModuleSection.helpdesk => 'SUPORTE',
      ModuleSection.admin => 'ADMINISTRAÇÃO',
      _ => 'SISTEMA',
    };

/// Módulos licenciáveis por empresa (contratáveis) — exclui o baseline
/// (Comunicação/Admin). É o universo que o dono da plataforma libera por
/// tenant em `organizations.settings.modules`.
///
/// Deduplica por [ModuleDescriptor.accessKey]: quando vários itens de navegação
/// compartilham a mesma licença (ex.: `helpdesk_central` + `helpdesk`), o
/// Console exibe **um** toggle. Preferimos o descriptor canônico (aquele cujo
/// `id == accessKey`) para rotular a entitlement.
List<ModuleDescriptor> get licensableModules {
  final byKey = <String, ModuleDescriptor>{};
  for (final m in kModuleRegistry) {
    if (!m.isLicensable) continue;
    final existing = byKey[m.accessKey];
    if (existing == null || (m.id == m.accessKey && existing.id != existing.accessKey)) {
      byKey[m.accessKey] = m;
    }
  }
  return byKey.values.toList(growable: false);
}

/// IDs (accessKeys) licenciáveis. Usado como bundle padrão ("todos ligados")
/// ao cadastrar uma empresa nova e como universo de entitlement do Console.
List<String> get licensableModuleIds =>
    licensableModules.map((m) => m.accessKey).toList(growable: false);
