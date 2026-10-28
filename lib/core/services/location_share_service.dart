import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Posição capturada para compartilhar em uma conversa.
class SharedPosition {
  final double latitude;
  final double longitude;
  final double? accuracy;

  const SharedPosition({
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });
}

/// Motivo da falha, para a UI dar uma orientação útil em vez de "erro".
enum LocationShareError { serviceDisabled, denied, deniedForever, failed }

class LocationShareResult {
  final SharedPosition? position;
  final LocationShareError? error;

  const LocationShareResult.success(this.position) : error = null;
  const LocationShareResult.failure(this.error) : position = null;

  bool get isSuccess => position != null;

  String get message {
    switch (error) {
      case LocationShareError.serviceDisabled:
        return 'Ligue o GPS do aparelho para compartilhar sua localização.';
      case LocationShareError.denied:
        return 'Permissão de localização negada.';
      case LocationShareError.deniedForever:
        return 'Permissão bloqueada. Libere o acesso à localização nos ajustes do aparelho.';
      case LocationShareError.failed:
      case null:
        return 'Não foi possível obter sua localização agora.';
    }
  }
}

/// Captura pontual da posição para enviar no chat.
///
/// Diferente do `LocationService` do módulo de rastreamento corporativo, aqui
/// só se pede permissão de uso em primeiro plano (`whileInUse`) e nada é
/// gravado em `user_locations` — é um envio pontual, a pedido do usuário.
class LocationShareService {
  LocationShareService._();

  static Future<LocationShareResult> capture() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationShareResult.failure(
          LocationShareError.serviceDisabled,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationShareResult.failure(LocationShareError.denied);
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationShareResult.failure(
          LocationShareError.deniedForever,
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      return LocationShareResult.success(SharedPosition(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      ));
    } catch (e) {
      debugPrint('Erro ao capturar localização para envio: $e');
      return const LocationShareResult.failure(LocationShareError.failed);
    }
  }

  /// Link universal para abrir o ponto no app de mapas do aparelho.
  static Uri mapsUri(double latitude, double longitude) => Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
      );
}
