import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/legal/data/legal_documents.dart';
import 'package:alinha_ja/features/legal/models/org_legal_profile.dart';
import 'package:alinha_ja/features/legal/providers/legal_provider.dart';
import 'package:alinha_ja/features/legal/ui/widgets/legal_markdown.dart';

/// Corpo rolável de um documento legal, com carregamento e erro tratados.
///
/// Compartilhado pelo leitor comum, pelo painel direito da tela de aceite no
/// desktop e pela leitura em tela cheia no celular — o texto precisa ser o
/// mesmo nos três, e um widget só garante isso.
class LegalDocumentView extends ConsumerStatefulWidget {
  const LegalDocumentView({
    super.key,
    required this.doc,
    required this.onOpenDocument,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 40),
    this.onReachedEnd,
  });

  final LegalDocument doc;
  final ValueChanged<LegalDocument> onOpenDocument;

  /// Faixa opcional acima do texto (status de aceite, versão…).
  final Widget? header;

  final EdgeInsets padding;

  /// Disparado quando o leitor chega ao fim do documento. Serve de sinal de
  /// leitura efetiva — não bloqueia nada, apenas informa a tela de aceite.
  final VoidCallback? onReachedEnd;

  @override
  ConsumerState<LegalDocumentView> createState() => _LegalDocumentViewState();
}

class _LegalDocumentViewState extends ConsumerState<LegalDocumentView> {
  final _controller = ScrollController();
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_checkEnd);
  }

  @override
  void didUpdateWidget(covariant LegalDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trocou de documento no painel: o rastro de leitura recomeça e a rolagem
    // volta ao topo, senão o novo texto abre no meio.
    if (oldWidget.doc.id != widget.doc.id) {
      _notified = false;
      if (_controller.hasClients) _controller.jumpTo(0);
    }
  }

  void _checkEnd() {
    if (_notified || widget.onReachedEnd == null) return;
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    // Margem de 80px: exigir o pixel final falha em telas com barra flutuante.
    if (pos.pixels >= pos.maxScrollExtent - 80) {
      _notified = true;
      widget.onReachedEnd!.call();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textAsync = ref.watch(legalDocumentTextProvider(widget.doc.id));

    return textAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 32),
              const SizedBox(height: 12),
              Text(
                'Não foi possível carregar o documento.\n$e',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      data: (markdown) {
        // Documento curto não rola: sem evento de fim, a leitura nunca seria
        // marcada. Marca no primeiro frame se não há o que rolar.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_controller.hasClients &&
              _controller.position.maxScrollExtent <= 0) {
            _checkEndImmediate();
          }
        });

        return Scrollbar(
          controller: _controller,
          child: ListView(
            controller: _controller,
            padding: widget.padding,
            children: [
              if (widget.header != null) ...[
                widget.header!,
                const SizedBox(height: 8),
              ],
              const _IncompleteProfileNotice(),
              LegalMarkdown(
                data: markdown,
                onOpenDocument: widget.onOpenDocument,
              ),
            ],
          ),
        );
      },
    );
  }

  void _checkEndImmediate() {
    if (_notified || widget.onReachedEnd == null) return;
    _notified = true;
    widget.onReachedEnd!.call();
  }
}

/// Faixa que aparece quando a empresa ainda não preencheu os dados legais.
///
/// Existe porque o documento sai com `[RAZÃO SOCIAL]` e `[E-MAIL DO DPO]`
/// literais na tela, e quem lê precisa entender que isso é cadastro pendente —
/// não um erro de renderização, e muito menos um documento em vigor.
class _IncompleteProfileNotice extends ConsumerWidget {
  const _IncompleteProfileNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final perfil = ref.watch(orgLegalProfileProvider);

    final faltando = perfil.maybeWhen(
      data: (p) => p.missingEssentials,
      orElse: () => const <LegalField>[],
    );
    if (faltando.isEmpty) return const SizedBox.shrink();

    final campos = faltando.map((f) => f.label).join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Documento ainda não personalizado. Faltam os dados da empresa: '
              '$campos. Os campos entre colchetes são preenchidos '
              'automaticamente assim que um administrador cadastrá-los em '
              'Painel Administrativo → Dados Legais.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Envolve [LegalDocumentView] limitando a largura da coluna de texto — linha
/// muito longa é ilegível em monitor grande.
class LegalDocumentReadingPane extends StatelessWidget {
  const LegalDocumentReadingPane({
    super.key,
    required this.doc,
    required this.onOpenDocument,
    this.header,
    this.onReachedEnd,
    this.padding = const EdgeInsets.fromLTRB(24, 16, 24, 48),
  });

  final LegalDocument doc;
  final ValueChanged<LegalDocument> onOpenDocument;
  final Widget? header;
  final VoidCallback? onReachedEnd;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ResponsiveWidthContainer(
      maxWidth: 820,
      child: LegalDocumentView(
        key: ValueKey(doc.id),
        doc: doc,
        onOpenDocument: onOpenDocument,
        header: header,
        padding: padding,
        onReachedEnd: onReachedEnd,
      ),
    );
  }
}
