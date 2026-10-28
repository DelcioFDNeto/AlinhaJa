import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:alinha_ja/features/location/providers/location_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Dashboard de rastreamento para TI — exibe mapa, lista de localizações
/// e painel de consentimento LGPD.
class LocationDashboardScreen extends ConsumerStatefulWidget {
  const LocationDashboardScreen({super.key});

  @override
  ConsumerState<LocationDashboardScreen> createState() =>
      _LocationDashboardScreenState();
}

class _LocationDashboardScreenState
    extends ConsumerState<LocationDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MapController _mapController = MapController();
  Timer? _refreshTimer;
  String _searchQuery = '';

  // Centro padrão do mapa: Belém-PA (sede das empresas atendidas).
  static const _defaultCenter = LatLng(-1.4557, -48.5024);
  static const _defaultZoom = 12.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Auto-refresh a cada 60 segundos
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      ref.invalidate(latestLocationsProvider);
      ref.invalidate(gpsConsentOverviewProvider);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locationsAsync = ref.watch(latestLocationsProvider);
    final consentOverviewAsync = ref.watch(gpsConsentOverviewProvider);

    return Column(
      children: [
        // ── Barra de Busca ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Buscar colaborador...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
        ),

        // ── Resumo de consentimento (banner) ──
        _buildConsentSummaryBanner(theme, consentOverviewAsync),

        // ── Tab Bar ──
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.map_rounded), text: 'Mapa'),
            Tab(icon: Icon(Icons.list_rounded), text: 'Lista'),
            Tab(icon: Icon(Icons.verified_user_outlined), text: 'Consentimento'),
          ],
        ),

        // ── Conteúdo ──
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 0: Mapa
              locationsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _buildErrorView(theme, e),
                data: (locations) =>
                    _buildMapView(theme, _filterLocations(locations)),
              ),
              // Tab 1: Lista
              locationsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _buildErrorView(theme, e),
                data: (locations) =>
                    _buildListView(theme, _filterLocations(locations)),
              ),
              // Tab 2: Consentimento
              consentOverviewAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _buildErrorView(theme, e),
                data: (overview) =>
                    _buildConsentTab(theme, _filterConsent(overview)),
              ),
            ],
          ),
        ),

        // ── Botão de refresh ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 14, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              Text(
                'Atualiza automaticamente a cada 60s',
                style:
                    TextStyle(fontSize: 11, color: theme.colorScheme.outline),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  ref.invalidate(latestLocationsProvider);
                  ref.invalidate(gpsConsentOverviewProvider);
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Atualizar', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _filterLocations(
      List<Map<String, dynamic>> locations) {
    if (_searchQuery.isEmpty) return locations;
    return locations.where((loc) {
      final name = (loc['full_name'] as String? ?? '').toLowerCase();
      return name.contains(_searchQuery);
    }).toList();
  }

  List<Map<String, dynamic>> _filterConsent(
      List<Map<String, dynamic>> overview) {
    if (_searchQuery.isEmpty) return overview;
    return overview.where((item) {
      final name = (item['full_name'] as String? ?? '').toLowerCase();
      return name.contains(_searchQuery);
    }).toList();
  }

  Widget _buildErrorView(ThemeData theme, Object e) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              color: theme.colorScheme.error, size: 48),
          const SizedBox(height: 8),
          Text('Erro ao carregar dados',
              style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              ref.invalidate(latestLocationsProvider);
              ref.invalidate(gpsConsentOverviewProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  // ── Banner resumo de consentimento ─────────────────────────────

  Widget _buildConsentSummaryBanner(
    ThemeData theme,
    AsyncValue<List<Map<String, dynamic>>> consentAsync,
  ) {
    return consentAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (overview) {
        if (overview.isEmpty) return const SizedBox.shrink();

        final total = overview.length;
        final consented =
            overview.where((e) => e['consent_active'] == true).length;
        final pending = total - consented;

        if (pending == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Material(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _tabController.animateTo(2);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 20, color: Colors.orange.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$pending de $total colaborador${total > 1 ? 'es' : ''} '
                        'sem consentimento GPS',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: Colors.orange.shade600),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Mapa com flutter_map + OpenStreetMap ──
  Widget _buildMapView(ThemeData theme, List<Map<String, dynamic>> locations) {
    if (locations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_rounded,
                size: 64,
                color: theme.colorScheme.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'Nenhuma localização recente',
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Localizações da última hora aparecerão aqui.\n'
              'Verifique a aba Consentimento se a lista ficou vazia.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.outline.withValues(alpha: 0.7),
                  fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Inicializa o centro no primeiro ponto
    final firstLat =
        locations.first['latitude'] as double? ?? _defaultCenter.latitude;
    final firstLng =
        locations.first['longitude'] as double? ?? _defaultCenter.longitude;

    final markers = locations
        .where((loc) => loc['latitude'] != null && loc['longitude'] != null)
        .map((loc) {
      final lat = loc['latitude'] as double;
      final lng = loc['longitude'] as double;
      final name = loc['full_name'] as String? ?? 'Desconhecido';

      return Marker(
        point: LatLng(lat, lng),
        width: 180,
        height: 60,
        child: GestureDetector(
          onTap: () => _showLocationDetail(loc),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  name.split(' ').first,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.location_pin,
                color: theme.colorScheme.primary,
                size: 32,
              ),
            ],
          ),
        ),
      );
    }).toList();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(firstLat, firstLng),
        initialZoom: _defaultZoom,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.alinha_ja.app',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  // ── Lista de localizações ──
  Widget _buildListView(ThemeData theme, List<Map<String, dynamic>> locations) {
    if (locations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded,
                size: 64,
                color: theme.colorScheme.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'Nenhum colaborador rastreado',
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Colaboradores precisam consentir antes de gerar pontos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.outline.withValues(alpha: 0.7),
                  fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: locations.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 72, endIndent: 16),
      itemBuilder: (context, index) {
        final loc = locations[index];
        final name = loc['full_name'] as String? ?? 'Desconhecido';
        final avatarUrl = loc['avatar_url'] as String?;
        final lat = loc['latitude'] as double?;
        final lng = loc['longitude'] as double?;
        final battery = loc['battery_level'] as int?;
        final recordedAt = loc['recorded_at'] != null
            ? DateTime.tryParse(loc['recorded_at'] as String)
            : null;
        final speed = loc['speed'] as double?;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl, maxWidth: 320) : null,
            child: avatarUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600),
                  )
                : null,
          ),
          title:
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Row(
            children: [
              Icon(Icons.access_time_rounded,
                  size: 12, color: theme.colorScheme.outline),
              const SizedBox(width: 4),
              Text(
                recordedAt != null
                    ? timeago.format(recordedAt, locale: 'pt_BR')
                    : 'Desconhecido',
                style:
                    TextStyle(fontSize: 12, color: theme.colorScheme.outline),
              ),
              if (battery != null) ...[
                const SizedBox(width: 12),
                Icon(
                  battery > 50
                      ? Icons.battery_full_rounded
                      : battery > 20
                          ? Icons.battery_3_bar_rounded
                          : Icons.battery_alert_rounded,
                  size: 14,
                  color: battery > 50
                      ? Colors.green
                      : battery > 20
                          ? Colors.orange
                          : Colors.red,
                ),
                const SizedBox(width: 2),
                Text(
                  '$battery%',
                  style:
                      TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                ),
              ],
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (lat != null && lng != null)
                Text(
                  '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.outline,
                    fontFamily: 'monospace',
                  ),
                ),
              if (speed != null && speed > 0)
                Text(
                  '${(speed * 3.6).toStringAsFixed(0)} km/h',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          onTap: () => _showLocationDetail(loc),
        );
      },
    );
  }

  // ── Tab Consentimento ─────────────────────────────────────────

  Widget _buildConsentTab(
      ThemeData theme, List<Map<String, dynamic>> overview) {
    if (overview.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user_outlined,
                size: 64,
                color: theme.colorScheme.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'Nenhum registro de rastreamento',
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Colaboradores aparecerão aqui quando acessarem\na tela de rastreamento pela primeira vez.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.outline.withValues(alpha: 0.7),
                  fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Separar em grupos
    final pending =
        overview.where((e) => e['consent_active'] != true).toList();
    final consented =
        overview.where((e) => e['consent_active'] == true).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // ── Resumo ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _ConsentStatChip(
                icon: Icons.check_circle_rounded,
                color: Colors.green,
                count: consented.length,
                label: 'Consentiu',
              ),
              const SizedBox(width: 10),
              _ConsentStatChip(
                icon: Icons.hourglass_top_rounded,
                color: Colors.orange,
                count: pending.length,
                label: 'Aguardando',
              ),
              const SizedBox(width: 10),
              _ConsentStatChip(
                icon: Icons.people_rounded,
                color: Colors.blue,
                count: overview.length,
                label: 'Total',
              ),
            ],
          ),
        ),

        // ── Aguardando consentimento ──
        if (pending.isNotEmpty) ...[
          _ConsentSectionHeader(
            title: 'Aguardando consentimento',
            count: pending.length,
            color: Colors.orange,
            theme: theme,
          ),
          ...pending
              .map((item) => _buildConsentTile(theme, item))
              ,
        ],

        // ── Consentimento ativo ──
        if (consented.isNotEmpty) ...[
          _ConsentSectionHeader(
            title: 'Consentimento ativo',
            count: consented.length,
            color: Colors.green,
            theme: theme,
          ),
          ...consented
              .map((item) => _buildConsentTile(theme, item))
              ,
        ],
      ],
    );
  }

  Widget _buildConsentTile(ThemeData theme, Map<String, dynamic> item) {
    final name = item['full_name'] as String? ?? 'Desconhecido';
    final avatarUrl = item['avatar_url'] as String?;
    final consentActive = item['consent_active'] as bool? ?? false;
    final isEnabled = item['is_enabled'] as bool? ?? false;
    final consentGivenAt = item['consent_given_at'] as String?;
    final consentRevokedAt = item['consent_revoked_at'] as String?;
    final version = item['consent_version'] as String?;

    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (consentActive) {
      statusText = 'Consentiu em ${_formatDate(consentGivenAt)}';
      statusColor = Colors.green;
      statusIcon = Icons.verified_user_rounded;
    } else if (consentRevokedAt != null) {
      statusText = 'Revogou em ${_formatDate(consentRevokedAt)}';
      statusColor = Colors.red;
      statusIcon = Icons.shield_outlined;
    } else {
      statusText = 'Aguardando consentimento';
      statusColor = Colors.orange;
      statusIcon = Icons.hourglass_top_rounded;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl, maxWidth: 320) : null,
        child: avatarUrl == null
            ? Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600),
              )
            : null,
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Row(
        children: [
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(fontSize: 12, color: statusColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isEnabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'GPS ON',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.blue),
              ),
            ),
          if (version != null) ...[
            const SizedBox(height: 2),
            Text(
              version,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.outline,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '-';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return DateFormat('dd/MM/yy').format(dt);
    } catch (_) {
      return isoDate;
    }
  }

  void _showLocationDetail(Map<String, dynamic> loc) {
    final theme = Theme.of(context);
    final name = loc['full_name'] as String? ?? 'Desconhecido';
    final lat = loc['latitude'] as double?;
    final lng = loc['longitude'] as double?;
    final accuracy = loc['accuracy'] as double?;
    final battery = loc['battery_level'] as int?;
    final speed = loc['speed'] as double?;
    final recordedAt = loc['recorded_at'] != null
        ? DateTime.tryParse(loc['recorded_at'] as String)
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              name,
              style:
                  GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            if (recordedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                timeago.format(recordedAt, locale: 'pt_BR'),
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.location_on_rounded,
              label: 'Coordenadas',
              value: lat != null && lng != null
                  ? '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'
                  : '-',
            ),
            if (accuracy != null)
              _DetailRow(
                icon: Icons.adjust_rounded,
                label: 'Precisão',
                value: '±${accuracy.toStringAsFixed(0)} m',
              ),
            if (speed != null)
              _DetailRow(
                icon: Icons.speed_rounded,
                label: 'Velocidade',
                value: '${(speed * 3.6).toStringAsFixed(1)} km/h',
              ),
            if (battery != null)
              _DetailRow(
                icon: Icons.battery_std_rounded,
                label: 'Bateria',
                value: '$battery%',
              ),
            const SizedBox(height: 16),
            if (lat != null && lng != null)
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(lat, lng),
                      initialZoom: 16,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.alinha_ja.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(lat, lng),
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_pin,
                              color: theme.colorScheme.primary,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────

class _ConsentStatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;

  const _ConsentStatChip({
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentSectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final ThemeData theme;

  const _ConsentSectionHeader({
    required this.title,
    required this.count,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 13)),
          const Spacer(),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
