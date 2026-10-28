import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';

/// Identidade visual da empresa em atuação: nome, logo e cores.
///
/// O AlinhaJá é white-label em dois níveis:
///   • a MARCA DO PRODUTO (nome do app, cor-base) vem da build —
///     [AppConstants.appName] e [AppConstants.primary], definidos por
///     `--dart-define=BRAND_NAME` e `BRAND_PRIMARY_COLOR`;
///   • a IDENTIDADE DA EMPRESA (logo e cores) vem do banco e troca em tempo
///     de execução, sem build — é o que este modelo carrega.
///
/// Campos nulos significam "use o padrão da marca".
@immutable
class OrgIdentity {
  final String? organizationId;
  final String? nome;
  final String? logoUrl;
  final Color? corPrimaria;
  final Color? corSecundaria;

  const OrgIdentity({
    this.organizationId,
    this.nome,
    this.logoUrl,
    this.corPrimaria,
    this.corSecundaria,
  });

  /// Sem empresa resolvida (antes do login, falha de rede): só a marca.
  static const vazia = OrgIdentity();

  /// Cor principal efetiva: a da empresa ou, sem ela, a da marca.
  Color get primariaEfetiva => corPrimaria ?? AppConstants.primary;

  bool get temLogo => logoUrl != null && logoUrl!.isNotEmpty;

  factory OrgIdentity.fromJson(Map<String, dynamic> json) {
    String? texto(String chave) {
      final v = json[chave];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return OrgIdentity(
      organizationId: texto('organization_id'),
      nome: texto('nome'),
      logoUrl: texto('logo_url'),
      corPrimaria: corDeHex(texto('cor_primaria')),
      corSecundaria: corDeHex(texto('cor_secundaria')),
    );
  }

  /// `#RRGGBB` (com ou sem `#`) → cor opaca. Qualquer outra coisa → nulo.
  static Color? corDeHex(String? hex) {
    if (hex == null) return null;
    final limpo = hex.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(limpo)) return null;
    return Color(int.parse('FF$limpo', radix: 16));
  }

  /// Cor → `#RRGGBB` em maiúsculas, o formato que o banco aceita.
  static String hexDeCor(Color cor) {
    final argb = cor.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// Razão de contraste WCAG entre duas cores (1 a 21).
  static double contraste(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final claro = la > lb ? la : lb;
    final escuro = la > lb ? lb : la;
    return (claro + 0.05) / (escuro + 0.05);
  }

  /// Texto sobre a cor (botões, barra) fica legível com branco ou preto?
  /// 3:1 é o mínimo WCAG para texto grande e componentes de interface.
  static bool legivelComTexto(Color fundo) =>
      contraste(fundo, Colors.white) >= 3 ||
      contraste(fundo, Colors.black) >= 3;

  /// Cor da empresa conhecida fora da árvore de widgets — usada por quem não
  /// tem `BuildContext`, como as notificações do Android. Atualizada sempre
  /// que a identidade é carregada; parte da cor da marca.
  static Color corAtual = AppConstants.primary;

  @override
  bool operator ==(Object other) =>
      other is OrgIdentity &&
      other.organizationId == organizationId &&
      other.nome == nome &&
      other.logoUrl == logoUrl &&
      other.corPrimaria == corPrimaria &&
      other.corSecundaria == corSecundaria;

  @override
  int get hashCode =>
      Object.hash(organizationId, nome, logoUrl, corPrimaria, corSecundaria);
}

/// Identidade da empresa do usuário logado. Recarrega quando o usuário muda;
/// após gravar uma identidade nova, invalide este provider.
///
/// Nunca falha: sem sessão ou sem resposta, devolve [OrgIdentity.vazia] e o
/// app segue com a marca do produto.
final orgIdentityProvider = FutureProvider<OrgIdentity>((ref) async {
  final userId = ref.watch(currentUserProvider.select((u) => u.value?.id));
  if (userId == null) {
    OrgIdentity.corAtual = AppConstants.primary;
    return OrgIdentity.vazia;
  }
  try {
    final res = await supabase.rpc('get_org_identity');
    final id = res is Map<String, dynamic>
        ? OrgIdentity.fromJson(res)
        : OrgIdentity.vazia;
    OrgIdentity.corAtual = id.primariaEfetiva;
    return id;
  } catch (e) {
    debugPrint('OrgIdentity: identidade indisponível ($e) — usando a marca.');
    return OrgIdentity.vazia;
  }
});

/// Cor de destaque vigente na árvore: a primária do tema, que já reflete a
/// cor da empresa (ou a da marca, ou o esquema escolhido pelo usuário).
extension CorDaMarca on BuildContext {
  Color get corMarca => Theme.of(this).colorScheme.primary;
}
