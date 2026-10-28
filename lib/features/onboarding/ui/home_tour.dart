import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import 'package:alinha_ja/core/modules/module_access_provider.dart';
import 'package:alinha_ja/core/modules/module_descriptor.dart';
import 'package:alinha_ja/core/modules/module_registry.dart';
import 'package:alinha_ja/core/providers/chat_tab_provider.dart';
import 'package:alinha_ja/core/providers/desktop_selection_provider.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import '../onboarding_keys.dart';

/// Descreve um passo do tour antes de virar um [TargetFocus].
class _Step {
  final String id;
  final GlobalKey key;
  final IconData icon;
  final String title;
  final String description;
  final ShapeLightFocus shape;

  /// Linha curta acima do título (ex.: onde o módulo fica no mobile).
  final String? caption;

  /// Executada logo antes de o passo ser destacado: abre a view REAL do
  /// módulo e/ou monta o alvo (ex.: troca para a aba que tem a busca).
  final VoidCallback? onActivate;

  /// `true` para passos cujo alvo vive na lista rolável da CrmSidebar. O tour
  /// rola esse alvo para dentro da tela antes de destacá-lo, garantindo que o
  /// recorte e o balão apareçam mesmo em telas baixas.
  final bool inSidebar;

  const _Step({
    required this.id,
    required this.key,
    required this.icon,
    required this.title,
    required this.description,
    this.shape = ShapeLightFocus.RRect,
    this.caption,
    this.onActivate,
    this.inSidebar = false,
  });
}

/// Inicia o tour guiado da home destacando os elementos reais da interface.
///
/// Funciona no mobile (barra inferior + header) e no desktop (CrmSidebar):
/// ambos os layouts compartilham as [HomeTourKeys]. Os passos saem dos
/// módulos que o RBAC libera ([accessibleModulesProvider]) — um por módulo.
///
/// Cada passo monta o próprio alvo antes de ser medido ([_Step.onActivate]):
/// o `tutorial_coach_mark` encerra o tour INTEIRO quando um alvo não está
/// montado, e era assim que ele parava na metade (ex.: a busca some na aba
/// Chamadas; os módulos de uma seção recolhida da sidebar não existem).
Future<void> showHomeTour(BuildContext context, {VoidCallback? onFinish}) async {
  final container = ProviderScope.containerOf(context, listen: false);

  // Enquanto RBAC e licenças carregam, o provider só expõe Comunicação.
  await _awaitModuleAccess(container);
  if (!context.mounted) return;

  // No desktop o CrmSidebar está montado: expandimos com todas as seções
  // abertas e posicionamos os balões à DIREITA dos itens.
  final sidebarState = HomeTourKeys.crmSidebar.currentState;
  final isDesktop = sidebarState != null;
  final wasExpanded = sidebarState?.isExpanded ?? false;

  void finish() {
    sidebarState?.endTour(collapse: !wasExpanded);
    onFinish?.call();
  }

  if (sidebarState != null) {
    sidebarState.beginTour();
    // Animação de largura da sidebar (250ms) antes de medir os alvos.
    await Future.delayed(const Duration(milliseconds: 300));
    if (!context.mounted) return;
    // O guia assume o scroll: começa no topo e desce passo a passo.
    await sidebarState.scrollToTop();
    if (!context.mounted) return;
  }

  final modules = container.read(accessibleModulesProvider);
  final steps = isDesktop
      ? _desktopSteps(container, modules)
      : _mobileSteps(container, modules);

  // Passo sem preparo precisa do alvo montado agora; os demais o montam em
  // `beforeFocus`, logo antes da medição.
  final present = [
    for (final s in steps)
      if (s.onActivate != null || s.key.currentContext != null) s,
  ];
  if (present.isEmpty) {
    finish();
    return;
  }

  final screen = MediaQuery.of(context).size;
  final targets = [for (final s in present) _toTarget(s, screen, isDesktop)];
  final stepById = <String, _Step>{for (final s in present) s.id: s};

  // Antes de destacar cada passo o `tutorial_coach_mark` mede a posição do
  // alvo: ativamos a view do passo, esperamos o frame que a remonta e, na
  // sidebar, rolamos o item para dentro da tela (telas baixas).
  Future<void> beforeFocus(TargetFocus t) async {
    final id = t.identify;
    final s = id is String ? stepById[id] : null;
    if (s == null) return;
    s.onActivate?.call();
    await WidgetsBinding.instance.endOfFrame;
    if (s.inSidebar) await sidebarState?.ensureKeyVisible(s.key);
  }

  final cs = Theme.of(context).colorScheme;

  TutorialCoachMark(
    targets: targets,
    // Sombra mais leve para o usuário enxergar a view do módulo ativado.
    colorShadow: const Color(0xFF0B1A2B),
    opacityShadow: 0.78,
    paddingFocus: 8,
    hideSkip: false,
    textSkip: 'PULAR',
    alignSkip: Alignment.topRight,
    skipWidget: _SkipButton(color: cs.primary),
    beforeFocus: beforeFocus,
    onFinish: finish,
    onSkip: () {
      finish();
      return true;
    },
  ).show(context: context);
}

