import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:alinha_ja/core/constants.dart';

class MiroTalkService {
  static final MiroTalkService _instance = MiroTalkService._internal();
  factory MiroTalkService() => _instance;
  MiroTalkService._internal();

  Future<String?> createRoom({
    required String roomName,
    String? roomPassword,
    int durationHours = 24,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.mirotalkApiUrl}/meeting'),
        headers: {
          'Authorization': AppConstants.mirotalkApiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'room': 'AlinhaJá_$roomName',
          'roomPassword': roomPassword != null && roomPassword.isNotEmpty
              ? roomPassword
              : false,
          'duration': durationHours,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['meeting'] != null) {
          debugPrint('MiroTalk: Sala criada via API: ${data['meeting']}');
          return data['meeting'] as String;
        }
      }

      debugPrint(
          'MiroTalk API error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('MiroTalk: Erro ao criar sala via API: $e');
    }

    // Fallback: URL direta (pode não funcionar se a API estiver down)
    final encodedRoom = Uri.encodeComponent('AlinhaJá_$roomName');
    return '${AppConstants.mirotalkServerUrl}/$encodedRoom';
  }

  Future<String?> getJoinUrl({
    required String roomName,
    required String userName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.mirotalkApiUrl}/join'),
        headers: {
          'Authorization': AppConstants.mirotalkApiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'room': 'AlinhaJá_$roomName',
          'roomPassword': false,
          'name': userName,
          'audio': true,
          'video': true,
          'screen': true,
          'chat': true,
          'notify': true,
          'duration': 'unlimited',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['join'] != null) {
          debugPrint('MiroTalk: URL de join obtida via API: ${data['join']}');
          return data['join'] as String;
        }
      }

      debugPrint(
          'MiroTalk API join error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('MiroTalk: Erro ao obter URL de join: $e');
    }

    // Fallback
    final encodedName = Uri.encodeComponent(userName);
    final encodedRoom = Uri.encodeComponent('AlinhaJá_$roomName');
    return '${AppConstants.mirotalkServerUrl}/$encodedRoom?name=$encodedName';
  }

  Future<String?> getDirectJoinUrl({
    required String roomName,
    required String userName,
    String? password,
  }) async {
    return getJoinUrl(roomName: roomName, userName: userName);
  }
}
