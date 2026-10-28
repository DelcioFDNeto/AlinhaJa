import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants.dart';
import '../providers/two_factor_provider.dart';
import '../services/device_fingerprint_service.dart';

class TrustedDevicesScreen extends ConsumerStatefulWidget {
  const TrustedDevicesScreen({super.key});

  @override
  ConsumerState<TrustedDevicesScreen> createState() =>
      _TrustedDevicesScreenState();
}

class _TrustedDevicesScreenState extends ConsumerState<TrustedDevicesScreen> {
  String? _currentFingerprint;

  @override
  void initState() {
    super.initState();
    _loadFingerprint();
  }

  Future<void> _loadFingerprint() async {
    final fingerprint = await DeviceFingerprintService.getFingerprint();
    if (mounted) {
      setState(() {
        _currentFingerprint = fingerprint;
      });
    }
  }

  IconData _getDeviceIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('android') ||
        lower.contains('samsung') ||
        lower.contains('xiaomi') ||
        lower.contains('motorola') ||
        lower.contains('lg')) {
      return Icons.phone_android_rounded;
    }
    if (lower.contains('iphone') ||
        lower.contains('ios') ||
        lower.contains('ipad')) {
      return Icons.phone_iphone_rounded;
    }
    if (lower.contains('web') ||
        lower.contains('navegador') ||
        lower.contains('chrome') ||
        lower.contains('firefox')) {
      return Icons.computer_rounded;
    }
    return Icons.devices_rounded;
  }

  bool _isDeviceActive(Map<String, dynamic> device) {
    final expiresAt = device['expires_at'] as String?;
    if (expiresAt == null) return false;
    return DateTime.parse(expiresAt).isAfter(DateTime.now());
  }

  bool _isCurrentDevice(Map<String, dynamic> device) {
    if (_currentFingerprint == null) return false;
    return device['device_fingerprint'] == _currentFingerprint;
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (_) {
      return '-';
    }
  }

  Future<void> _revokeDevice(String deviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Revogar Dispositivo',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Tem certeza que deseja revogar este dispositivo? Será necessária uma nova verificação no próximo acesso.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(
                color: AppConstants.secondaryText,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Revogar',
              style: GoogleFonts.inter(
                color: AppConstants.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = ref.read(twoFactorServiceProvider);
        await service.revokeDevice(deviceId);
        ref.invalidate(trustedDevicesProvider);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erro ao revogar dispositivo. Tente novamente.',
                style: GoogleFonts.inter(),
              ),
              backgroundColor: AppConstants.danger,
            ),
          );
        }
      }
    }
  }

  Future<void> _revokeAllDevices() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Revogar Todos os Dispositivos',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Tem certeza que deseja revogar todos os dispositivos confiáveis? Você precisará verificar novamente em cada dispositivo.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(
                color: AppConstants.secondaryText,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Revogar Todos',
              style: GoogleFonts.inter(
                color: AppConstants.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = ref.read(twoFactorServiceProvider);
        await service.revokeAllDevices();
        ref.invalidate(trustedDevicesProvider);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erro ao revogar dispositivos. Tente novamente.',
                style: GoogleFonts.inter(),
              ),
              backgroundColor: AppConstants.danger,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final devicesAsync = ref.watch(trustedDevicesProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Dispositivos Confiáveis',
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        color: AppConstants.primary,
        onRefresh: () async {
          ref.invalidate(trustedDevicesProvider);
        },
        child: devicesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: AppConstants.danger,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Erro ao carregar dispositivos',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Puxe para baixo para tentar novamente.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppConstants.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          data: (devices) {
            if (devices.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  _buildInfoCard(colorScheme),
                  const SizedBox(height: 48),
                  _buildEmptyState(colorScheme),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildInfoCard(colorScheme),
                const SizedBox(height: 20),
                ...devices.map(
                  (device) => _buildDeviceCard(device, colorScheme),
                ),
                const SizedBox(height: 24),
                _buildRevokeAllButton(colorScheme),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppConstants.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppConstants.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: AppConstants.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sobre Dispositivos Confiáveis',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Dispositivos confiáveis não precisam passar pela verificação em dois fatores por 30 dias. Você pode revogar o acesso a qualquer momento.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppConstants.secondaryText,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(
    Map<String, dynamic> device,
    ColorScheme colorScheme,
  ) {
    final deviceName = device['device_name'] as String? ?? 'Dispositivo';
    final verifiedAt = device['verified_at'] as String?;
    final expiresAt = device['expires_at'] as String?;
    final deviceId = device['id'] as String? ?? '';
    final isActive = _isDeviceActive(device);
    final isCurrent = _isCurrentDevice(device);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: isCurrent
            ? Border.all(
                color: AppConstants.primary.withValues(alpha: 0.4),
                width: 1.5,
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isActive ? AppConstants.primary : AppConstants.secondaryText)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getDeviceIcon(deviceName),
              size: 24,
              color: isActive
                  ? AppConstants.primary
                  : AppConstants.secondaryText,
            ),
          ),
          const SizedBox(width: 12),

          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        deviceName,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              AppConstants.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Este dispositivo',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Verificado em: ${_formatDate(verifiedAt)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppConstants.secondaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Expira em: ${_formatDate(expiresAt)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppConstants.secondaryText,
                  ),
                ),
                const SizedBox(height: 8),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (isActive
                            ? AppConstants.success
                            : AppConstants.danger)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isActive ? 'Ativo' : 'Expirado',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? AppConstants.success
                          : AppConstants.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Delete button
          IconButton(
            onPressed: () => _revokeDevice(deviceId),
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppConstants.danger,
              size: 22,
            ),
            tooltip: 'Revogar dispositivo',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppConstants.secondaryText.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Icon(
            Icons.devices_other_rounded,
            size: 48,
            color: AppConstants.secondaryText.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Nenhum dispositivo confiável registrado',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Dispositivos serão adicionados automaticamente após a verificação em dois fatores.',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: AppConstants.secondaryText,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRevokeAllButton(ColorScheme colorScheme) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: _revokeAllDevices,
        icon: const Icon(
          Icons.delete_sweep_rounded,
          color: AppConstants.danger,
        ),
        label: Text(
          'Revogar Todos os Dispositivos',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppConstants.danger,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: AppConstants.danger.withValues(alpha: 0.5),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