/// Aguarda o RBAC e as licenças da empresa (com teto), e um frame para a
/// sidebar/header remontarem com os módulos liberados.
Future<void> _awaitModuleAccess(ProviderContainer container) async {
  try {
    await Future.wait([
      container.read(myPermissionsProvider.future),
      container.read(enabledModuleIdsProvider.future),
    ]).timeout(const Duration(seconds: 5));
  } catch (_) {
    // Sem resposta a tempo: segue com os módulos já liberados.
  }
  await WidgetsBinding.instance.endOfFrame;
}

/// A busca do header só existe nas abas Canais e Conversas.
void _showSearchTab(ProviderContainer container) {
  final tab = container.read(chatTabProvider.notifier);
  if (tab.state == 2) tab.state = 1;
}

/// Passos do desktop: um por módulo liberado, na ordem do registro, com
/// descrição vinda do próprio [ModuleDescriptor.tourHint], mais a busca do
/// header e o perfil. Cada passo abre a view real do módulo.
List<_Step> _desktopSteps(
    ProviderContainer container, List<ModuleDescriptor> modules) {
  return [
    for (final m in modules)
      _Step(
        id: m.id,
        key: HomeTourKeys.moduleKey(m.id),
        icon: m.activeIcon,
        title: m.title,
        description: m.tourHint ?? 'Abra para explorar este módulo.',
        inSidebar: true,
        onActivate: () {
          if (m.activation == ModuleActivation.leftTab) {
            container.read(chatTabProvider.notifier).state =
                m.leftTabIndex ?? 0;
          } else {
            container.read(desktopSelectionProvider.notifier).state =
                DesktopSelection.module(m.id);
          }
        },
      ),
    _Step(
      id: 'search',
      key: HomeTourKeys.search,
      icon: Icons.search,
      title: 'Busca rápida',
      description:
          'Encontre pessoas, conversas e mensagens em qualquer lugar do app.',
      shape: ShapeLightFocus.Circle,
      onActivate: () => _showSearchTab(container),
    ),
    _Step(
      id: 'avatar',
      key: HomeTourKeys.avatarMenu,
      icon: Icons.account_circle,
      title: 'Seu perfil',
      description:
          'Acesse seu perfil, favoritas, suporte e configurações. É por aqui '
          'também que você pode rever este tutorial quando quiser.',
      shape: ShapeLightFocus.Circle,
      onActivate: () => container.read(desktopSelectionProvider.notifier).state =
          const DesktopSelection(type: DesktopViewType.profile),
    ),
  ];
}

