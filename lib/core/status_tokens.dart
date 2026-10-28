import 'package:flutter/material.dart';

import 'package:alinha_ja/core/status_role.dart';

/// Tokens de cor por papel de status ([StatusRole]), expostos como
/// [ThemeExtension] para que cada tenant (white-label) troque a paleta no
/// [ThemeData] sem que as telas conheçam cores cruas. Anexado por esquema
/// visual em `app.dart`.
@immutable
class AlinhaStatusTokens extends ThemeExtension<AlinhaStatusTokens> {
  const AlinhaStatusTokens({
    required this.success,
    required this.info,
    required this.warning,
    required this.danger,
    required this.neutral,
    required this.highlight,
    required this.progress,
    required this.pending,
  });

  final Color success;
  final Color info;
  final Color warning;
  final Color danger;
  final Color neutral;
  final Color highlight;
  final Color progress;
  final Color pending;

  /// Paleta padrão — equivale, 1:1, às cores Material usadas antes da
  /// extração dos tokens. É o ponto de partida do white-label: um tenant
  /// sobrescreve só os papéis que quiser via [copyWith].
  static const standard = AlinhaStatusTokens(
    success: Colors.green,
    info: Colors.blue,
    warning: Colors.orange,
    danger: Colors.red,
    neutral: Colors.grey,
    highlight: Colors.purple,
    progress: Colors.teal,
    pending: Colors.amber,
  );

  Color color(StatusRole role) => switch (role) {
        StatusRole.success => success,
        StatusRole.info => info,
        StatusRole.warning => warning,
        StatusRole.danger => danger,
        StatusRole.neutral => neutral,
        StatusRole.highlight => highlight,
        StatusRole.progress => progress,
        StatusRole.pending => pending,
      };

  @override
  AlinhaStatusTokens copyWith({
    Color? success,
    Color? info,
    Color? warning,
    Color? danger,
    Color? neutral,
    Color? highlight,
    Color? progress,
    Color? pending,
  }) =>
      AlinhaStatusTokens(
        success: success ?? this.success,
        info: info ?? this.info,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        neutral: neutral ?? this.neutral,
        highlight: highlight ?? this.highlight,
        progress: progress ?? this.progress,
        pending: pending ?? this.pending,
      );

  @override
  AlinhaStatusTokens lerp(ThemeExtension<AlinhaStatusTokens>? other, double t) {
    if (other is! AlinhaStatusTokens) return this;
    return AlinhaStatusTokens(
      success: Color.lerp(success, other.success, t)!,
      info: Color.lerp(info, other.info, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      progress: Color.lerp(progress, other.progress, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
    );
  }
}

/// Açúcar para resolver a cor de um [StatusRole] no tema atual, com
/// fallback para a paleta padrão caso a extensão não esteja registrada.
extension StatusTokensX on BuildContext {
  AlinhaStatusTokens get statusTokens =>
      Theme.of(this).extension<AlinhaStatusTokens>() ??
      AlinhaStatusTokens.standard;
}
