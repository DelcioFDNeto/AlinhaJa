import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:alinha_ja/core/services/location_share_service.dart';

/// Localização escolhida para enviar na conversa.
class PickedLocation {
  final double latitude;
  final double longitude;

  /// Nome dado pelo usuário ("Loja Centro", "Portaria 2"). Vazio quando não
  /// informado — o card cai no rótulo genérico.
  final String? label;

  /// Precisão do GPS, só quando o ponto veio do aparelho e não foi arrastado.
  final double? accuracy;

  const PickedLocation({
    required this.latitude,
    required this.longitude,
    this.label,
    this.accuracy,
  });
}

/// Escolha de um ponto no mapa para enviar na conversa.
///
/// Antes o app só sabia mandar "onde estou agora". Aqui dá para apontar
/// qualquer lugar — endereço de entrega, ponto de encontro, obra —, com a
/// posição atual como atalho e não como única opção.
class LocationPickerScreen extends StatefulWidget {
  /// Centro inicial quando a posição do aparelho não está disponível.
  /// Padrão: centro geográfico aproximado do Brasil.
  final LatLng fallbackCenter;

  const LocationPickerScreen({
    super.key,
    this.fallbackCenter = const LatLng(-15.7801, -47.9292),
  });

  static Future<PickedLocation?> show(BuildContext context) {
    return Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const LocationPickerScreen(),
      ),
    );
  }

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _mapController = MapController();
  final _labelCtrl = TextEditingController();

  late LatLng _center = widget.fallbackCenter;
  bool _locating = true;

  /// Precisão só vale enquanto o pino continuar exatamente onde o GPS marcou.
  double? _gpsAccuracy;

  @override
  void initState() {
    super.initState();
    _goToCurrentPosition(initial: true);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _goToCurrentPosition({bool initial = false}) async {
    if (!initial) setState(() => _locating = true);

    final result = await LocationShareService.capture();
    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() => _locating = false);
      // Sem GPS o mapa continua utilizável: o usuário navega e aponta na mão.
      if (!initial) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
      return;
    }

    final position = result.position!;
    final target = LatLng(position.latitude, position.longitude);

    setState(() {
      _center = target;
      _gpsAccuracy = position.accuracy;
      _locating = false;
    });
    _mapController.move(target, 16);
  }

  void _onMapMoved(MapCamera camera, bool hasGesture) {
    setState(() {
      _center = camera.center;
      // Arrastou o mapa: o ponto não é mais a leitura do GPS.
      if (hasGesture) _gpsAccuracy = null;
    });
  }

  void _confirm() {
    final label = _labelCtrl.text.trim();
    Navigator.of(context).pop(PickedLocation(
      latitude: _center.latitude,
      longitude: _center.longitude,
      label: label.isEmpty ? null : label,
      accuracy: _gpsAccuracy,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escolher localização'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 15,
                    onPositionChanged: _onMapMoved,
                    // Tocar move o alvo até ali, sem precisar arrastar o mapa.
                    onTap: (_, point) {
                      setState(() => _gpsAccuracy = null);
                      _mapController.move(point, _mapController.camera.zoom);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.alinha_ja.app',
                    ),
                  ],
                ),

                // Pino fixo no centro: o mapa se move por baixo dele, então o
                // alvo é sempre o meio da tela — não some sob o dedo.
                const IgnorePointer(child: Center(child: _CenterPin())),

                if (_locating)
                  const Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(child: _LocatingChip()),
                  ),

                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Column(
                    children: [
                      _MapButton(
                        icon: Icons.add,
                        tooltip: 'Aproximar',
                        onTap: () => _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom + 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _MapButton(
                        icon: Icons.remove,
                        tooltip: 'Afastar',
                        onTap: () => _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom - 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _MapButton(
                        icon: Icons.my_location_rounded,
                        tooltip: 'Minha localização',
                        highlighted: true,
                        onTap: _goToCurrentPosition,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Painel de confirmação ──
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.place_rounded,
                          size: 18, color: Color(0xFF34C759)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_center.latitude.toStringAsFixed(5)}, '
                          '${_center.longitude.toStringAsFixed(5)}'
                          '${_gpsAccuracy != null ? ' · ±${_gpsAccuracy!.round()} m' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _labelCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _confirm(),
                    decoration: InputDecoration(
                      hintText: 'Nome do local (opcional) — ex: Portaria 2',
                      prefixIcon: const Icon(Icons.label_outline, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _confirm,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Enviar esta localização'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
}

class _CenterPin extends StatelessWidget {
  const _CenterPin();

  @override
  Widget build(BuildContext context) {
    // Deslocado para cima em metade da altura: a ponta do pino é que marca o
    // ponto, não o centro do ícone.
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on, size: 44, color: Color(0xFFE53935)),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocatingChip extends StatelessWidget {
  const _LocatingChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surface,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Localizando...', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool highlighted;

  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: highlighted ? theme.colorScheme.primary : theme.colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: highlighted
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
