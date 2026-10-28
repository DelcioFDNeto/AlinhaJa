import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alinha_ja/core/services/location_share_service.dart';

/// Card de localização com mini-mapa e atalho para o app de mapas.
class LocationCard extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final String? label;
  final double maxWidth;

  const LocationCard({
    super.key,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.label,
    this.maxWidth = 260,
  });

  Future<void> _openMaps(BuildContext context) async {
    final uri = LocationShareService.mapsUri(latitude, longitude);
    try {
      bool opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!opened) {
        opened = await launchUrl(uri);
      }
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o mapa.')),
        );
      }
    } catch (e) {
      debugPrint('Erro ao abrir mapa: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final point = LatLng(latitude, longitude);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 140,
              width: maxWidth,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: point,
                      initialZoom: 15,
                      // Mapa decorativo: o gesto é abrir no app de mapas.
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
                            point: point,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_on,
                              color: Color(0xFFE53935),
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(onTap: () => _openMaps(context)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  size: 16, color: Color(0xFF34C759)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label?.isNotEmpty == true ? label! : 'Localização',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'
                      '${accuracy != null ? ' · ±${accuracy!.round()} m' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                tooltip: 'Abrir no mapa',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openMaps(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
