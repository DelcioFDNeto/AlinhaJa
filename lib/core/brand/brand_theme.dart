import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import 'package:alinha_ja/core/brand/org_identity.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/core/theme_provider.dart';

/// Temas do app a partir do esquema escolhido pelo usuário e da identidade
/// da empresa. Sem cor de empresa, o resultado é idêntico ao tema da marca.
class BrandTheme {
  BrandTheme._();

  /// Vermelho da marca AlinhaJá e o tom escuro que sempre o acompanhou.
  static const _vermelhoDaMarca = Color(0xFFD21A18);
  static const _containerDoVermelho = Color(0xFFA51412);

  static const _subTemasClaro = FlexSubThemesData(
    blendOnLevel: 10,
    blendOnColors: false,
    useMaterial3Typography: true,
    useM2StyleDividerInM3: true,
    inputDecoratorRadius: 14,
    inputDecoratorBorderType: FlexInputBorderType.outline,
    inputDecoratorUnfocusedHasBorder: false,
  );

  /// Escurece (valor negativo) ou clareia uma cor em [delta] de luminosidade.
  static Color ajustarLuz(Color cor, double delta) {
    final hsl = HSLColor.fromColor(cor);
    return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
  }

  /// Tom escuro de apoio (container) de uma cor primária. O vermelho da
  /// marca mantém o tom de sempre; qualquer outra cor — da empresa ou de uma
  /// distribuição com `BRAND_PRIMARY_COLOR` — recebe o tom derivado dela.
  static Color containerDe(Color primaria) => primaria == _vermelhoDaMarca
      ? _containerDoVermelho
      : ajustarLuz(primaria, -0.10);

  /// Cores da marca/empresa para o esquema padrão.
  static FlexSchemeColor coresPadrao(OrgIdentity id, Brightness brilho) {
    final primaria = id.corPrimaria ?? AppConstants.primary;
    final container = containerDe(primaria);
    final escuro = brilho == Brightness.dark;
    final secundaria =
        id.corSecundaria ?? (escuro ? const Color(0xFFFFFFFF) : const Color(0xFF000000));
    final secundariaContainer = id.corSecundaria == null
        ? (escuro ? const Color(0xFFE0E0E0) : const Color(0xFF333333))
        : ajustarLuz(id.corSecundaria!, escuro ? 0.10 : -0.10);
    return FlexSchemeColor(
      primary: primaria,
      primaryContainer: container,
      secondary: secundaria,
      secondaryContainer: secundariaContainer,
    );
  }

  static ThemeData claro(AppThemeScheme esquema, OrgIdentity id) {
    if (esquema == AppThemeScheme.whatsapp) {
      return FlexThemeData.light(
        colors: const FlexSchemeColor(
          primary: Color(0xFF075E54),
          primaryContainer: Color(0xFF128C7E),
          secondary: Color(0xFF25D366),
          secondaryContainer: Color(0xFF1D9344),
        ),
        surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
        blendLevel: 4,
        subThemesData: _subTemasClaro,
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        extensions: const [AlinhaStatusTokens.standard],
      );
    }

    return FlexThemeData.light(
      colors: coresPadrao(id, Brightness.light),
      surfaceMode: FlexSurfaceMode.highSurfaceLowScaffold,
      blendLevel: 2, // Quase neutro/branco
      subThemesData: _subTemasClaro,
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      useMaterial3: true,
      extensions: const [AlinhaStatusTokens.standard],
    );
  }

  static ThemeData escuro(AppThemeScheme esquema, OrgIdentity id) {
    if (esquema == AppThemeScheme.whatsapp) {
      return FlexThemeData.dark(
        colors: const FlexSchemeColor(
          primary: Color(0xFF00A884),
          primaryContainer: Color(0xFF008969),
          secondary: Color(0xFF25D366),
          secondaryContainer: Color(0xFF1D9344),
        ),
        surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
        blendLevel: 2,
        scaffoldBackground: const Color(0xFF111B21), // Zap Dark background
        surface: const Color(0xFF1F2C34), // Zap Dark cards
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 20,
          useMaterial3Typography: true,
          useM2StyleDividerInM3: true,
          inputDecoratorRadius: 14,
          inputDecoratorBorderType: FlexInputBorderType.outline,
          inputDecoratorUnfocusedHasBorder: false,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        extensions: const [AlinhaStatusTokens.standard],
      );
    }

    return FlexThemeData.dark(
      colors: coresPadrao(id, Brightness.dark),
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 0,
      scaffoldBackground: const Color(0xFF000000), // Preto total no fundo
      surface: const Color(0xFF1F2124), // Cinza escuro/Shark
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 10,
        useMaterial3Typography: true,
        useM2StyleDividerInM3: true,
        inputDecoratorRadius: 14,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorUnfocusedHasBorder: false,
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      useMaterial3: true,
      extensions: const [AlinhaStatusTokens.standard],
    );
  }
}
