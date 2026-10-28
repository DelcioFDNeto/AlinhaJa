import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:uuid/uuid.dart';

class AudioRecorderService {
  String? _currentRecordingPath;
  RtcEngine? _engine;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;

  Future<void> startRecording(RtcEngine engine, String? callId) async {
    if (_isRecording) return;

    _engine = engine;

    try {
      final dir = await getTemporaryDirectory();
      final id = callId ?? const Uuid().v4();
      final filePath = '${dir.path}/call_$id.wav';
      _currentRecordingPath = filePath;

      await engine.startAudioRecording(
        AudioRecordingConfiguration(
          filePath: filePath,
          sampleRate: 32000,
        ),
      );
      _isRecording = true;
      debugPrint('📞 Gravação nativa iniciada: $filePath');
    } catch (e) {
      debugPrint('📞 Erro ao iniciar gravação nativa: $e');
      _isRecording = false;
    }
  }

  Future<Uint8List?> stopRecording() async {
    if (!_isRecording || _engine == null || _currentRecordingPath == null) {
      return null;
    }

    try {
      await _engine!.stopAudioRecording();
      _isRecording = false;

      final file = File(_currentRecordingPath!);
      if (await file.exists()) {
        debugPrint('📞 Gravação nativa parada: ${file.path}');
        final bytes = await file.readAsBytes();
        try {
          await file.delete();
        } catch (e) {
          debugPrint('Aviso: Não foi possível deletar arquivo temporário $e');
        }
        _currentRecordingPath = null;
        return bytes;
      }
    } catch (e) {
      debugPrint('📞 Erro ao parar gravação nativa: $e');
    }

    return null;
  }

  Future<String> getTemporaryPath() async {
    final dir = await getTemporaryDirectory();
    return dir.path;
  }

  Future<List<int>?> readBytesFromPath(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  Future<void> deleteAtPath(String path) async {
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('Aviso: deleteAtPath falhou $e');
      }
    }
  }

  void dispose() {
    _isRecording = false;
    _engine = null;
    _currentRecordingPath = null;
  }
}
