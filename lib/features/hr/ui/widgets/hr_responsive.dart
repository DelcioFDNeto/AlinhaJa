import 'package:flutter/material.dart';

import 'package:alinha_ja/core/ui/responsive_layout.dart' show kDesktopBreakpoint;

/// Helpers de responsividade das telas de RH.
///
/// O app roda no mesmo binário em mobile e web/desktop, e as telas de RH
/// aparecem em dois contextos de largura bem diferentes: tela cheia no
/// mobile e painel direito (ao lado da sidebar) no desktop. Por isso as
/// medidas saem de `LayoutBuilder`/`constraints`, não de
/// `MediaQuery.size` — no desktop o painel é mais estreito que a janela.
extension HrBreakpoints on BoxConstraints {
  /// Layout compacto: uma coluna, ações empilhadas.
  bool get isCompact => maxWidth < kDesktopBreakpoint;

  /// Largura confortável para formulários e listas de leitura.
  bool get isWide => maxWidth >= kDesktopBreakpoint;

  /// Quantas colunas cabem numa grade de cards de ~340px.
  int get hrGridColumns {
    if (maxWidth >= 1240) return 3;
    if (maxWidth >= kDesktopBreakpoint) return 2;
    return 1;
  }
}

/// Centraliza e limita a largura do conteúdo, com padding que acompanha a
/// largura disponível. Em telas largas o conteúdo não estica até a borda;
/// no mobile ocupa tudo, com respiro menor.
class HrContentColumn extends StatelessWidget {
  const HrContentColumn({
    super.key,
    required this.child,
    this.maxWidth = 900,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.isCompact ? 16.0 : 24.0;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Linha de campos que vira coluna quando não há largura.
///
/// Resolve o caso mais comum dos formulários de RH: dois campos lado a
/// lado no desktop que, espremidos no celular, causariam overflow.
class HrFieldRow extends StatelessWidget {
  const HrFieldRow({
    super.key,
    required this.children,
    this.spacing = 12,
    this.breakAt = 520,
  });

  final List<Widget> children;
  final double spacing;

  /// Abaixo desta largura os campos empilham.
  final double breakAt;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakAt) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Sheet modal que vira diálogo centrado em telas largas.
///
/// No celular o bottom sheet é o gesto natural; no desktop um sheet
/// colado embaixo numa janela de 1600px fica estranho e longe do cursor.
Future<T?> showHrFormSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double dialogWidth = 560,
}) {
  final wide = MediaQuery.of(context).size.width >= kDesktopBreakpoint;
  if (!wide) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: builder(ctx),
      ),
    ),
  );
}
