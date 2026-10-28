import 'package:flutter/material.dart';
import 'package:alinha_ja/core/services/call_service.dart';

class CallControlBar extends StatelessWidget {
  final bool isVideo;
  final bool isHost;
  final bool isMiniature;
  final VoidCallback onEndCall;
  final VoidCallback onShowParticipants;
  final VoidCallback onRefresh;

  const CallControlBar({
    super.key,
    required this.isVideo,
    required this.isHost,
    this.isMiniature = false,
    required this.onEndCall,
    required this.onShowParticipants,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final callService = CallService.instance;

    if (isMiniature) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: Colors.black54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(callService.isMuted ? Icons.mic_off : Icons.mic,
                      color:
                          callService.isMuted ? Colors.redAccent : Colors.white,
                      size: 20),
                  onPressed: () async {
                    await callService.toggleMute();
                    onRefresh();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.call_end, color: Colors.red, size: 20),
                  onPressed: onEndCall,
                )
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white12, width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 5),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              // Mutar
              _CallButton(
                icon: callService.isMuted
                    ? Icons.mic_off_rounded
                    : Icons.mic_rounded,
                label: 'Mutar',
                color:
                    callService.isMuted ? Colors.white24 : Colors.transparent,
                iconColor:
                    callService.isMuted ? Colors.redAccent : Colors.white,
                onTap: () async {
                  await callService.toggleMute();
                  onRefresh();
                },
              ),

              // Botão de Tela (LOTE 3) / Botão Video (Toggle camera)
              if (isVideo)
                _CallButton(
                  icon: callService.isScreenSharing
                      ? Icons.stop_screen_share_rounded
                      : Icons.screen_share_rounded,
                  label: callService.isScreenSharing ? 'Parar Tela' : 'Tela',
                  color: callService.isScreenSharing
                      ? Colors.blueAccent.shade100
                      : Colors.transparent,
                  iconColor: callService.isScreenSharing
                      ? Colors.blue.shade900
                      : Colors.white,
                  onTap: () async {
                    await callService.toggleScreenShare();
                    onRefresh();
                  },
                ),

              // Botão de Participantes (Somente Host)
              if (isVideo && isHost)
                _CallButton(
                  icon: Icons.people_alt_rounded,
                  label: 'Usuários',
                  color: Colors.transparent,
                  iconColor: Colors.amberAccent,
                  onTap: onShowParticipants,
                ),

              // Botão central Encerrar (Vermelho Premium)
              GestureDetector(
                onTap: onEndCall,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.shade600,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.red.withValues(alpha: 0.5),
                          blurRadius: 15,
                          spreadRadius: 2),
                    ],
                  ),
                  child: const Icon(Icons.call_end_rounded,
                      color: Colors.white, size: 32),
                ),
              ),

              // Som / Alto-falante
              _CallButton(
                icon: callService.isSpeakerOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_rounded,
                label: 'Som',
                color: callService.isSpeakerOn
                    ? Colors.white24
                    : Colors.transparent,
                iconColor:
                    callService.isSpeakerOn ? Colors.blueAccent : Colors.white,
                onTap: () async {
                  await callService.toggleSpeaker();
                  onRefresh();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
