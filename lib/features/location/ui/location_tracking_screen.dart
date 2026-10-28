import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/location/providers/location_provider.dart';
import 'package:alinha_ja/core/globals.dart';
import 'package:intl/intl.dart';

/// Tela de configuração do rastreamento de localização.
///
/// Integra o fluxo de consentimento LGPD: o usuário precisa consentir
/// explicitamente antes de poder ativar o rastreamento. A revogação
/// desliga o rastreamento automaticamente.
class LocationTrackingScreen extends ConsumerStatefulWidget {
  const LocationTrackingScreen({super.key});

  @override
  ConsumerState<LocationTrackingScreen> createState() =>
      _LocationTrackingScreenState();
}

class _LocationTrackingScreenState
    extends ConsumerState<LocationTrackingScreen> {
  int _selectedInterval = 5;
  bool _isLoading = false;
  bool _isConsentLoading = false;

  final List<int> _intervalOptions = [1, 2, 5, 10, 15, 30];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userAsync = ref.watch(currentUserProvider);
    final isTracking = ref.watch(locationTrackingActiveProvider);
    final lastLocation = ref.watch(lastKnownLocationProvider);
    final consentAsync = ref.watch(gpsConsentProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Rastreamento',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Erro ao carregar perfil')),
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Usuário não identificado'));
          }

          return consentAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: theme.colorScheme.error),
                    const SizedBox(height: 16),
                    Text('Erro ao consultar consentimento',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('$e',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: theme.colorScheme.outline)),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(gpsConsentProvider),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
            data: (consent) {
              final consentActive =
                  consent?['consent_active'] as bool? ?? false;

              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // ── Ícone principal ──
                  _buildStatusHeader(theme, isTracking, lastLocation),

                  const Divider(indent: 16, endIndent: 16),

                  // ── Card de consentimento LGPD ──
                  _buildConsentSection(theme, consent, consentActive),

                  const Divider(height: 32, indent: 16, endIndent: 16),

                  // ── Toggle de rastreamento ──
                  _SectionHeader(title: 'Controle', theme: theme),

                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.gps_fixed_rounded,
                          color: Colors.blue),
                    ),
                    title: const Text('Ativar Rastreamento',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      !consentActive
                          ? 'Consentimento necessário para ativar'
                          : isTracking
                              ? 'Enviando localização a cada $_selectedInterval min'
                              : 'Localização não está sendo rastreada',
                      style: TextStyle(
                          color: theme.colorScheme.outline, fontSize: 13),
                    ),
                    value: isTracking,
                    onChanged: !consentActive || _isLoading
                        ? null
                        : (value) => _toggleTracking(value),
                  ),

                  // ── Frequência ──
                  const SizedBox(height: 8),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.timer_outlined,
                          color: Colors.purple),
                    ),
                    title: const Text('Frequência de Atualização',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'A cada $_selectedInterval minutos',
                      style: TextStyle(
                          color: theme.colorScheme.outline, fontSize: 13),
                    ),
                    trailing: DropdownButton<int>(
                      value: _selectedInterval,
                      underline: const SizedBox.shrink(),
                      borderRadius: BorderRadius.circular(12),
                      items: _intervalOptions.map((min) {
                        return DropdownMenuItem(
                          value: min,
                          child: Text('$min min'),
                        );
                      }).toList(),
                      onChanged: isTracking || !consentActive
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _selectedInterval = value);
                              }
                            },
                    ),
                  ),

                  const Divider(height: 32, indent: 16, endIndent: 16),

                  // ── Captura manual ──
                  _SectionHeader(title: 'Ações', theme: theme),

                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.my_location_rounded,
                          color: Colors.teal),
                    ),
                    title: const Text('Capturar Localização Agora',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      !consentActive
                          ? 'Consentimento necessário'
                          : 'Enviar posição imediatamente',
                      style: TextStyle(
                          color: theme.colorScheme.outline, fontSize: 13),
                    ),
                    trailing: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.send_rounded,
                            color: consentActive ? null : theme.disabledColor),
                    onTap:
                        _isLoading || !consentActive ? null : _captureNow,
                  ),

                  const SizedBox(height: 16),

                  // ── Info de bateria ──
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Card(
                      color: theme.colorScheme.surfaceContainerHigh
                          .withValues(alpha: 0.5),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.battery_std_rounded,
                                color: theme.colorScheme.outline, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'O rastreamento consome aproximadamente 5-10% '
                                'de bateria por dia quando ativo.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ── Status header ──────────────────────────────────────────────

  Widget _buildStatusHeader(
    ThemeData theme,
    bool isTracking,
    Map<String, dynamic>? lastLocation,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isTracking
                  ? Colors.green.withValues(alpha: 0.15)
                  : theme.colorScheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isTracking
                  ? Icons.location_on_rounded
                  : Icons.location_off_rounded,
              size: 48,
              color: isTracking
                  ? Colors.green
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isTracking ? 'Rastreamento Ativo' : 'Rastreamento Inativo',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isTracking ? Colors.green : null,
            ),
          ),
          if (lastLocation != null) ...[
            const SizedBox(height: 4),
            Text(
              'Lat: ${(lastLocation['latitude'] as double?)?.toStringAsFixed(5) ?? '-'}, '
              'Lng: ${(lastLocation['longitude'] as double?)?.toStringAsFixed(5) ?? '-'}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.outline,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Seção de consentimento LGPD ────────────────────────────────

  Widget _buildConsentSection(
    ThemeData theme,
    Map<String, dynamic>? consent,
    bool consentActive,
  ) {
    final consentGivenAt = consent?['consent_given_at'] as String?;
    final pontos = consent?['pontos_coletados'] as int? ?? 0;
    final version = consent?['consent_version'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'Consentimento LGPD', theme: theme),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: consentActive
                    ? Colors.green.withValues(alpha: 0.4)
                    : theme.colorScheme.outline.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            color: consentActive
                ? Colors.green.withValues(alpha: 0.06)
                : theme.colorScheme.surfaceContainerHigh
                    .withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Status row ──
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: consentActive
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          consentActive
                              ? Icons.verified_user_rounded
                              : Icons.shield_outlined,
                          color: consentActive ? Colors.green : Colors.orange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              consentActive
                                  ? 'Consentimento Ativo'
                                  : 'Consentimento Necessário',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: consentActive
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                            if (consentActive && consentGivenAt != null)
                              Text(
                                'Concedido em ${_formatDate(consentGivenAt)}'
                                '${version != null ? ' · $version' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (consentActive)
                        Text(
                          '$pontos pts',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.outline,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── Informação da finalidade ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Finalidade: Acompanhamento de equipe em atividade '
                            'externa durante a jornada de trabalho. Seus dados '
                            'de localização são coletados apenas enquanto o '
                            'rastreamento estiver ativo e retidos por até 7 dias. '
                            'Você pode revogar o consentimento a qualquer momento.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Botões de ação ──
                  if (!consentActive)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isConsentLoading ? null : _grantConsent,
                        icon: _isConsentLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_outline_rounded,
                                size: 20),
                        label: const Text('Eu consinto com a coleta'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                _isConsentLoading ? null : _revokeConsent,
                            icon: _isConsentLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.shield_outlined, size: 18),
                            label: const Text('Revogar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange.shade700,
                              side: BorderSide(
                                  color: Colors.orange.shade300, width: 1.2),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        if (pontos > 0) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isConsentLoading
                                  ? null
                                  : _confirmDeleteHistory,
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 18),
                              label: const Text('Apagar Histórico'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                                side: BorderSide(
                                    color: theme.colorScheme.error
                                        .withValues(alpha: 0.4),
                                    width: 1.2),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                  // ── Base legal ──
                  const SizedBox(height: 12),
                  Text(
                    'LGPD Art. 6º, VI — Transparência · Art. 18 — Direitos do Titular',
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.outline.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ações ──────────────────────────────────────────────────────

  Future<void> _grantConsent() async {
    setState(() => _isConsentLoading = true);
    try {
      final repo = ref.read(locationRepositoryProvider);
      await repo.grantConsent();
      ref.invalidate(gpsConsentProvider);
      if (mounted) {
        Globals.showSuccessSnackBar(
            '✅ Consentimento registrado com sucesso.');
      }
    } catch (e) {
      debugPrint('❌ Erro ao registrar consentimento: $e');
      if (mounted) {
        Globals.showErrorSnackBar('Erro ao registrar consentimento.');
      }
    } finally {
      if (mounted) setState(() => _isConsentLoading = false);
    }
  }

  Future<void> _revokeConsent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revogar consentimento?'),
        content: const Text(
          'O rastreamento será desligado imediatamente. '
          'Você poderá consentir novamente a qualquer momento.\n\n'
          'Seu histórico de localização existente será preservado — '
          'use "Apagar Histórico" se quiser removê-lo.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
            ),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isConsentLoading = true);
    try {
      // Parar tracking local antes de revogar no banco
      final isTracking = ref.read(locationTrackingActiveProvider);
      if (isTracking) {
        final controller = ref.read(locationControllerProvider);
        await controller.stopTracking();
      }

      final repo = ref.read(locationRepositoryProvider);
      await repo.revokeConsent();
      ref.invalidate(gpsConsentProvider);
      if (mounted) {
        Globals.showSuccessSnackBar(
            'Consentimento revogado. Rastreamento desligado.');
      }
    } catch (e) {
      debugPrint('❌ Erro ao revogar consentimento: $e');
      if (mounted) {
        Globals.showErrorSnackBar('Erro ao revogar consentimento.');
      }
    } finally {
      if (mounted) setState(() => _isConsentLoading = false);
    }
  }

  Future<void> _confirmDeleteHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_forever_rounded,
            size: 40, color: Theme.of(ctx).colorScheme.error),
        title: const Text('Apagar todo o histórico?'),
        content: const Text(
          'Esta ação é irreversível. Todos os pontos de localização '
          'coletados serão permanentemente apagados.\n\n'
          'Este é seu direito conforme LGPD Art. 18, VI — '
          'eliminação de dados pessoais.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Apagar Tudo'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isConsentLoading = true);
    try {
      final repo = ref.read(locationRepositoryProvider);
      final deleted = await repo.deleteMyLocations();
      ref.invalidate(gpsConsentProvider);
      if (mounted) {
        Globals.showSuccessSnackBar(
            '🗑️ $deleted ponto(s) de localização removido(s).');
      }
    } catch (e) {
      debugPrint('❌ Erro ao apagar histórico: $e');
      if (mounted) {
        Globals.showErrorSnackBar('Erro ao apagar histórico.');
      }
    } finally {
      if (mounted) setState(() => _isConsentLoading = false);
    }
  }

  Future<void> _toggleTracking(bool enable) async {
    setState(() => _isLoading = true);

    try {
      final controller = ref.read(locationControllerProvider);

      if (enable) {
        final success = await controller.startTracking(
          intervalMinutes: _selectedInterval,
        );
        if (!success && mounted) {
          Globals.showErrorSnackBar(
            'Não foi possível iniciar o rastreamento. '
            'Verifique as permissões de localização.',
          );
        }
      } else {
        await controller.stopTracking();
      }
    } catch (e) {
      debugPrint('❌ Erro ao alternar rastreamento: $e');
      Globals.showErrorSnackBar('Erro ao alterar rastreamento.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _captureNow() async {
    setState(() => _isLoading = true);

    try {
      final controller = ref.read(locationControllerProvider);
      await controller.captureAndSendNow();
      Globals.showSuccessSnackBar('📍 Localização capturada com sucesso!');
    } catch (e) {
      Globals.showErrorSnackBar('Erro ao capturar localização.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (_) {
      return isoDate;
    }
  }
}

// ─── Widget auxiliar de cabeçalho de seção ────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
