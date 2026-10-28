import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants.dart';
import '../../../core/globals.dart';
import '../../../core/supabase_client.dart';
import '../providers/two_factor_provider.dart';

class VerifyEmail2FAScreen extends ConsumerStatefulWidget {
  const VerifyEmail2FAScreen({super.key});

  @override
  ConsumerState<VerifyEmail2FAScreen> createState() => _VerifyEmail2FAScreenState();
}

class _VerifyEmail2FAScreenState extends ConsumerState<VerifyEmail2FAScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  String? _errorMessage;
  int _resendCooldown = 0;
  int _expirySeconds = 600;
  int _attemptsLeft = 5;
  String _maskedEmail = '';

  Timer? _expiryTimer;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _sendInitialCode();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _expiryTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendInitialCode() async {
    try {
      final service = ref.read(twoFactorServiceProvider);
      final result = await service.requestCode();
      if (mounted) {
        setState(() {
          _maskedEmail = result['masked_email'] as String? ?? '';
        });
        _startExpiryTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao enviar código. Tente novamente.';
        });
      }
    }
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    setState(() {
      _expirySeconds = 600;
    });
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_expirySeconds > 0) {
          _expirySeconds--;
        } else {
          timer.cancel();
          _errorMessage = 'Código expirado. Solicite um novo código.';
        }
      });
    });
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() {
      _resendCooldown = 60;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendCooldown > 0) {
          _resendCooldown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  String get _formattedExpiry {
    final minutes = (_expirySeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_expirySeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _currentCode {
    return _controllers.map((c) => c.text).join();
  }

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
      // Handle paste
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

    setState(() {
      _errorMessage = null;
    });
  }

  Future<void> _verifyCode() async {
    final code = _currentCode;
    if (code.length != 6) {
      setState(() {
        _errorMessage = 'Digite o código completo de 6 dígitos.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(twoFactorServiceProvider);
      final result = await service.verifyCode(code);

      if (!mounted) return;

      switch (result) {
        case 'valid':
          // Libera a RLS para esta sessão (dispositivo acabou de virar
          // confiável no verify_2fa_code).
          await service.registerSessionVerified();
          if (!mounted) return;
          Globals.is2faVerified = true;
          context.go('/chats');
          break;
        case 'invalid':
          setState(() {
            _attemptsLeft--;
            if (_attemptsLeft <= 0) {
              _errorMessage =
                  'Número máximo de tentativas atingido. Solicite um novo código.';
            } else {
              _errorMessage =
                  'Código inválido. Você tem $_attemptsLeft tentativa${_attemptsLeft == 1 ? '' : 's'} restante${_attemptsLeft == 1 ? '' : 's'}.';
            }
          });
          _clearCode();
          break;
        case 'blocked':
          setState(() {
            _errorMessage =
                'Sua conta foi temporariamente bloqueada por excesso de tentativas. Tente novamente mais tarde.';
          });
          break;
        case 'expired':
          setState(() {
            _errorMessage =
                'Código expirado. Solicite um novo código.';
          });
          break;
        default:
          setState(() {
            _errorMessage = 'Erro desconhecido. Tente novamente.';
          });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao verificar código. Tente novamente.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resendCode() async {
    if (_resendCooldown > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(twoFactorServiceProvider);
      final result = await service.requestCode();

      if (mounted) {
        setState(() {
          _maskedEmail = result['masked_email'] as String? ?? _maskedEmail;
          _attemptsLeft = 5;
        });
        _clearCode();
        _startExpiryTimer();
        _startResendCooldown();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao reenviar código. Tente novamente.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    Globals.is2faVerified = false;
    await supabase.auth.signOut();
    if (mounted) {
      context.go('/login');
    }
  }

  bool get _isBlocked {
    return _attemptsLeft <= 0 ||
        (_errorMessage != null &&
            _errorMessage!.contains('bloqueada'));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                  // Shield icon
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

                  // Title
                  Text(
                    'Verificação de Segurança',
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Subtitle
                  Text(
                    _maskedEmail.isNotEmpty
                        ? 'Enviamos um código de 6 dígitos para $_maskedEmail'
                        : 'Enviando código de verificação...',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppConstants.secondaryText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // OTP Input
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
                              borderSide: BorderSide(
                                color: colorScheme.outline,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: colorScheme.outline
                                    .withValues(alpha: 0.3),
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
                  const SizedBox(height: 20),

                  // Timer
                  if (_expirySeconds > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: _expirySeconds <= 60
                              ? AppConstants.danger
                              : AppConstants.secondaryText,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Código expira em $_formattedExpiry',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _expirySeconds <= 60
                                ? AppConstants.danger
                                : AppConstants.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 24),

                  // Error Display
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
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 20,
                            color: AppConstants.danger,
                          ),
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

                  // Verify Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed:
                          (_isLoading || _isBlocked) ? null : _verifyCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppConstants.primary.withValues(alpha: 0.4),
                        disabledForegroundColor:
                            Colors.white.withValues(alpha: 0.6),
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
                  const SizedBox(height: 24),

                  // Resend Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Não recebeu o código?',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppConstants.secondaryText,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _isResending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppConstants.primary,
                              ),
                            )
                          : TextButton(
                              onPressed:
                                  _resendCooldown > 0 ? null : _resendCode,
                              child: Text(
                                _resendCooldown > 0
                                    ? 'Reenviar (${_resendCooldown}s)'
                                    : 'Reenviar',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _resendCooldown > 0
                                      ? AppConstants.secondaryText
                                      : AppConstants.primary,
                                ),
                              ),
                            ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Sign Out
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



