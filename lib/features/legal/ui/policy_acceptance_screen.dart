import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:alinha_ja/core/ui/responsive_layout.dart' show kDesktopBreakpoint;
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/legal/data/legal_documents.dart';
import 'package:alinha_ja/features/legal/providers/legal_provider.dart';
import 'package:alinha_ja/features/legal/ui/widgets/legal_document_view.dart';
import 'package:alinha_ja/features/legal/ui/widgets/policy_acceptance_parts.dart';
import 'package:alinha_ja/features/legal/ui/widgets/policy_reader_page.dart';

/// Tela de consentimento exibida no primeiro acesso e sempre que uma versão
/// material de um documento é publicada.
///
/// Regras de desenho, que existem para o aceite ter valor probatório:
///   • o documento precisa ser ABERTO antes de a caixa liberar — aceite às
///     cegas não é consentimento informado (Art. 8º, § 1º);
///   • cada documento é aceito individualmente, com seu próprio tipo e versão;
///   • quem não concorda sai da conta — não há como seguir sem aceitar, nem
///     ficar preso na tela.
///
/// Layout: painel duplo no desktop (lista à esquerda, documento à direita) e
/// fluxo de leitura em tela cheia no celular. O mesmo widget atende web e APK.
class PolicyAcceptanceScreen extends ConsumerStatefulWidget {
  const PolicyAcceptanceScreen({super.key, required this.pending});

  final List<LegalDocument> pending;

  @override
  ConsumerState<PolicyAcceptanceScreen> createState() =>
      _PolicyAcceptanceScreenState();
}

class _PolicyAcceptanceScreenState
    extends ConsumerState<PolicyAcceptanceScreen> {
  final _opened = <String>{};
  final _read = <String>{};
  final _checked = <String>{};

  late String _selectedId = widget.pending.first.id;
  bool _saving = false;

  LegalDocument get _selected =>
      widget.pending.firstWhere((d) => d.id == _selectedId);

  bool get _canAccept =>
      widget.pending.every((doc) => _checked.contains(doc.id));

  /// No desktop, o documento selecionado está visível no painel direito — logo,
  /// foi apresentado. No celular só conta o que passou pelo leitor: `_opened`
  /// não pode nascer preenchido, senão a primeira caixa liberaria sem ninguém
  /// ter visto uma linha do texto.
  bool _isOpenedDesktop(LegalDocument doc) =>
      doc.id == _selectedId || _opened.contains(doc.id);

  void _toggle(LegalDocument doc, bool? value) {
    setState(() {
      if (value == true) {
        _checked.add(doc.id);
      } else {
        _checked.remove(doc.id);
      }
    });
  }

  void _select(LegalDocument doc) {
    setState(() {
      _selectedId = doc.id;
      _opened.add(doc.id);
    });
  }

  /// Marca que o titular chegou ao fim do texto. É indicador visual, não
  /// trava: a caixa de aceite já libera na abertura.
  void _markRead(LegalDocument doc) {
    if (!mounted || _read.contains(doc.id)) return;
    setState(() => _read.add(doc.id));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Largura sozinha não basta: celular em paisagem passa dos 800px
              // com menos de 400px de altura, e o painel duplo lá vira duas
              // colunas espremidas. Abaixo de 520px de altura, fluxo de leitura
              // em tela cheia — que é o que cabe.
              final painelDuplo = constraints.maxWidth >= kDesktopBreakpoint &&
                  constraints.maxHeight >= 520;
              return painelDuplo
                  ? _DesktopLayout(state: this)
                  : _MobileLayout(state: this);
            },
          ),
        ),
      ),
    );
  }

  /// Leitura em tela cheia (celular). Usa Navigator local e não o GoRouter: a
  /// tela de aceite cobre o app inteiro, e navegar pelo router aqui reentraria
  /// no próprio portão.
  Future<void> _readFullScreen(LegalDocument doc) async {
    _select(doc);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PolicyReaderPage(
          doc: doc,
          alreadyChecked: _checked.contains(doc.id),
          onReachedEnd: () => _markRead(doc),
          // Marca direto no estado em vez de devolver resultado pelo pop: o
          // aceite não pode depender de o valor sobreviver ao fechamento da
          // rota — se a navegação for interrompida, a caixa fica marcada do
          // mesmo jeito, que é o que o titular declarou.
          onAccept: () => _toggle(doc, true),
        ),
      ),
    );
  }

  /// Rodapé de ação, idêntico nos dois layouts.
  Widget _footer() => PolicyAcceptanceFooter(
        faltam: widget.pending.length - _checked.length,
        canAccept: _canAccept,
        saving: _saving,
        onSubmit: _submit,
        onSignOut: _signOut,
      );

  Future<void> _submit() async {
    setState(() => _saving = true);
    final repo = ref.read(legalRepositoryProvider);

    try {
      for (final doc in widget.pending) {
        await repo.acceptPolicy(doc);
      }
      ref.invalidate(myAcceptancesProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível registrar o aceite: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da conta'),
        content: const Text(
            'Sem aceitar os documentos não é possível usar a plataforma. '
            'Deseja sair?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await const AuthRepository().signOut();
      if (mounted) context.go('/login');
    }
  }
}

/* ───────────────────────── layout: desktop / web ───────────────────────── */

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.state});

  final _PolicyAcceptanceScreenState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = state._selected;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 380,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 20, 8),
                  children: [
                    const PolicyIntroHeader(compact: false),
                    const SizedBox(height: 24),
                    for (final d in state.widget.pending) ...[
                      PolicyDocumentTile(
                        doc: d,
                        selected: d.id == state._selectedId,
                        opened: state._isOpenedDesktop(d),
                        read: state._read.contains(d.id),
                        checked: state._checked.contains(d.id),
                        onTap: () => state._select(d),
                        onChanged: (v) => state._toggle(d, v),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 8),
                    const PolicyConsentNote(),
                  ],
                ),
              ),
              state._footer(),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom:
                        BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(doc.icon, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        doc.title,
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      'v${doc.version}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LegalDocumentReadingPane(
                  doc: doc,
                  onOpenDocument: state._select,
                  onReachedEnd: () => state._markRead(doc),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* ───────────────────────── layout: celular / APK ───────────────────────── */

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.state});

  final _PolicyAcceptanceScreenState state;

  @override
  Widget build(BuildContext context) {
    return ResponsiveWidthContainer(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              children: [
                const PolicyIntroHeader(compact: true),
                const SizedBox(height: 24),
                for (final d in state.widget.pending) ...[
                  PolicyDocumentTile(
                    doc: d,
                    selected: false,
                    opened: state._opened.contains(d.id),
                    read: state._read.contains(d.id),
                    checked: state._checked.contains(d.id),
                    onTap: () => state._readFullScreen(d),
                    onChanged: (v) => state._toggle(d, v),
                    showReadButton: true,
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                const PolicyConsentNote(),
              ],
            ),
          ),
          state._footer(),
        ],
      ),
    );
  }
}
