import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:alinha_ja/core/ui/responsive_layout.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/onboarding/onboarding_launcher.dart';
import 'package:alinha_ja/features/onboarding/tour_replay_provider.dart';
import 'package:alinha_ja/features/support/data/help_faq.dart';
import 'package:alinha_ja/features/support/ui/help_guides_view.dart';
import 'package:alinha_ja/features/support/ui/help_manual_view.dart';
import 'package:alinha_ja/features/support/ui/support_dashboard_screen.dart';

/// Hub de Ajuda & Suporte (item "Central de Ajuda" da sidebar).
///
/// Reúne, numa porta só, quatro frentes de apoio ao usuário, em ordem
/// crescente de profundidade:
/// • **Central de Ajuda** — perguntas frequentes pesquisáveis + ações rápidas;
/// • **Guias** — a Academia, com roteiros passo a passo por módulo;
/// • **Manual** — a documentação de referência (regras, campos, permissões);
/// • **Meus Chamados** — acompanhamento dos tickets do próprio usuário.
///
/// É a visão de *consumo* do módulo Helpdesk (`helpdesk:view`); a fila de
/// atendimento (resolver) vive na tela separada `HelpdeskAdminScreen`.
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Ajuda & Suporte',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.help_outline_rounded), text: 'Central de Ajuda'),
              Tab(icon: Icon(Icons.lightbulb_outline_rounded), text: 'Guias'),
              Tab(icon: Icon(Icons.description_outlined), text: 'Manual'),
              Tab(
                  icon: Icon(Icons.receipt_long_rounded),
                  text: 'Meus Chamados'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ResponsiveWidthContainer(child: HelpFaqView()),
            ResponsiveWidthContainer(child: HelpGuidesView()),
            ResponsiveWidthContainer(child: HelpManualView()),
            ResponsiveWidthContainer(child: MyTicketsView()),
          ],
        ),
      ),
    );
  }
}

/// Dispara o fluxo de introdução + tour guiado a partir da Central de Ajuda.
///
/// No desktop a CrmSidebar já está montada, então basta chamar direto. No
/// mobile a Central de Ajuda está empilhada sobre a home; sinalizamos via
/// [tourReplayProvider] e voltamos para `/`, onde o MainScaffold assume e
/// dispara o tour com os alvos (bottom nav) montados.
Future<void> replayTour(BuildContext context, WidgetRef ref) async {
  final isDesktop = MediaQuery.of(context).size.width >= kDesktopBreakpoint;
  if (isDesktop) {
    await launchOnboarding(context, reset: true);
    return;
  }
  ref.read(tourReplayProvider.notifier).state = true;
  if (context.mounted) context.go('/');
}

// ─────────────────────────── Central de Ajuda (FAQ) ───────────────────────────

/// Central de Ajuda pesquisável (perguntas frequentes) com ações rápidas no
/// topo. Sem Scaffold próprio para poder ser embutida como aba do hub.
class HelpFaqView extends StatefulWidget {
  const HelpFaqView({super.key});

  @override
  State<HelpFaqView> createState() => _HelpFaqViewState();
}

