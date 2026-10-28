import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:record/record.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentRecordingPath;
  String? _callId;

  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;

  Future<void> startRecording(RtcEngine engine, String? callId) async {
    if (_isRecording) return;

    _callId = callId ?? DateTime.now().millisecondsSinceEpoch.toString();

    try {
      if (await _recorder.hasPermission()) {
        // On Web, passing an empty path to record package saves to an internal blob in memory
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.opus),
          path: '',
        );
        _isRecording = true;
        _currentRecordingPath = 'web_session_$_callId.webm';
        debugPrint('📞 Gravação Web com record iniciada (callId: $_callId)');
      } else {
        debugPrint('📞 Permissão de microfone negada para gravação Web');
      }
    } catch (e) {
      debugPrint('📞 Erro ao iniciar gravação Web com record: $e');
      _isRecording = false;
    }
  }

  Future<Uint8List?> stopRecording() async {
    if (!_isRecording) return null;

    _isRecording = false;

    try {
      final path = await _recorder.stop();
      if (path != null) {
        debugPrint('📞 Gravação Web parada, blob URL: $path');

        // Fetching the blob: URL using standard fetch API
        final response = await web.window.fetch(path.toJS).toDart;
        final jsArrayBuffer = await response.arrayBuffer().toDart;
        final bytes = jsArrayBuffer.toDart.asUint8List();

        debugPrint(
            '📞 Gravação Web carregada com sucesso: ${bytes.length} bytes');
        return bytes;
      }
    } catch (e) {
      debugPrint('📞 Erro ao parar gravação Web com record: $e');
    }

    return null;
  }

  Future<String> getTemporaryPath() async {
    return 'web_temp';
  }

  Future<List<int>?> readBytesFromPath(String path) async {
    return null;
  }

  Future<void> deleteAtPath(String path) async {}

  void dispose() {
    _recorder.dispose();
    _isRecording = false;
    _currentRecordingPath = null;
    _callId = null;
  }
}
