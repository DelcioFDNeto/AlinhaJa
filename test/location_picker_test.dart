import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:alinha_ja/core/models/message_extras.dart';
import 'package:alinha_ja/core/ui/composer/sheets/location_picker_screen.dart';

/// Sem plugin de GPS no ambiente de teste, `LocationShareService.capture()`
/// falha e o seletor cai no centro de fallback — que é justamente o caminho a
/// garantir: sem permissão, o mapa continua utilizável.
const _fallback = LatLng(-23.5505, -46.6333);

Future<PickedLocation?> _pickWith(
  WidgetTester tester, {
  String? label,
}) async {
  PickedLocation? result;

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          result = await Navigator.of(context).push<PickedLocation>(
            MaterialPageRoute(
              builder: (_) =>
                  const LocationPickerScreen(fallbackCenter: _fallback),
            ),
          );
        },
        child: const Text('abrir'),
      ),
    ),
  ));

  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  if (label != null) {
    await tester.enterText(find.byType(TextField), label);
    await tester.pump();
  }

  await tester.tap(find.text('Enviar esta localização'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  return result;
}

void main() {
  group('LocationPickerScreen', () {
    testWidgets('devolve o ponto do mapa mesmo sem GPS disponível',
        (tester) async {
      final picked = await _pickWith(tester);

      expect(picked, isNotNull);
      expect(picked!.latitude, closeTo(_fallback.latitude, 0.0001));
      expect(picked.longitude, closeTo(_fallback.longitude, 0.0001));
      // Sem leitura do GPS não se inventa precisão.
      expect(picked.accuracy, isNull);
    });

    testWidgets('rótulo digitado acompanha a localização', (tester) async {
      final picked = await _pickWith(tester, label: 'Portaria 2');

      expect(picked?.label, 'Portaria 2');
    });

    testWidgets('sem rótulo o campo não vira string vazia', (tester) async {
      final picked = await _pickWith(tester, label: '   ');

      // String vazia no metadata faria o card mostrar um título em branco.
      expect(picked?.label, isNull);
    });
  });

  group('Metadata da localização escolhida', () {
    test('rótulo chega ao metadata e é lido de volta', () {
      final metadata = MessageExtras.location(
        latitude: -23.5505,
        longitude: -46.6333,
        label: 'Portaria 2',
      );

      expect(metadata.isLocation, isTrue);
      expect(metadata.locationLabel, 'Portaria 2');
      expect(metadata.locationAccuracy, isNull);
    });

    test('rótulo vazio não é gravado', () {
      final metadata = MessageExtras.location(
        latitude: 0,
        longitude: 0,
        label: '',
      );

      expect(metadata.containsKey('label'), isFalse);
    });
  });
}
