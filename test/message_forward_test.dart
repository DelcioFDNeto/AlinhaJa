import 'package:flutter_test/flutter_test.dart';
import 'package:alinha_ja/core/services/message_forward_service.dart';

void main() {
  group('MessageForwardService.buildMetadata', () {
    test('não copia dados que pertencem só à mensagem original', () {
      final result = MessageForwardService.buildMetadata({
        'mentions': ['uuid-de-outro-chat'],
        'reactions': {'👍': 2},
        'upload_progress': 0.5,
        'is_view_once': true,
      }, 'Ana');

      expect(result.containsKey('mentions'), isFalse);
      expect(result.containsKey('reactions'), isFalse);
      expect(result.containsKey('upload_progress'), isFalse);
      expect(result.containsKey('is_view_once'), isFalse);
      expect(result['forwarded_from'], 'Ana');
    });

    test('preserva os dados de mídia necessários para exibir o anexo', () {
      final result = MessageForwardService.buildMetadata({
        'media_mime_type': 'image/jpeg',
        'media_size_bytes': 1024,
        'file_name': 'foto.jpg',
      }, 'Ana');

      expect(result['media_mime_type'], 'image/jpeg');
      expect(result['media_size_bytes'], 1024);
      expect(result['file_name'], 'foto.jpg');
    });

    test('encaminhar um encaminhamento mantém o autor original', () {
      final result = MessageForwardService.buildMetadata({
        'forwarded_from': 'Ana',
      }, 'Bruno');

      expect(result['forwarded_from'], 'Ana');
    });
  });
}
