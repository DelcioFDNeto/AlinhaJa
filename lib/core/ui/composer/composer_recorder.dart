import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Gravação de áudio do composer: permissão, arquivo temporário e cronômetro.
///
/// [onChanged] dispara a cada mudança visível (início, tique do segundo,
/// parada) para o widget se redesenhar.
class ComposerRecorder {
  final VoidCallback onChanged;

  ComposerRecorder({required this.onChanged});

  final AudioRecorder _record = AudioRecorder();
  Timer? _timer;

  bool _isRecording = false;
  Duration _duration = Duration.zero;

  bool get isRecording => _isRecording;
  Duration get duration => _duration;

  Future<void> start() async {
    try {
      if (!await _record.hasPermission()) return;

      // Na Web o plugin grava em memória e devolve um blob; o caminho em
      // disco só existe nas plataformas nativas.
      String path = '';
      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _record.start(const RecordConfig(), path: path);

      _isRecording = true;
      _duration = Duration.zero;
      onChanged();

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _duration += const Duration(seconds: 1);
        onChanged();
      });
    } catch (e) {
      debugPrint('Erro ao iniciar gravação: $e');
      _reset();
    }
  }

  /// Encerra a gravação. Retorna o caminho do áudio, ou `null` quando
  /// [discard] é verdadeiro ou a gravação falhou — descartar também apaga o
  /// arquivo temporário.
  Future<String?> stop({bool discard = false}) async {
    _timer?.cancel();

    try {
      final path = await _record.stop();
      _reset();

      if (path == null) return null;
      if (!discard) return path;

      if (!kIsWeb) {
        try {
          final file = io.File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      return null;
    } catch (e) {
      debugPrint('Erro ao parar gravação: $e');
      _reset();
      return null;
    }
  }

  void _reset() {
    _isRecording = false;
    _duration = Duration.zero;
    onChanged();
  }

  void dispose() {
    _timer?.cancel();
    _record.dispose();
  }
}
