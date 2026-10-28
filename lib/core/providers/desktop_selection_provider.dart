import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DesktopViewType {
  chat,
  workflow,
  profile,
  settings,
  support,
  starred,
  contacts,

  /// Tela de um módulo do registro (RH, Helpdesk, Admin, ...). O módulo
  /// específico é identificado por [DesktopSelection.moduleId]. Substitui os
  /// antigos valores por-módulo (hrTalentos, adminDashboard, supportAdmin, ...)
  /// para tornar a navegação dirigida pelo registro de módulos.
  module,
  platformConsole,
}

/// Modelo de seleção para o painel direito do layout Desktop.
class DesktopSelection {
  final DesktopViewType type;
  final String? id;
  final String? name;
  final bool isGroup;

  /// Id do módulo do registro quando [type] == [DesktopViewType.module].
  final String? moduleId;

  const DesktopSelection({
    required this.type,
    this.id,
    this.name,
    this.isGroup = false,
    this.moduleId,
  });

  /// Atalho para selecionar a tela de um módulo do registro no painel direito.
  factory DesktopSelection.module(String moduleId) {
    return DesktopSelection(type: DesktopViewType.module, moduleId: moduleId);
  }

  bool get isChannel => type == DesktopViewType.workflow;
  bool get isChat => type == DesktopViewType.chat;

  factory DesktopSelection.chat(String id, String name,
      {bool isGroup = false}) {
    return DesktopSelection(
        type: DesktopViewType.chat, id: id, name: name, isGroup: isGroup);
  }

  factory DesktopSelection.channel(String id, String name) {
    return DesktopSelection(type: DesktopViewType.workflow, id: id, name: name);
  }
}

/// Provider global para controlar qual chat/canal ou tela está selecionada no Desktop.
/// No Mobile esse provider é ignorado — a navegação usa GoRouter normalmente.
final desktopSelectionProvider =
    StateProvider<DesktopSelection?>((ref) => null);

/// Modo Foco do layout Desktop: esconde a sidebar de módulos e a lista de
/// conversas, deixando apenas o painel direito.
///
/// É um provider (e não estado local do layout) porque as telas do painel
/// direito precisam sair do modo foco — ex.: o botão de voltar da conversa,
/// que no Desktop não tem rota para desempilhar.
final desktopFocusModeProvider = StateProvider<bool>((ref) => false);
