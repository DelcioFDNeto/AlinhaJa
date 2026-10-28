import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants.dart';
import '../../../core/globals.dart';
import '../../../core/supabase_client.dart';
import '../services/mfa_service.dart';
import '../services/two_factor_service.dart';

/// Tela de segundo fator no login: o usuário já autenticou com senha
/// (sessão em `aal1`) e precisa digitar o código TOTP do app autenticador
/// para elevar a sessão a `aal2`. Só então a RLS libera os dados.
class Verify2FAScreen extends ConsumerStatefulWidget {
  const Verify2FAScreen({super.key});

  @override
  ConsumerState<Verify2FAScreen> createState() => _Verify2FAScreenState();
}

class _Verify2FAScreenState extends ConsumerState<Verify2FAScreen> {
  final MfaService _service = MfaService();
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isBootstrapping = true;
  String? _errorMessage;
  String? _factorId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  /// Resolve o estado do 2FA ao abrir a tela:
  ///  - já em aal2 → libera direto (cobre reload em rota protegida);
  ///  - sem fator configurado → rollout permite entrar;
  ///  - com fator → mostra o campo de código.
  Future<void> _bootstrap() async {
    final status = _service.evaluate();

    if (status == MfaGateStatus.verified) {
      Globals.is2faVerified = true;
      if (mounted) context.go('/chats');
      return;
    }

    final factorId = await _service.verifiedTotpFactorId();
    if (!mounted) return;

    if (factorId == null) {
      // Sem fator TOTP verificado: cai no 2FA por e-mail (se ativado).
      final gateOk = await TwoFactorService().emailGateSatisfied();
      if (!mounted) return;
      if (gateOk) {
        Globals.is2faVerified = true;
        context.go('/chats');
      } else {
        context.go('/verify-email-2fa');
      }
      return;
    }

    setState(() {
      _factorId = factorId;
      _isBootstrapping = false;
    });
    _focusNodes[0].requestFocus();
  }

  String get _currentCode => _controllers.map((c) => c.text).join();

  void _clearCode() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
  }

  void _handlePaste(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 6) {
      for (int i = 0; i < 6; i++) {
        _controllers[i].text = digits[i];
      }
      _focusNodes[5].requestFocus();
    }
  }

  void _onCodeFieldChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 6) {
        _handlePaste(digits);
        return;
      }
      _controllers[index].text = value.substring(value.length - 1);
    }

    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }

    // Autoenvio quando os 6 dígitos estão preenchidos.
    if (_currentCode.length == 6) {
      _verifyCode();
    }
  }

  Future<void> _verifyCode() async {
    final factorId = _factorId;
    if (factorId == null) return;

    final code = _currentCode;
    if (code.length != 6) {
      setState(() => _errorMessage = 'Digite o código completo de 6 dígitos.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _service.verifyCode(factorId: factorId, code: code);
      if (!mounted) return;
      Globals.is2faVerified = true;
      context.go('/chats');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Código incorreto ou expirado. Verifique o app autenticador.';
      });
      _clearCode();
    }
  }

  Future<void> _signOut() async {
    Globals.is2faVerified = false;
    await supabase.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isBootstrapping) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppConstants.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      size: 40,
                      color: AppConstants.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Verificação em Duas Etapas',
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Digite o código de 6 dígitos gerado pelo seu app autenticador.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppConstants.secondaryText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // OTP Input (6 caixas)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (index) {
                      return Container(
                        width: 48,
                        height: 56,
                        margin: EdgeInsets.only(
                          left: index == 0 ? 0 : 6,
                          right: index == 5 ? 0 : 6,
                        ),
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 1,
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor:
                                colorScheme.onSurface.withValues(alpha: 0.05),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: colorScheme.outline),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color:
                                    colorScheme.outline.withValues(alpha: 0.3),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppConstants.primary,
                                width: 2,
                              ),
                            ),
                          ),
                          onChanged: (value) =>
                              _onCodeFieldChanged(index, value),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),

                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppConstants.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppConstants.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 20, color: AppConstants.danger),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppConstants.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _verifyCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppConstants.primary.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Verificar Código',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  TextButton(
                    onPressed: _signOut,
                    child: Text(
                      'Voltar ao Login',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppConstants.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
