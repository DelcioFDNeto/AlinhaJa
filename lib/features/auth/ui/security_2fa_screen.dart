import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants.dart';
import '../../../core/globals.dart';
import '../services/mfa_service.dart';
import '../services/two_factor_service.dart';

/// Tela de gerenciamento do 2FA (app autenticador / TOTP).
///
/// Substitui a antiga tela de "Dispositivos Confiáveis" (modelo de OTP por
/// e-mail, descontinuado). Mostra o status atual, permite configurar quando
/// não há fator e remover quando há.
class Security2FAScreen extends ConsumerStatefulWidget {
  const Security2FAScreen({super.key});

  @override
  ConsumerState<Security2FAScreen> createState() => _Security2FAScreenState();
}

class _Security2FAScreenState extends ConsumerState<Security2FAScreen> {
  final MfaService _service = MfaService();
  final TwoFactorService _twoFactorService = TwoFactorService();

  bool _isLoading = true;
  bool _email2faEnabled = false;
  bool _email2faBusy = false;
  List<Factor> _factors = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final factors = await _service.listTotpFactors();
    final emailEnabled = await _twoFactorService.isEmail2faEnabled();
    if (!mounted) return;
    setState(() {
      _factors = factors.where((f) => f.status == FactorStatus.verified).toList();
      _email2faEnabled = emailEnabled;
      _isLoading = false;
    });
  }

  Future<void> _toggleEmail2fa(bool enable) async {
    if (_email2faBusy) return;

    if (!enable) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Desativar código por e-mail?'),
          content: const Text(
            'Sua conta deixará de exigir o código enviado por e-mail em '
            'dispositivos novos. Você pode reativar a qualquer momento.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppConstants.danger),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Desativar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _email2faBusy = true);
    try {
      await _twoFactorService.setEmail2faEnabled(enable);
      if (!mounted) return;
      setState(() => _email2faEnabled = enable);
      Globals.showSuccessSnackBar(enable
          ? '2FA por e-mail ativado. Este dispositivo já é confiável.'
          : '2FA por e-mail desativado.');
    } catch (e) {
      if (!mounted) return;
      Globals.showErrorSnackBar(
          'Não foi possível alterar o 2FA por e-mail. Tente novamente.');
    } finally {
      if (mounted) setState(() => _email2faBusy = false);
    }
  }

  Future<void> _configure() async {
    await context.push('/mfa-setup');
    if (mounted) _load();
  }

  Future<void> _remove(Factor factor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover 2FA?'),
        content: const Text(
          'Sua conta deixará de exigir o código do app autenticador ao entrar. '
          'Você pode reconfigurar a qualquer momento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.unenroll(factor.id);
      if (!mounted) return;
      Globals.showSuccessSnackBar('2FA removido.');
      _load();
    } catch (e) {
      if (!mounted) return;
      Globals.showErrorSnackBar('Não foi possível remover. Tente novamente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasFactor = _factors.isNotEmpty;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Segurança e 2FA',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        hasFactor
                            ? _buildActive(colorScheme)
                            : _buildInactive(colorScheme),
                        const SizedBox(height: 32),
                        Text(
                          'Código por e-mail',
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Quando ativado, o login em dispositivos novos exige '
                          'um código enviado ao seu e-mail, dispensado em '
                          'dispositivos confiáveis por 30 dias.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildEmailToggle(colorScheme),
                        if (_email2faEnabled) ...[
                          const SizedBox(height: 12),
                          _buildTrustedDevicesTile(colorScheme),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildEmailToggle(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppConstants.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.mark_email_read_rounded,
                color: AppConstants.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exigir código por e-mail',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _email2faEnabled
                      ? 'Ativo: dispositivos novos precisam do código'
                      : 'Inativo: o login pede apenas a senha',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _email2faBusy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Switch(
                  value: _email2faEnabled,
                  activeThumbColor: AppConstants.primary,
                  onChanged: _toggleEmail2fa,
                ),
        ],
      ),
    );
  }

  Widget _buildTrustedDevicesTile(ColorScheme colorScheme) {
    return InkWell(
      onTap: () => context.push('/trusted-devices'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppConstants.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.devices_rounded,
                  color: AppConstants.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dispositivos confiáveis',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Gerencie onde o código por e-mail não é pedido',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(ColorScheme colorScheme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 20, color: AppConstants.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInactive(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoCard(
          colorScheme,
          'A verificação em duas etapas adiciona uma camada extra de segurança: '
          'além da senha, será pedido um código do seu app autenticador ao entrar.',
        ),
        const SizedBox(height: 32),
        Icon(Icons.shield_outlined,
            size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        Text(
          '2FA não configurado',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Use Google Authenticator, Authy ou Microsoft Authenticator.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _configure,
            icon: const Icon(Icons.add_moderator_rounded),
            label: Text(
              'Configurar 2FA',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActive(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoCard(
          colorScheme,
          'A verificação em duas etapas está ativa. A cada novo login será pedido '
          'o código de 6 dígitos do seu app autenticador.',
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.verified_user_rounded,
                size: 22, color: AppConstants.success),
            const SizedBox(width: 8),
            Text(
              '2FA Ativado',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._factors.map((f) => _buildFactorTile(colorScheme, f)),
      ],
    );
  }

  Widget _buildFactorTile(ColorScheme colorScheme, Factor factor) {
    final name = (factor.friendlyName?.isNotEmpty ?? false)
        ? factor.friendlyName!
        : 'App Autenticador';
    final date = factor.createdAt.toLocal();
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppConstants.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.smartphone_rounded,
                color: AppConstants.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ativado em $dateStr',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _remove(factor),
            child: Text(
              'Remover',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: AppConstants.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
