import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import 'package:alinha_ja/core/constants.dart';

/// Estado do 2FA para a sessão atual, usado para decidir o roteamento
/// pós-login e pós-restore de sessão.
enum MfaGateStatus {
  /// Sessão já está em `aal2` (segundo fator cumprido) — pode entrar no app.
  verified,

  /// Usuário tem um fator TOTP verificado, mas a sessão está em `aal1`.
  /// Precisa digitar o código do app autenticador.
  challengeRequired,

  /// Usuário ainda não configurou nenhum fator TOTP.
  /// Durante o rollout, a RLS permite acesso (anti-lockout).
  notEnrolled,
}

/// Dados de enrollment de um novo fator TOTP.
class TotpEnrollment {
  const TotpEnrollment({
    required this.factorId,
    required this.uri,
    required this.secret,
  });

  /// ID do fator recém-criado (necessário para verificar o código).
  final String factorId;

  /// URI `otpauth://...` — vira o QR code lido pelo app autenticador.
  final String uri;

  /// Segredo em texto, para entrada manual quando não dá para escanear.
  final String secret;
}

/// Wrapper fino sobre a API de MFA nativa do Supabase (`supabase.auth.mfa`).
///
/// Substitui o antigo fluxo de OTP por e-mail: aqui o segundo fator é um
/// TOTP (app autenticador) e o próprio Supabase gerencia o nível de garantia
/// (AAL) dentro do JWT. A proteção real vem da RLS que exige `aal2`.
class MfaService {
  GoTrueMFAApi get _mfa => supabase.auth.mfa;

  /// Avalia o estado do 2FA para a sessão atual (síncrono — lê o JWT local).
  MfaGateStatus evaluate() {
    final aal = _mfa.getAuthenticatorAssuranceLevel();

    if (aal.currentLevel == AuthenticatorAssuranceLevels.aal2) {
      return MfaGateStatus.verified;
    }

    // aal1 no momento: se o próximo nível alcançável é aal2, existe um fator
    // verificado e o usuário precisa completar o desafio.
    if (aal.nextLevel == AuthenticatorAssuranceLevels.aal2) {
      return MfaGateStatus.challengeRequired;
    }

    return MfaGateStatus.notEnrolled;
  }

  /// Retorna o ID do primeiro fator TOTP verificado, ou `null` se não houver.
  Future<String?> verifiedTotpFactorId() async {
    try {
      final res = await _mfa.listFactors();
      final verified = res.totp.where((f) => f.status == FactorStatus.verified);
      return verified.isEmpty ? null : verified.first.id;
    } catch (e) {
      debugPrint('[MFA] Erro ao listar fatores: $e');
      return null;
    }
  }

  /// Indica se o usuário atual já tem algum fator TOTP verificado.
  Future<bool> hasVerifiedFactor() async {
    final id = await verifiedTotpFactorId();
    return id != null;
  }

  /// Inicia o enrollment de um novo fator TOTP.
  ///
  /// Remove antes qualquer fator TOTP ainda não verificado (enrollments
  /// abandonados), evitando acúmulo de fatores "pendentes".
  Future<TotpEnrollment> enrollTotp({String issuer = AppConstants.appName}) async {
    await _cleanupUnverifiedFactors();

    final res = await _mfa.enroll(
      factorType: FactorType.totp,
      issuer: issuer,
    );

    final totp = res.totp;
    if (totp == null) {
      throw StateError('Enrollment TOTP não retornou dados do fator.');
    }

    return TotpEnrollment(
      factorId: res.id,
      uri: totp.uri,
      secret: totp.secret,
    );
  }

  /// Verifica um código de 6 dígitos contra o fator informado.
  ///
  /// Serve tanto para ATIVAR um enrollment recém-criado quanto para o
  /// step-up de `aal1` → `aal2` no login. Em ambos os casos, ao final a
  /// sessão fica em `aal2`. Lança em caso de código inválido/expirado.
  Future<void> verifyCode({
    required String factorId,
    required String code,
  }) async {
    await _mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  /// Lista todos os fatores TOTP do usuário (para a tela de segurança).
  Future<List<Factor>> listTotpFactors() async {
    try {
      final res = await _mfa.listFactors();
      return res.totp;
    } catch (e) {
      debugPrint('[MFA] Erro ao listar fatores TOTP: $e');
      return [];
    }
  }

  /// Remove um fator (desativa o 2FA daquele fator).
  Future<void> unenroll(String factorId) async {
    await _mfa.unenroll(factorId);
  }

  /// Remove fatores TOTP que ficaram em estado `unverified` (enrollments
  /// abandonados sem confirmação do código).
  Future<void> _cleanupUnverifiedFactors() async {
    try {
      final res = await _mfa.listFactors();
      for (final f in res.totp) {
        if (f.status == FactorStatus.unverified) {
          await _mfa.unenroll(f.id);
        }
      }
    } catch (e) {
      debugPrint('[MFA] Erro ao limpar fatores não verificados: $e');
    }
  }
}
