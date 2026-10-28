import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/constants.dart';

import 'package:alinha_ja/core/supabase_client.dart';

import 'package:alinha_ja/features/auth/providers/auth_provider.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:alinha_ja/core/globals.dart';
import '../services/mfa_service.dart';
import '../services/two_factor_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('remembered_email');
    if (savedEmail != null && savedEmail.isNotEmpty) {
      if (mounted) {
        setState(() {
          _emailCtrl.text = savedEmail;
          _rememberMe = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = ref.read(authRepositoryProvider);
    // Toda nova tentativa de login começa sem 2FA cumprido.
    Globals.is2faVerified = false;
    setState(() => _isLoading = true);

    try {
      await auth.signIn(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final row = await supabase
            .from('users')
            .select('is_active, must_change_password')
            .eq('id', userId)
            .maybeSingle();

        if (row != null && row['is_active'] == false) {
          await supabase.auth.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Sua conta ainda não foi aprovada pelo administrador. Aguarde a ativação.'),
                backgroundColor: AppConstants.danger,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }

        // Senha provisória (seed): obriga troca antes de qualquer acesso.
        if (row != null && row['must_change_password'] == true) {
          if (mounted) context.go('/force-change-password');
          return;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remembered_email', _emailCtrl.text.trim());
      } else {
        await prefs.remove('remembered_email');
      }

      // Avaliar o segundo fator (MFA nativo / AAL do Supabase).
      final status = MfaService().evaluate();
      if (!mounted) return;

      switch (status) {
        case MfaGateStatus.verified:
          // Sessão já em aal2 (ex.: sessão anterior preservada).
          Globals.is2faVerified = true;
          context.go('/chats');
        case MfaGateStatus.challengeRequired:
          // Tem fator TOTP mas sessão em aal1: exige o código.
          Globals.is2faVerified = false;
          context.go('/verify-2fa');
        case MfaGateStatus.notEnrolled:
          // Sem app autenticador: cai no segundo fator por e-mail
          // (apenas se o usuário ativou o 2FA por e-mail).
          final gateOk = await TwoFactorService().emailGateSatisfied();
          if (!mounted) return;
          if (gateOk) {
            Globals.is2faVerified = true;
            context.go('/chats');
          } else {
            Globals.is2faVerified = false;
            context.go('/verify-email-2fa');
          }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e.toString())),
          backgroundColor: AppConstants.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String msg) {
    if (msg.contains('Invalid login')) return 'E-mail ou senha incorretos.';
    if (msg.contains('already registered')) {
      return 'Este e-mail já está cadastrado.';
    }
    if (msg.contains('banned') || msg.contains('User is banned')) {
      return 'Sua conta está aguardando aprovação do TI. Tente novamente após a liberação.';
    }
    return 'Erro: $msg';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLargeScreen = constraints.maxWidth > 900;
          final isSmallPhone = constraints.maxHeight < 650;

          if (isLargeScreen) {
            // Layout Split-Screen para Desktop/PWA
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF000000), // Preto Base

                    ),
                    child: Stack(
                      children: [
                        // Glassmorphism Blobs
                        Positioned(
                          top: -100,
                          left: -100,
                          child: Container(
                            width: 500,
                            height: 500,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  AppConstants.primary.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -200,
                          right: -100,
                          child: Container(
                            width: 600,
                            height: 600,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFA51412)
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        // Conteúdo Institucional
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(64.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/logo.png',
                                  height: 80,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Icon(Icons.chat,
                                      size: 80, color: primaryColor),
                                ),
                                const SizedBox(height: 48),
                                Text(
                                  'Comunicação\ne Logística.',
                                  style: GoogleFonts.outfit(
                                    fontSize: 64,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                    color: Colors.white,
                                    letterSpacing: -1,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'A plataforma unificada desenvolvida para impulsionar a operação corporativa da sua empresa.',
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    color: Colors.white70,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Container(
                    color: isDark ? const Color(0xFF111111) : Colors.white,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: _buildLoginForm(
                            theme, isDark, primaryColor, isSmallPhone,
                            isDesktop: true),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          // Mobile View Glassmorphism
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [const Color(0xFF000000), const Color(0xFF111111)]
                    : [
                        theme.colorScheme.primary.withValues(alpha: 0.05),
                        theme.colorScheme.surface
                      ],
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: isSmallPhone ? 24 : 48,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _buildLoginCard(
                        theme, isDark, primaryColor, isSmallPhone),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Wrapper do Form (Card Glassmorphism para Mobile)
  Widget _buildLoginCard(
      ThemeData theme, bool isDark, Color primaryColor, bool isSmallPhone) {
    return Container(
      padding: EdgeInsets.all(isSmallPhone ? 24 : 32),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1F2124).withValues(alpha: 0.7)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: _buildLoginForm(theme, isDark, primaryColor, isSmallPhone,
          isDesktop: false),
    );
  }

  // O Form Base (Campos e Botões) -> Usado tanto no Desktop Limpo quanto no Mobile Card
  Widget _buildLoginForm(
      ThemeData theme, bool isDark, Color primaryColor, bool isSmallPhone,
      {required bool isDesktop}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isDesktop) _buildLogo(theme, primaryColor),
        if (!isDesktop) const SizedBox(height: 24),
        _buildTitle(theme, isDesktop),
        const SizedBox(height: 8),
        _buildSubtitle(theme),
        const SizedBox(height: 40),
        _buildEmailField(theme, primaryColor),
        const SizedBox(height: 16),
        _buildPasswordField(theme, primaryColor),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildRememberMe(theme),
            _buildForgotPassword(theme, primaryColor),
          ],
        ),
        const SizedBox(height: 32),
        _buildLoginButton(theme, primaryColor),
        const SizedBox(height: 24),
        _buildSignupLink(theme),
      ],
    );
  }

  Widget _buildLogo(ThemeData theme, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
      child: Center(
        child: Image.asset('assets/images/logo.png',
            height: 52,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.chat_rounded, size: 52, color: primaryColor)),
      ),
    );
  }

  Widget _buildTitle(ThemeData theme, bool isDesktop) {
    return Text(isDesktop ? 'Acessar Conta' : 'Bem-vindo(a)',
        textAlign: isDesktop ? TextAlign.left : TextAlign.center,
        style: GoogleFonts.outfit(
            fontSize: isDesktop ? 32 : 28,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface));
  }

  Widget _buildSubtitle(ThemeData theme) {
    return Text('Entre com suas credenciais corporativas.',
        textAlign: TextAlign.left,
        style: GoogleFonts.inter(
            fontSize: 15, color: theme.colorScheme.onSurfaceVariant));
  }

  Widget _buildEmailField(ThemeData theme, Color primaryColor) {
    return TextField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      style:
          GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 16),
      decoration: InputDecoration(
        hintText: 'E-mail corporativo',
        hintStyle: GoogleFonts.inter(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
        prefixIcon:
            Icon(Icons.business_outlined, color: primaryColor, size: 22),
        filled: true,
        fillColor:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.2))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: primaryColor, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
    );
  }

  Widget _buildPasswordField(ThemeData theme, Color primaryColor) {
    return TextField(
      controller: _passwordCtrl,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      style:
          GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Senha',
        hintStyle: GoogleFonts.inter(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
        prefixIcon:
            Icon(Icons.lock_outline_rounded, color: primaryColor, size: 22),
        suffixIcon: IconButton(
            icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: theme.colorScheme.onSurfaceVariant,
                size: 20),
            onPressed: () => setState(() => _obscure = !_obscure)),
        filled: true,
        fillColor:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.2))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: primaryColor, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
    );
  }

  Widget _buildForgotPassword(ThemeData theme, Color primaryColor) {
    return TextButton(
      onPressed: () => _showForgotPasswordDialog(context, theme, primaryColor),
      style: TextButton.styleFrom(
          padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
      child: Text('Esqueceu a senha?',
          style: GoogleFonts.inter(
              fontSize: 14, color: primaryColor, fontWeight: FontWeight.w600)),
    );
  }

  void _showForgotPasswordDialog(
      BuildContext context, ThemeData theme, Color primaryColor) {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    bool isSending = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: theme.colorScheme.surface,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Recuperar Senha',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Digite o e-mail associado à sua conta para receber o link de redefinição.',
                      style: GoogleFonts.inter(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      hintText: 'E-mail corporativo',
                      prefixIcon: Icon(Icons.email_outlined,
                          color: primaryColor, size: 20),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSending ? null : () => Navigator.of(context).pop(),
                  child: Text('Cancelar',
                      style: GoogleFonts.inter(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final email = emailCtrl.text.trim();
                          if (email.isEmpty) return;

                          setDialogState(() => isSending = true);

                          try {
                            await supabase.auth.resetPasswordForEmail(
                              email,
                              redirectTo: kIsWeb
                                  ? '${AppEnv.appBaseUrl}/update-password'
                                  : 'alinhaja://update-password',
                            );
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Um link de redefinição foi enviado para $email.'),
                                  backgroundColor: AppConstants.primary,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              setDialogState(() => isSending = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('Erro ao enviar e-mail: ${e.toString()}'),
                                  backgroundColor: AppConstants.danger,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: isSending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Enviar link',
                          style:
                              GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildRememberMe(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: _rememberMe,
            onChanged: (val) {
              setState(() => _rememberMe = val ?? false);
            },
            activeColor: theme.colorScheme.primary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            side: BorderSide(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Lembrar email',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton(ThemeData theme, Color primaryColor) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 3.0, color: Colors.white))
            : Text('Entrar',
                style: GoogleFonts.inter(
                    fontSize: 18, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildSignupLink(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Novo por aqui?',
            style: GoogleFonts.inter(
                fontSize: 15, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(width: 4),
        TextButton(
          onPressed: () => context.push('/signup'),
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
          child: Text('Cadastre-se',
              style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary)),
        ),
      ],
    );
  }
}