/// Passos do mobile: abas da barra inferior, busca, atalhos de módulo do
/// header e um passo por módulo do menu "Módulos" — o mesmo conjunto que o
/// desktop mostra na sidebar.
List<_Step> _mobileSteps(
    ProviderContainer container, List<ModuleDescriptor> modules) {
  void tab(int index) => container.read(chatTabProvider.notifier).state = index;

  return [
    _Step(
      id: 'tab_canais',
      key: HomeTourKeys.tabCanais,
      icon: Icons.campaign,
      title: 'Canais',
      description:
          'Avisos e comunicados oficiais da empresa. Explore e siga os canais '
          'que interessam ao seu trabalho.',
      onActivate: () => tab(0),
    ),
    _Step(
      id: 'tab_conversas',
      key: HomeTourKeys.tabConversas,
      icon: Icons.chat_bubble,
      title: 'Conversas',
      description:
          'Mensagens diretas e grupos com seus colegas. É aqui que o dia a dia '
          'acontece.',
      onActivate: () => tab(1),
    ),
    _Step(
      id: 'tab_chamadas',
      key: HomeTourKeys.tabChamadas,
      icon: Icons.videocam,
      title: 'Chamadas',
      description: 'Voz e vídeo com uma pessoa ou com o time inteiro.',
      onActivate: () => tab(2),
    ),
    _Step(
      id: 'search',
      key: HomeTourKeys.search,
      icon: Icons.search,
      title: 'Busca rápida',
      description:
          'Encontre pessoas, conversas e mensagens em qualquer lugar do app.',
      shape: ShapeLightFocus.Circle,
      onActivate: () => _showSearchTab(container),
    ),
    for (final m in modules.where((m) => m.section == ModuleSection.helpdesk))
      _Step(
        id: 'header_${m.id}',
        key: HomeTourKeys.headerModuleKey(m.id),
        icon: m.activeIcon,
        title: m.title,
        description: m.tourHint ?? 'Abra para explorar este módulo.',
        shape: ShapeLightFocus.Circle,
      ),
    for (final m in mobileMenuModules(modules))
      _Step(
        id: 'menu_${m.id}',
        key: HomeTourKeys.modulesMenu,
        icon: m.activeIcon,
        title: m.title,
        caption: 'MENU MÓDULOS · ${moduleSectionLabel(m.section)}',
        description: m.tourHint ?? 'Abra para explorar este módulo.',
        shape: ShapeLightFocus.Circle,
      ),
    _Step(
      id: 'avatar',
      key: HomeTourKeys.avatarMenu,
      icon: Icons.account_circle,
      title: 'Seu perfil',
      description:
          'Acesse seu perfil, favoritas, suporte e configurações. É por aqui '
          'também que você pode rever este tutorial quando quiser.',
      shape: ShapeLightFocus.Circle,
    ),
  ];
}

/// Escolhe de que lado do alvo o balão aparece, sem sobrepor o elemento:
/// • Desktop: itens encostados na borda esquerda (CrmSidebar) → balão à
///   DIREITA; demais alvos (ex.: busca no header) → abaixo.
/// • Mobile: acima/abaixo conforme a metade vertical da tela.
ContentAlign _alignFor(GlobalKey key, Size screen, bool isDesktop) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) {
    return isDesktop ? ContentAlign.right : ContentAlign.bottom;
  }
  final topLeft = box.localToGlobal(Offset.zero);
  final centerX = topLeft.dx + box.size.width / 2;
  final centerY = topLeft.dy + box.size.height / 2;

  if (isDesktop) {
    return centerX < screen.width * 0.22
        ? ContentAlign.right
        : ContentAlign.bottom;
  }
  return centerY < screen.height / 2 ? ContentAlign.bottom : ContentAlign.top;
}

TargetFocus _toTarget(_Step step, Size screen, bool isDesktop) {
  return TargetFocus(
    identify: step.id,
    keyTarget: step.key,
    shape: step.shape,
    radius: 20,
    // Permite avançar tocando em QUALQUER lugar (não só no alvo recortado),
    // que às vezes fica atrás do balão.
    enableOverlayTab: true,
    contents: [
      TargetContent(
        align: _alignFor(step.key, screen, isDesktop),
        builder: (context, controller) => _TourCard(
          icon: step.icon,
          title: step.title,
          description: step.description,
          caption: step.caption,
        ),
      ),
    ],
  );
}

class _TourCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? caption;

  const _TourCard({
    required this.icon,
    required this.title,
    required this.description,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (caption != null) ...[
            Text(
              caption!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Toque para continuar',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward,
                size: 14,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  final Color color;
  const _SkipButton({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Pular tour',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}
