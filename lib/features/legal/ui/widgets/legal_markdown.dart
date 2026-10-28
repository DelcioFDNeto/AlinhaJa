import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alinha_ja/features/legal/data/legal_documents.dart';

/// Corpo Markdown de um documento legal.
///
/// Os arquivos em `docs/legal/` se referenciam entre si por link relativo
/// (`02-politica-de-privacidade.md`). No app esses links precisam navegar para
/// o documento correspondente, e não abrir o navegador num caminho que não
/// existe — daí o [onOpenDocument].
class LegalMarkdown extends StatelessWidget {
  const LegalMarkdown({
    super.key,
    required this.data,
    required this.onOpenDocument,
    this.selectable = true,
  });

  final String data;
  final ValueChanged<LegalDocument> onOpenDocument;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MarkdownBody(
      data: data,
      selectable: selectable,
      onTapLink: (text, href, title) => _handleLink(context, href),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
        h1: theme.textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w800, height: 1.3),
        h2: theme.textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800, height: 1.4),
        h3: theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700, height: 1.4),
        listBullet: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
        blockquotePadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 4),
          ),
        ),
        tableBorder: TableBorder.all(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        tableHead: theme.textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w700),
        tableBody: theme.textTheme.bodySmall?.copyWith(height: 1.4),
        code: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLink(BuildContext context, String? href) async {
    if (href == null || href.isEmpty) return;

    // Link entre documentos do próprio pacote → navega dentro do app.
    if (href.endsWith('.md') || href.contains('.md#')) {
      final target = legalDocumentByFile(href);
      if (target != null) {
        onOpenDocument(target);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Documento não disponível no app.')),
        );
      }
      return;
    }

    // Âncora interna: o leitor já mostra o documento inteiro, nada a fazer.
    if (href.startsWith('#')) return;

    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir $href')),
        );
      }
    }
  }
}
