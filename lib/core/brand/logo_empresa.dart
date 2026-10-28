import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/brand/org_identity.dart';

/// Logo da empresa em atuação; sem logo cadastrado (ou se a imagem não
/// carregar), o logo do produto — ou nada, com [comLogoDoProduto] falso.
class LogoEmpresa extends ConsumerWidget {
  final double altura;
  final bool comLogoDoProduto;

  /// Logo do produto, trocado por arquivo na build de cada distribuição.
  static const logoDoProduto = 'assets/images/logo_header.png';

  const LogoEmpresa({
    super.key,
    this.altura = 32,
    this.comLogoDoProduto = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(orgIdentityProvider).value ?? OrgIdentity.vazia;
    final reserva = comLogoDoProduto
        ? Image.asset(logoDoProduto, height: altura, fit: BoxFit.contain)
        : const SizedBox.shrink();

    if (!id.temLogo) return reserva;

    return ConstrainedBox(
      // Logos largos não empurram o resto do cabeçalho.
      constraints: BoxConstraints(maxHeight: altura, maxWidth: altura * 4),
      child: CachedNetworkImage(
        imageUrl: id.logoUrl!,
        height: altura,
        fit: BoxFit.contain,
        fadeInDuration: Duration.zero,
        placeholder: (_, __) => SizedBox(height: altura, width: altura),
        errorWidget: (_, __, ___) => reserva,
      ),
    );
  }
}
