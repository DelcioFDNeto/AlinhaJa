import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show Importance;

/// Seções lógicas em que os módulos são agrupados na navegação.
///
/// A ordem aqui define a ordem de renderização na sidebar/menus.
enum ModuleSection {
  comunicacao,
  rh,
  financeiro,
  operacoes,
  helpdesk,
  admin,
  sistema,
}

extension ModuleSectionInfo on ModuleSection {
  /// Se a seção é **baseline** do produto (sempre incluída, não licenciável).
  ///
  /// Comunicação (chat/canais/chamadas) e Admin (painel de gestão da própria
  /// empresa) acompanham qualquer contratação. As demais seções — RH, Helpdesk
  /// e futuros módulos de departamento — são licenciáveis: o dono da plataforma
  /// libera por empresa em `organizations.settings.modules`.
  bool get isBaseline =>
      this == ModuleSection.comunicacao || this == ModuleSection.admin;

  /// Título exibido acima do grupo na sidebar (null = sem cabeçalho,
  /// usado para os itens fixos do rodapé como Helpdesk/Admin).
  String? get title {
    switch (this) {
      case ModuleSection.comunicacao:
        return 'COMUNICAÇÃO';
      case ModuleSection.rh:
        return 'RECURSOS HUMANOS';
      case ModuleSection.financeiro:
        return 'FINANCEIRO';
      case ModuleSection.operacoes:
        return 'OPERAÇÕES';
      case ModuleSection.helpdesk:
      case ModuleSection.admin:
      case ModuleSection.sistema:
        return null;
    }
  }
}

/// Como o módulo é ativado na navegação.
///
/// - [leftTab]: alterna uma aba do painel esquerdo (Canais/Conversas/Chamadas).
/// - [rightPanel]: abre uma tela no painel direito do Desktop (ou empurra a
///   rota no Mobile).
enum ModuleActivation { leftTab, rightPanel }

/// Especificação de notificação FCM de um módulo: canal Android + tópico.
///
/// Presente apenas em módulos que recebem broadcast por departamento
/// (ex.: alertas do RH, novos tickets do Helpdesk). Módulos de comunicação
/// (DMs/grupos/chamadas) usam canais intrínsecos roteados por `chat_type` e
/// não declaram spec aqui.
class ModuleNotificationSpec {
  /// ID do canal de notificação no Android (ex.: `mod_rh_alertas`).
  final String androidChannelId;

  /// Nome amigável do canal (aparece nas configurações do sistema Android).
  final String channelName;

  /// Descrição do canal.
  final String description;

  /// Importância do canal Android.
  final Importance importance;

  /// Tópico FCM para broadcast do departamento (ex.: `mod_rh_alertas`).
  final String topic;

  /// Se o app deve inscrever automaticamente no tópico ao ter acesso ao módulo.
  final bool subscribeByDefault;

  const ModuleNotificationSpec({
    required this.androidChannelId,
    required this.channelName,
    required this.description,
    required this.topic,
    this.importance = Importance.high,
    this.subscribeByDefault = true,
  });
}

/// Descreve um módulo do AlinhaJá — a fonte única de verdade da qual derivam
/// a sidebar, o drawer mobile, o painel direito do desktop, as rotas (com
/// guarda de permissão), os canais/ tópicos FCM e os toggles de notificação.
///
/// Adicionar um novo departamento = adicionar um [ModuleDescriptor] em
/// `module_registry.dart` + a linha de permissão RBAC correspondente no banco.
@immutable
class ModuleDescriptor {
  /// Identificador estável do módulo **na navegação** (sidebar, DesktopSelection,
  /// guarda de rota). Único no registro. Por padrão também é a chave usada no
  /// RBAC/entitlement — a menos que [permissionKey] seja informado.
  final String id;

  /// Chave de RBAC/entitlement do módulo (padrão: [id]). Permite que **vários**
  /// itens de navegação (ex.: `helpdesk_central` para abrir chamados e
  /// `helpdesk` para resolvê-los) compartilhem a **mesma** permissão e a mesma
  /// licença de tenant, diferenciando-se apenas pela ação exigida ([viewAction]).
  final String? permissionKey;

  /// Seção de agrupamento na navegação.
  final ModuleSection section;

  /// Título exibido no item de navegação.
  final String title;

  /// Ícone quando inativo.
  final IconData icon;

  /// Ícone quando ativo/selecionado.
  final IconData activeIcon;

  /// Cor opcional do badge (contador). `null` = transparente.
  final Color? badgeColor;

  /// Rota deep-link primária do módulo (ex.: `/rh/alertas`).
  final String route;

  /// Ação RBAC exigida para *ver* o módulo (padrão `view`).
  final String viewAction;

  /// Ação RBAC de gestão, quando aplicável (padrão `manage`, ou `null`).
  final String? manageAction;

  /// Forma de ativação na navegação.
  final ModuleActivation activation;

  /// Índice da aba do painel esquerdo, quando [activation] == leftTab.
  final int? leftTabIndex;

  /// Construtor da tela cheia (Mobile e rota deep-link).
  final WidgetBuilder screenBuilder;

  /// Construtor da tela no painel direito do Desktop.
  /// Se `null`, usa [screenBuilder].
  final WidgetBuilder? desktopBuilder;

  /// Especificação de notificação FCM (canal + tópico), quando o módulo
  /// recebe broadcast por departamento.
  final ModuleNotificationSpec? notification;

  /// Frase curta explicando o módulo, exibida no tour guiado de introdução
  /// (ver `features/onboarding`). `null` = usa um texto genérico.
  final String? tourHint;

  const ModuleDescriptor({
    required this.id,
    required this.section,
    required this.title,
    required this.icon,
    required this.activeIcon,
    required this.route,
    required this.activation,
    required this.screenBuilder,
    this.permissionKey,
    this.badgeColor,
    this.viewAction = 'view',
    this.manageAction = 'manage',
    this.leftTabIndex,
    this.desktopBuilder,
    this.notification,
    this.tourHint,
  });

  /// Chave efetiva de RBAC/entitlement (permissão + licença de tenant).
  /// Cai em [id] quando [permissionKey] não é informado.
  String get accessKey => permissionKey ?? id;

  /// Construtor efetivo para o painel direito do Desktop.
  WidgetBuilder get effectiveDesktopBuilder => desktopBuilder ?? screenBuilder;

  /// Se o módulo é licenciável por empresa (contratável). Módulos de seção
  /// baseline (Comunicação/Admin) não são gated por entitlement de tenant.
  bool get isLicensable => !section.isBaseline;
}
