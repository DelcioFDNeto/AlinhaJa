import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/core/constants.dart';

Widget buildMirotalkView({
  required String roomId,
  required String userName,
  required VoidCallback onClosed,
  String? mirotalkUrl,
  bool isHost = false,
  VoidCallback? onEndMeeting,
}) {
  return const Scaffold(
    body: Center(
      child: CircularProgressIndicator(),
    ),
  );
}

Future<void> joinMirotalkNative({
  required String roomId,
  required String userName,
  required VoidCallback onClosed,
  String? mirotalkUrl,
}) async {
  try {
    // Usa a URL passada diretamente, ou usa a armazenada no CallService, ou constrói a URL
    final url = mirotalkUrl ??
        CallService.instance.mirotalkUrl ??
        CallService.lastJoinedRoomUrl ??
        '${AppConstants.mirotalkServerUrl}/AlinhaJá_$roomId';

    debugPrint('📞 Abrindo MiroTalk com URL: $url');
    debugPrint('📞 mirotalkUrl passado: $mirotalkUrl');
    debugPrint(
        '📞 CallService.mirotalkUrl: ${CallService.instance.mirotalkUrl}');
    debugPrint(
        '📞 CallService.lastJoinedRoomUrl: ${CallService.lastJoinedRoomUrl}');

    if (url.isEmpty) {
      debugPrint("MiroTalk: URL vazia - não foi possível abrir");
      onClosed();
      return;
    }

    // Limpa o nome de usuario - remove caracteres invisiveis e normaliza
    String cleanUserName =
        userName.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    if (cleanUserName.isEmpty) {
      cleanUserName = 'Participante';
    }

    final finalUrl = _withUserName(url, cleanUserName);

    debugPrint('📞 URL final (limpa): $finalUrl');

    try {
      // Valida a URL antes de tentar fazer parse
      if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
        debugPrint("MiroTalk: URL invalida - protocolo nao reconhecido");
        onClosed();
        return;
      }

      final uri = Uri.parse(finalUrl);

      // Abre no navegador in-app / nativo com suporte profundo a WebRTC e Câmera
      final result = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );

      if (!result) {
        debugPrint("MiroTalk: Não foi possível abrir o navegador");
        onClosed();
      } else {
        debugPrint("MiroTalk: Reunião iniciada no navegador externo.");
      }
    } catch (error) {
      debugPrint("Erro ao abrir MiroTalk: $error");
      onClosed();
    }
  } catch (e) {
    debugPrint("Erro geral no joinMirotalkNative: $e");
    onClosed();
  }
}

String _withUserName(String baseUrl, String userName) {
  final name = userName.isEmpty ? 'Participante' : userName;
  final safeUrl = _escapeIllegalPercents(baseUrl.trim());
  final uri = Uri.tryParse(safeUrl);

  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    if (uri.queryParameters.containsKey('name')) {
      return uri.toString();
    }

    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'name': name,
    }).toString();
  }

  final separator = safeUrl.contains('?') ? '&' : '?';
  return '$safeUrl${separator}name=${Uri.encodeComponent(name)}';
}

String _escapeIllegalPercents(String value) {
  return value.replaceAllMapped(
    RegExp(r'%(?![0-9A-Fa-f]{2})'),
    (_) => '%25',
  );
}
