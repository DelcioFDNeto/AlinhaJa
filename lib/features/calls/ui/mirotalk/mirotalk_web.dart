import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:alinha_ja/core/constants.dart';

Future<void> joinMirotalkNative({
  required String roomId,
  required String userName,
  required VoidCallback onClosed,
  String? mirotalkUrl,
}) async {
  throw UnsupportedError('Only use buildMirotalkView for the Web.');
}

Widget buildMirotalkView({
  required String roomId,
  required String userName,
  required VoidCallback onClosed,
  String? mirotalkUrl,
  bool isHost = false,
  VoidCallback? onEndMeeting,
}) {
  final fullUrl = _withUserName(
    mirotalkUrl ?? '${AppConstants.mirotalkServerUrl}/AlinhaJá_$roomId',
    userName,
  );

  debugPrint('MiroTalk Web: mirotalkUrl=$mirotalkUrl, fullUrl=$fullUrl');

  return _MiroTalkEntryScreen(
    roomUrl: fullUrl,
    userName: userName,
    onClosed: onClosed,
    isHost: isHost,
    onEndMeeting: onEndMeeting,
  );
}

class _MiroTalkEntryScreen extends StatelessWidget {
  final String roomUrl;
  final String userName;
  final VoidCallback onClosed;
  final bool isHost;
  final VoidCallback? onEndMeeting;

  const _MiroTalkEntryScreen({
    required this.roomUrl,
    required this.userName,
    required this.onClosed,
    this.isHost = false,
    this.onEndMeeting,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Reunião ${AppConstants.appName}'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onClosed,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.video_camera_front_rounded,
                size: 80,
                color: Colors.teal,
              ),
              const SizedBox(height: 32),
              const Text(
                'Reunião de Vídeo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Toque no botão abaixo para entrar na reunião com vídeo e áudio.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  roomUrl,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: () => _openMeeting(context),
                icon: const Icon(Icons.login_rounded, size: 24),
                label: const Text(
                  'Entrar na Reunião',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
              ),
              const SizedBox(height: 24),
              if (isHost && onEndMeeting != null) ...[
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Encerrar Reunião'),
                        content: const Text(
                            'Deseja encerrar esta videoconferência para todos os participantes de forma definitiva?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                            child: const Text('Encerrar para Todos'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      onEndMeeting!();
                    }
                  },
                  icon: const Icon(Icons.cancel_presentation_rounded, size: 24),
                  label: const Text(
                    'Encerrar para Todos',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.white.withValues(alpha: 0.5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Você será redirecionado para a reunião no navegador',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMeeting(BuildContext context) async {
    debugPrint('MiroTalk: Opening URL: $roomUrl');

    try {
      final uri = Uri.parse(roomUrl);

      // Use externalApplication para mobile web - abre no navegador completo
      final canLaunch = await canLaunchUrl(uri);

      debugPrint('MiroTalk: canLaunchUrl: $canLaunch');

      if (canLaunch) {
        // Use inAppBrowserView for web, externalApplication for mobile
        final result = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        debugPrint('MiroTalk: launchUrl result: $result');

        if (!result) {
          if (context.mounted) {
            _showError(context, 'Não foi possível abrir o navegador');
          }
        }
      } else {
        // Try fallback
        debugPrint('MiroTalk: cannot launch, trying with webOnlyWindowName');
        final fallbackResult = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_self',
        );

        debugPrint('MiroTalk: fallback result: $fallbackResult');
      }
    } catch (e) {
      debugPrint('MiroTalk: Error: $e');
      if (context.mounted) {
        _showError(context, 'Erro ao abrir reunião: $e');
      }
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

String _withUserName(String baseUrl, String userName) {
  final cleanUserName =
      userName.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  final name = cleanUserName.isEmpty ? 'Participante' : cleanUserName;
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
