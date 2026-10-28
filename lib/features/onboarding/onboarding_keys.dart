import 'package:flutter/widgets.dart';
import 'package:alinha_ja/core/ui/components/crm_sidebar.dart';

/// Chaves globais dos alvos do tour guiado da home.
///
/// Ficam em nível de biblioteca (estáticas) para permanecerem **estáveis entre
/// rebuilds** do MainScaffold — o `tutorial_coach_mark` localiza cada alvo pelo
/// `currentContext` da chave, então elas não podem ser recriadas a cada build.
///
/// Os passos do tour saem do RBAC (`accessibleModulesProvider`), não do que
/// está montado: o `tutorial_coach_mark` encerra o tour inteiro ao encontrar
/// um alvo sem `currentContext`, então cada passo prepara a tela (troca de
/// aba, seção aberta) antes de ser medido — ver `showHomeTour`.
class HomeTourKeys {
  HomeTourKeys._();

  static final tabCanais = GlobalKey(debugLabel: 'tour_tab_canais');
  static final tabConversas = GlobalKey(debugLabel: 'tour_tab_conversas');
  static final tabChamadas = GlobalKey(debugLabel: 'tour_tab_chamadas');
  static final search = GlobalKey(debugLabel: 'tour_search');
  static final modulesMenu = GlobalKey(debugLabel: 'tour_modules_menu');
  static final avatarMenu = GlobalKey(debugLabel: 'tour_avatar_menu');
  static final crmSidebar = GlobalKey<CrmSidebarState>(debugLabel: 'tour_crm_sidebar');

  /// Uma chave por módulo (id → key) para o walkthrough do desktop, onde a
  /// CrmSidebar mostra cada módulo em sua própria linha. Criadas sob demanda e
  /// estáveis entre rebuilds.
  static final Map<String, GlobalKey> _moduleKeys = {};
  static GlobalKey moduleKey(String moduleId) =>
      _moduleKeys.putIfAbsent(
          moduleId, () => GlobalKey(debugLabel: 'tour_mod_$moduleId'));

  /// Atalhos de módulo no header do mobile (ex.: Helpdesk). Espaço de chaves
  /// separado de [moduleKey]: no desktop o mesmo módulo também está na
  /// sidebar, e uma GlobalKey não pode estar montada em dois lugares.
  static final Map<String, GlobalKey> _headerKeys = {};
  static GlobalKey headerModuleKey(String moduleId) =>
      _headerKeys.putIfAbsent(
          moduleId, () => GlobalKey(debugLabel: 'tour_header_$moduleId'));
}
