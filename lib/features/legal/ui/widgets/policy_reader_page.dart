import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:alinha_ja/features/legal/data/legal_documents.dart';
import 'package:alinha_ja/features/legal/ui/widgets/legal_document_view.dart';

/// Leitura em tela cheia usada pelo fluxo de consentimento no celular.
///
/// Usa Navigator local (e não o GoRouter): a tela de aceite cobre o app
/// inteiro, e navegar pelo router aqui reentraria no próprio portão.
class PolicyReaderPage extends StatefulWidget {
  const PolicyReaderPage({
    super.key,
    required this.doc,
    required this.alreadyChecked,
    required this.onReachedEnd,
    required this.onAccept,
  });

  final LegalDocument doc;

  /// Já marcado na lista — muda o rótulo do botão para não sugerir novo aceite.
  final bool alreadyChecked;

  final VoidCallback onReachedEnd;

  /// Marca o aceite direto no estado da tela anterior. Não devolvemos resultado
  /// pelo `pop` de propósito: o que o titular declarou não pode depender de o
  /// valor sobreviver ao fechamento da rota.
  final VoidCallback onAccept;

  @override
  State<PolicyReaderPage> createState() => _PolicyReaderPageState();
}

class _PolicyReaderPageState extends State<PolicyReaderPage> {
  late LegalDocument _doc = widget.doc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // O texto referencia outros documentos; ao navegar para um deles a barra de
    // aceite some — só se aceita o documento que se veio ler.
    final isMainDoc = _doc.id == widget.doc.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(_doc.title,
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: LegalDocumentReadingPane(
        doc: _doc,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        onOpenDocument: (target) => setState(() => _doc = target),
        onReachedEnd: isMainDoc ? widget.onReachedEnd : null,
      ),
      // A confirmação vive no fim da leitura: mandar o titular voltar e caçar o
      // checkbox na lista é o jeito mais fácil de alguém aceitar sem ler.
      bottomNavigationBar: isMainDoc
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ao confirmar, você declara ter lido este documento '
                        '(v${_doc.version}).',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        widget.onAccept();
                        Navigator.pop(context);
                      },
                      child: Text(
                        widget.alreadyChecked ? 'Continuar' : 'Li e concordo',
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
