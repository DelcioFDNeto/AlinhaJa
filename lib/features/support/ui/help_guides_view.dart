import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/modules/module_access_provider.dart';
import 'package:alinha_ja/features/support/data/help_guides.dart';
import 'package:alinha_ja/features/support/ui/help_image.dart';

/// Aba **Guias** — a Academia: um roteiro numerado por módulo do sistema.
///
/// Cada [HelpGuide] é um cartão expansível com o público-alvo, o atalho para
/// o módulo (quando o usuário tem permissão) e os passos com captura real.
/// A busca filtra por título, descrição, palavras-chave e pelo texto dos
/// próprios passos — quem procura "holerite" acha o passo mesmo que a palavra
/// não esteja no título do guia.
class HelpGuidesView extends StatefulWidget {
  const HelpGuidesView({super.key});

  @override
  State<HelpGuidesView> createState() => _HelpGuidesViewState();
}

class _HelpGuidesViewState extends State<HelpGuidesView> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(HelpGuide g, String q) {
    if (g.title.toLowerCase().contains(q) ||
        g.description.toLowerCase().contains(q) ||
        g.keywords.contains(q) ||
        g.audience.toLowerCase().contains(q)) {
      return true;
    }
    return g.steps.any((s) =>
        s.title.toLowerCase().contains(q) ||
        s.description.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.toLowerCase();
    final guides =
        q.isEmpty ? kHelpGuides : kHelpGuides.where((g) => _matches(g, q)).toList();

    final totalSteps =
        kHelpGuides.fold<int>(0, (sum, g) => sum + g.steps.length);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Academia ${AppConstants.appName}',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${kHelpGuides.length} roteiros · $totalSteps passos ilustrados '
                'com telas reais do sistema.',
                style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  hintText: "Buscar guia: 'holerite', 'card', 'permissão'...",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          tooltip: 'Limpar busca',
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: guides.isEmpty
              ? _EmptyGuides(query: _query)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: guides.length,
                  itemBuilder: (context, i) => _GuideCard(
                    guide: guides[i],
                    initiallyExpanded: _query.isNotEmpty && guides.length <= 3,
                  ),
                ),
        ),
      ],
    );
  }
}

class _EmptyGuides extends StatelessWidget {
  final String query;
  const _EmptyGuides({required this.query});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore_rounded,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'Nenhum guia para "$query"',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Tente um termo mais genérico, ou procure na aba Manual — '
              'lá estão as regras detalhadas de cada módulo.',
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final HelpGuide guide;
  final bool initiallyExpanded;

  const _GuideCard({required this.guide, required this.initiallyExpanded});

  /// Só oferece o atalho quando há rota e o RBAC do módulo permite entrar —
  /// caso contrário o botão levaria a um redirecionamento silencioso.
  bool get _canOpen {
    final route = guide.route;
    if (route == null) return false;
    final moduleId = guide.moduleId;
    return moduleId == null || canAccessModuleRouteSync(moduleId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('guide_${guide.id}'),
          initiallyExpanded: initiallyExpanded,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: guide.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(guide.icon, color: guide.color),
          ),
          title: Text(
            guide.title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guide.description,
                  style:
                      TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Chip(
                      icon: Icons.groups_rounded,
                      label: guide.audience,
                      color: guide.color,
                    ),
                    _Chip(
                      icon: Icons.format_list_numbered_rounded,
                      label: '${guide.steps.length} passos',
                      color: theme.colorScheme.outline,
                    ),
                  ],
                ),
              ],
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            if (_canOpen)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(guide.route!),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Abrir módulo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: guide.color,
                      side: BorderSide(color: guide.color.withValues(alpha: 0.4)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            for (var i = 0; i < guide.steps.length; i++)
              _GuideStepTile(
                index: i + 1,
                step: guide.steps[i],
                color: guide.color,
                isLast: i == guide.steps.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideStepTile extends StatelessWidget {
  final int index;
  final HelpGuideStep step;
  final Color color;
  final bool isLast;

  const _GuideStepTile({
    required this.index,
    required this.step,
    required this.color,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trilha numerada: conecta os passos verticalmente.
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text(
                  '$index',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: color.withValues(alpha: 0.22),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      step.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step.description,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (step.tip != null) ...[
                    const SizedBox(height: 8),
                    _StepTip(text: step.tip!, color: color),
                  ],
                  if (step.image != null) ...[
                    const SizedBox(height: 10),
                    HelpImage(asset: step.image!, caption: step.title),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTip extends StatelessWidget {
  final String text;
  final Color color;

  const _StepTip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
