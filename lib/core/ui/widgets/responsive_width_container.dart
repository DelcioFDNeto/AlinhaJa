import 'package:flutter/material.dart';

/// Um wrapper que centraliza e limita a largura do conteúdo.
/// Especialmente útil no Desktop para evitar formulários ultra largos.
class ResponsiveWidthContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final Alignment alignment;

  const ResponsiveWidthContainer({
    super.key,
    required this.child,
    this.maxWidth = 850.0,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child:
            padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );
  }
}