class _HelpFaqViewState extends State<HelpFaqView> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _searchQuery.toLowerCase();

    final filteredTopics = kHelpTopics.where((topic) {
      if (q.isEmpty) return true;
      return topic.title.toLowerCase().contains(q) ||
          topic.content.toLowerCase().contains(q) ||
          topic.category.toLowerCase().contains(q) ||
          topic.tags.any((tag) => tag.contains(q));
    }).toList();

    // As categorias já vêm prefixadas ("1 · 🚀 Começando"), então a ordem
    // alfabética reproduz a ordem didática pretendida.
    final Map<String, List<HelpTopic>> grouped = {};
    for (final topic in filteredTopics) {
      grouped.putIfAbsent(topic.category, () => []).add(topic);
    }
    final sortedCategories = grouped.keys.toList()..sort();

    return Column(
      children: [
        // Cabeçalho / Campo de Busca
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.08),
                theme.colorScheme.primary.withValues(alpha: 0.01),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              Text(
                'Como podemos ajudar você hoje?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -0.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Pesquise por termos operacionais, permissões ou chamados',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchCtrl,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Buscar na central de ajuda...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          tooltip: 'Limpar busca',
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  isDense: true,
                ),
              ),
            ],
          ),
        ),

        // Ações rápidas (tour guiado, guias, manual, abrir chamado)
        const _QuickActionsBar(),
        const Divider(height: 1),

        // Lista de Tópicos
        Expanded(
          child: filteredTopics.isEmpty
              ? _NoTopics(query: _searchQuery)
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: sortedCategories.length,
                  itemBuilder: (context, catIdx) {
                    final category = sortedCategories[catIdx];
                    final topics = grouped[category]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(left: 8, top: 16, bottom: 8),
                          child: Text(
                            category.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        ...topics.map((topic) => _TopicCard(
                              topic: topic,
                              expanded: _searchQuery.isNotEmpty,
                            )),
                      ],
                    );
                  },
                ),
        ),

        // Rodapé CTA - Fale Conosco
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ainda com dúvidas?',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Fale diretamente com nossa equipe de suporte da T.I.',
                      style: TextStyle(
                          color: theme.colorScheme.outline, fontSize: 11),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/support/new'),
                icon: const Icon(Icons.support_agent_rounded, size: 18),
                label: const Text('Suporte T.I.'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cartão expansível de uma pergunta frequente.
class _TopicCard extends StatelessWidget {
  final HelpTopic topic;
  final bool expanded;

  const _TopicCard({required this.topic, required this.expanded});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            topic.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: theme.colorScheme.onSurface,
            ),
          ),
          iconColor: theme.colorScheme.primary,
          collapsedIconColor: theme.colorScheme.outline,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          initiallyExpanded: expanded,
          children: [
            const Divider(height: 16),
            // O conteúdo usa **negrito** em Markdown; renderizamos manualmente
            // para não carregar o parser inteiro em um texto de 3 linhas.
            _RichHelpText(text: topic.content),
          ],
        ),
      ),
    );
  }
}

/// Renderiza o texto de um tópico aplicando apenas negrito `**assim**`.
class _RichHelpText extends StatelessWidget {
  final String text;

  const _RichHelpText({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = TextStyle(
      fontSize: 13,
      height: 1.5,
      color: theme.colorScheme.onSurfaceVariant,
    );

    final spans = <TextSpan>[];
    // Alterna entre trecho normal e trecho em negrito a cada par de `**`.
    var bold = false;
    for (final part in text.split('**')) {
      if (part.isNotEmpty) {
        spans.add(TextSpan(
          text: part,
          style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
        ));
      }
      bold = !bold;
    }

    return RichText(text: TextSpan(style: base, children: spans));
  }
}

class _NoTopics extends StatelessWidget {
  final String query;
  const _NoTopics({required this.query});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = DefaultTabController.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.help_outline_rounded,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Nada encontrado para "$query"',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Tente termos mais genéricos como "card", "ponto" ou "permissão" — '
              'ou procure nas abas Guias e Manual, que têm busca própria.',
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => controller.animateTo(1),
                  icon: const Icon(Icons.lightbulb_outline_rounded, size: 16),
                  label: const Text('Ver guias'),
                ),
                OutlinedButton.icon(
                  onPressed: () => controller.animateTo(2),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Ver manual'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Faixa horizontal de ações rápidas exibida acima do FAQ.
class _QuickActionsBar extends ConsumerWidget {
  const _QuickActionsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = DefaultTabController.of(context);

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _QuickAction(
            icon: Icons.school_rounded,
            label: 'Rever tutorial',
            color: theme.colorScheme.primary,
            onTap: () => replayTour(context, ref),
          ),
          _QuickAction(
            icon: Icons.menu_book_rounded,
            label: 'Guias passo\na passo',
            color: const Color(0xFF6366f1),
            onTap: () => controller.animateTo(1),
          ),
          _QuickAction(
            icon: Icons.auto_stories_rounded,
            label: 'Manual\ncompleto',
            color: const Color(0xFF14b8a6),
            onTap: () => controller.animateTo(2),
          ),
          _QuickAction(
            icon: Icons.add_comment_rounded,
            label: 'Abrir\nchamado',
            color: const Color(0xFFf59e0b),
            onTap: () => context.push('/support/new'),
          ),
          _QuickAction(
            icon: Icons.receipt_long_rounded,
            label: 'Meus\nchamados',
            color: const Color(0xFF0ea5e9),
            onTap: () => controller.animateTo(3),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 104,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 22),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
