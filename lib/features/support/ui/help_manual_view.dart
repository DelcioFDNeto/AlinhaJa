import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:alinha_ja/features/support/data/help_manual.dart';
import 'package:alinha_ja/features/support/ui/help_image.dart';

/// Aba **Manual** — a documentação de referência, pesquisável e agrupada por
/// categoria.
///
/// Enquanto os Guias ensinam a fazer, o Manual explica as regras: campos,
/// status, tabelas de permissão e comportamento de cada módulo. Cada artigo é
/// um cartão expansível com o corpo em Markdown (imagens, tabelas e caixas de
/// destaque).
class HelpManualView extends StatefulWidget {
  const HelpManualView({super.key});

  @override
  State<HelpManualView> createState() => _HelpManualViewState();
}

class _HelpManualViewState extends State<HelpManualView> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.toLowerCase();

    // A busca inclui o corpo Markdown: o termo procurado quase nunca está no
    // título do artigo, e sim no parágrafo que explica o campo.
    final filtered = kManualArticles.where((art) {
      if (q.isEmpty) return true;
      return art.title.toLowerCase().contains(q) ||
          art.category.toLowerCase().contains(q) ||
          art.keywords.contains(q) ||
          art.markdown.toLowerCase().contains(q);
    }).toList();

    final grouped = <String, List<ManualArticle>>{};
    for (final art in filtered) {
      grouped.putIfAbsent(art.category, () => []).add(art);
    }
    final categories = grouped.keys.toList()..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  hintText: "Pesquise por 'RBAC', 'SLA', 'ponto', 'LGPD'...",
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
              const SizedBox(height: 8),
              Text(
                _query.isEmpty
                    ? '${kManualArticles.length} artigos em '
                        '${_categoryCount()} categorias.'
                    : '${filtered.length} de ${kManualArticles.length} artigos '
                        'mencionam "$_query".',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book_rounded,
                            size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum artigo para "$_query"',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tente um termo mais genérico, ou veja a aba Guias '
                          'para o roteiro passo a passo do módulo.',
                          style: TextStyle(
                              color: theme.colorScheme.outline, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    for (final cat in categories) ...[
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 4, top: 12, bottom: 6),
                        child: Text(
                          cat.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      for (final art in grouped[cat]!)
                        _ManualArticleCard(
                          article: art,
                          initiallyExpanded:
                              _query.isNotEmpty && filtered.length <= 3,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  int _categoryCount() =>
      kManualArticles.map((a) => a.category).toSet().length;
}

class _ManualArticleCard extends StatelessWidget {
  final ManualArticle article;
  final bool initiallyExpanded;

  const _ManualArticleCard({
    required this.article,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('manual_${article.id}'),
          leading: Icon(article.icon, color: theme.colorScheme.primary),
          title: Text(
            article.title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          initiallyExpanded: initiallyExpanded,
          children: [
            const Divider(height: 8),
            MarkdownBody(
              data: article.markdown,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                h2: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
                h3: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                blockquotePadding: const EdgeInsets.all(12.0),
                blockquoteDecoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  border: Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 4.0,
                    ),
                  ),
                ),
                tableBorder: TableBorder.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                  width: 1.0,
                ),
                tableCellsPadding: const EdgeInsets.all(6.0),
              ),
              sizedImageBuilder: (config) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: HelpImage(
                  asset: config.uri.toString(),
                  caption: article.title,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
