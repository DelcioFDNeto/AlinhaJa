import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants.dart';
import '../../../core/globals.dart';
import '../services/mfa_service.dart';

/// Tela de configuração (enrollment) do 2FA por app autenticador (TOTP).
///
/// Dois contextos de uso:
///  - `isOnboarding = true`: aberta no fluxo de login quando o 2FA é
///    obrigatório e o usuário ainda não configurou. Ao concluir, vai para
///    `/chats`.
///  - `isOnboarding = false` (padrão): aberta a partir das Configurações.
///    Ao concluir, dá `pop(true)`.
class MfaEnrollmentScreen extends ConsumerStatefulWidget {
  const MfaEnrollmentScreen({super.key, this.isOnboarding = false});

  final bool isOnboarding;

  @override
  ConsumerState<MfaEnrollmentScreen> createState() =>
      _MfaEnrollmentScreenState();
}

class _MfaEnrollmentScreenState extends ConsumerState<MfaEnrollmentScreen> {
  final MfaService _service = MfaService();
  final TextEditingController _codeCtrl = TextEditingController();

  TotpEnrollment? _enrollment;
  bool _isLoading = true;
  bool _isVerifying = false;
  String? _errorMessage;
  bool _secretVisible = false;

  @override
  void initState() {
    super.initState();
    _startEnrollment();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _startEnrollment() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final enrollment = await _service.enrollTotp();
      if (!mounted) return;
      setState(() {
        _enrollment = enrollment;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Não foi possível iniciar a configuração. Tente novamente.';
      });
    }
  }

  Future<void> _verify() async {
    final enrollment = _enrollment;
    if (enrollment == null) return;

    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Digite o código de 6 dígitos do app.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      await _service.verifyCode(factorId: enrollment.factorId, code: code);
      if (!mounted) return;

      // Enrollment confirmado: a sessão já está em aal2.
      Globals.is2faVerified = true;

      if (widget.isOnboarding) {
        context.go('/chats');
      } else {
        Navigator.of(context).pop(true);
        Globals.showSuccessSnackBar('2FA ativado com sucesso.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage =
            'Código incorreto ou expirado. Confira o app autenticador e tente de novo.';
      });
    }
  }

  Future<void> _copySecret() async {
    final secret = _enrollment?.secret;
    if (secret == null) return;
    await Clipboard.setData(ClipboardData(text: secret));
    Globals.showSuccessSnackBar('Chave copiada.');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Configurar 2FA',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: !widget.isOnboarding,
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _buildContent(colorScheme),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    final enrollment = _enrollment;

    if (enrollment == null) {
      return Column(
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.error_outline_rounded,
              size: 48, color: AppConstants.danger),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Erro ao carregar a configuração.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: AppConstants.secondaryText),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _startEnrollment,
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '1. Escaneie o QR Code',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Abra um app autenticador (Google Authenticator, Authy, Microsoft Authenticator) e escaneie o código abaixo.',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: AppConstants.secondaryText,
          ),
        ),
        const SizedBox(height: 20),

        // QR Code (fundo branco fixo para leitura por qualquer câmera).
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: enrollment.uri,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Entrada manual do segredo (fallback).
        Text(
          'Não consegue escanear? Insira a chave manualmente:',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppConstants.secondaryText,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _copySecret,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _secretVisible
                        ? enrollment.secret
                        : '•' * enrollment.secret.length,
                    style: GoogleFonts.robotoMono(
                      fontSize: 14,
                      letterSpacing: 1,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _secretVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _secretVisible = !_secretVisible),
                ),
                const Icon(Icons.copy_rounded, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),

        Text(
          '2. Digite o código gerado',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
            color: colorScheme.onSurface,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            filled: true,
            fillColor: colorScheme.onSurface.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: AppConstants.primary, width: 2),
            ),
          ),
          onSubmitted: (_) => _verify(),
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() => _errorMessage = null);
            }
          },
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 18, color: AppConstants.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppConstants.danger),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),

        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _isVerifying ? null : _verify,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: _isVerifying
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(
                    'Ativar 2FA',
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
