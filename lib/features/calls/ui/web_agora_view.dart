import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:alinha_ja/core/services/call_service.dart';

class WebAgoraView extends StatelessWidget {
  final String roomUrl;
  final String callerName;
  final VoidCallback onEndCall;

  const WebAgoraView({
    super.key,
    required this.roomUrl,
    required this.callerName,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _AgoraWebVideoView(
        channelName: _extractChannelName(roomUrl),
        callerName: callerName,
        onEndCall: onEndCall,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'Plataforma não suportada para videochamada web',
          style: TextStyle(color: Colors.grey.shade400),
        ),
      ),
    );
  }

  String _extractChannelName(String url) {
    if (url.startsWith('http')) {
      final uri = Uri.parse(url);
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'default';
    }
    return url;
  }
}

class _AgoraWebVideoView extends StatefulWidget {
  final String channelName;
  final String callerName;
  final VoidCallback onEndCall;

  const _AgoraWebVideoView({
    required this.channelName,
    required this.callerName,
    required this.onEndCall,
  });

  @override
  State<_AgoraWebVideoView> createState() => _AgoraWebVideoViewState();
}

class _AgoraWebVideoViewState extends State<_AgoraWebVideoView> {
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isScreenSharing = false;
  int? _pinnedUid;

  // Reutiliza o engine do CallService — NÃO cria um novo
  RtcEngine? get _engine => CallService.instance.engine;

  bool get _isJoined => CallService.instance.isInCall;
  bool get _isMeeting => widget.channelName.startsWith('room_');

  @override
  void initState() {
    super.initState();
    CallService.instance.addOnCallStateChangedListener(_onCallStateChanged);

    // Se o CallService já entrou no canal (o que acontece antes de navegar),
    // precisamos ativar vídeo explicitamente pois a Web pode precisar do startPreview
    _ensureVideoEnabled();
  }

  @override
  void dispose() {
    CallService.instance.removeOnCallStateChangedListener(_onCallStateChanged);

    // NÃO destrói o engine — ele pertence ao CallService
    super.dispose();
  }

  void _onCallStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _ensureVideoEnabled() async {
    if (_engine == null) return;
    try {
      await _engine!.enableVideo();
      await _engine!.startPreview();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('📞 Web Video: Erro ao ativar vídeo: $e');
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        String userMessage = 'Não foi possível ativar sua câmera.';
        if (errorStr.contains('permission') ||
            errorStr.contains('allowed') ||
            errorStr.contains('denied')) {
          userMessage =
              'Permissão de câmera negada pelo navegador. Ative as permissões nas configurações do site.';
        } else if (errorStr.contains('notfound') ||
            errorStr.contains('device')) {
          userMessage = 'Nenhuma câmera detectada no seu dispositivo.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.videocam_off, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(userMessage)),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _toggleMute() async {
    if (_engine == null) return;
    // FIX: Inverte PRIMEIRO, depois aplica o novo estado
    setState(() => _isMuted = !_isMuted);
    await _engine!.muteLocalAudioStream(_isMuted);
  }

  void _toggleVideo() async {
    if (_engine == null) return;
    // FIX: Inverte PRIMEIRO, depois aplica o novo estado
    setState(() => _isVideoOff = !_isVideoOff);
    await _engine!.muteLocalVideoStream(_isVideoOff);
  }

  void _toggleScreenShare() async {
    if (_engine == null) return;
    try {
      if (_isScreenSharing) {
        await _engine!.stopScreenCapture();
        await _engine!.updateChannelMediaOptions(
          const ChannelMediaOptions(
            publishScreenTrack: false,
            publishCameraTrack: true,
          ),
        );
      } else {
        await _engine!.startScreenCapture(const ScreenCaptureParameters2(
          captureAudio: true,
          captureVideo: true,
        ));
        await _engine!.updateChannelMediaOptions(
          const ChannelMediaOptions(
            publishScreenTrack: true,
            publishCameraTrack: false,
          ),
        );
      }
      setState(() => _isScreenSharing = !_isScreenSharing);
    } catch (e) {
      debugPrint('📞 Web: Erro ao alternar screen share: $e');
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        String userMessage = 'Não foi possível compartilhar sua tela.';
        if (errorStr.contains('permission') ||
            errorStr.contains('allowed') ||
            errorStr.contains('denied') ||
            errorStr.contains('cancel')) {
          userMessage = 'Compartilhamento de tela cancelado ou negado.';
        } else if (errorStr.contains('not supported') ||
            errorStr.contains('support')) {
          userMessage = 'Seu navegador não suporta compartilhamento de tela.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.stop_screen_share_rounded,
                    color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(userMessage)),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _leaveChannel() async {
    // Delega o encerramento ao CallService (ele gerencia o engine)
    widget.onEndCall();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Fundo premium escuro
      body: Stack(
        children: [
          _buildVideoArea(),
          _buildTopBar(),
          _buildBottomControls(), // Pill bar
        ],
      ),
    );
  }

  Widget _buildVideoArea() {
    if (!_isJoined) {
      return Container(
        color: const Color(0xFF13131A),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.tealAccent),
              SizedBox(height: 24),
              Text(
                'Conectando...',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Lista final de renderização
    // uid 0 = Eu (Câmera Local)
    // Se "isScreenSharing" for true, o SDK na porta 0 é minha Tela!
    final uids = <int>[0, ...CallService.instance.activeRemoteUids];

    if (_isMeeting) {
      return _buildMeetingGrid(uids);
    } else {
      return _buildOneOnOneLayout(uids);
    }
  }

  Widget _buildMeetingGrid(List<int> uids) {
    // Se alguém está fixado (pinned), usar layout spotlight
    if (_pinnedUid != null && uids.contains(_pinnedUid)) {
      return Positioned.fill(
        child: _buildWebSpotlightLayout(uids),
      );
    }

    // Zoom/Google Meet Style Grid Dinâmico
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = constraints.maxWidth > constraints.maxHeight;
          final count = uids.length;
          int crossAxisCount;

          if (count <= 1) {
            crossAxisCount = 1;
          } else if (count == 2) {
            crossAxisCount = isLandscape ? 2 : 1;
          } else if (count <= 4) {
            crossAxisCount = 2;
          } else if (count <= 9) {
            crossAxisCount = isLandscape ? 3 : 2;
          } else {
            crossAxisCount = isLandscape ? 4 : 3;
          }

          final availableHeight = constraints.maxHeight - 200;
          final rowCount = (count / crossAxisCount).ceil();
          final idealHeightPerItem = availableHeight / rowCount;
          final minHeight = constraints.maxHeight * 0.10;
          final clampHeight =
              idealHeightPerItem > minHeight ? idealHeightPerItem : minHeight;
          final idealAspectRatio =
              (constraints.maxWidth / crossAxisCount) / clampHeight;

          return GridView.builder(
            physics: count <= (crossAxisCount * 3)
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 80, 16, 140),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: idealAspectRatio.clamp(0.6, 1.8),
            ),
            itemCount: count,
            itemBuilder: (context, index) {
              final uid = uids[index];
              return GestureDetector(
                onTap: () => setState(() => _pinnedUid = uid),
                child: _buildTileForUid(uid),
              );
            },
          );
        },
      ),
    );
  }

  /// Layout Spotlight: participante fixado ocupa a maior parte, outros ficam numa barra lateral/inferior
  Widget _buildWebSpotlightLayout(List<int> uids) {
    final pinnedUid = _pinnedUid!;
    final otherUids = uids.where((uid) => uid != pinnedUid).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;

        if (isLandscape) {
          // Landscape: pinned à esquerda (grande), strip vertical à direita
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 80, 16, 140),
            child: Row(
              children: [
                // Vídeo principal fixado
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onDoubleTap: () => setState(() => _pinnedUid = null),
                    child: Stack(
                      children: [
                        _buildTileForUid(pinnedUid),
                        _buildUnpinBadge(),
                      ],
                    ),
                  ),
                ),
                if (otherUids.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  // Strip vertical de participantes
                  SizedBox(
                    width: 160,
                    child: ListView.separated(
                      itemCount: otherUids.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final uid = otherUids[index];
                        return GestureDetector(
                          onTap: () => setState(() => _pinnedUid = uid),
                          child: SizedBox(
                            height: 120,
                            child: _buildTileForUid(uid),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          );
        } else {
          // Portrait: pinned em cima (grande), strip horizontal embaixo
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 80, 16, 140),
            child: Column(
              children: [
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onDoubleTap: () => setState(() => _pinnedUid = null),
                    child: Stack(
                      children: [
                        _buildTileForUid(pinnedUid),
                        _buildUnpinBadge(),
                      ],
                    ),
                  ),
                ),
                if (otherUids.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 110,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: otherUids.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final uid = otherUids[index];
                        return GestureDetector(
                          onTap: () => setState(() => _pinnedUid = uid),
                          child: SizedBox(
                            width: 150,
                            child: _buildTileForUid(uid),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildUnpinBadge() {
    return Positioned(
      top: 12,
      left: 12,
      child: GestureDetector(
        onTap: () => setState(() => _pinnedUid = null),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.tealAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.push_pin, color: Colors.tealAccent, size: 13),
              SizedBox(width: 4),
              Text('Fixado — Toque 2x para soltar',
                  style: TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOneOnOneLayout(List<int> uids) {
    // Layout 1:1 - Chamada Privada
    final remoteUid = uids.length > 1 ? uids[1] : null;

    if (remoteUid == null) {
      return Container(
        color: const Color(0xFF13131A),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.tealAccent),
              SizedBox(height: 16),
              Text('Aguardando participante...',
                  style: TextStyle(color: Colors.white54, fontSize: 18)),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Tela Cheia Oponente
        Positioned.fill(
          child: _buildTileForUid(remoteUid, forceScale: true),
        ),

        // Local PIP superposicionado (Miniatura customizada)
        if (!_isVideoOff || _isScreenSharing)
          Positioned(
            right: 32,
            bottom: 140, // Acima da barra central
            child: Builder(
              builder: (context) {
                final pipWidth =
                    (MediaQuery.of(context).size.shortestSide * 0.35)
                        .clamp(100.0, 220.0);
                return Container(
                  width: pipWidth,
                  height: pipWidth * 1.3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.tealAccent, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildTileForUid(0),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTileForUid(int uid, {bool forceScale = false}) {
    final isLocal = uid == 0;
    final isLocalScreen = isLocal && _isScreenSharing;

    Widget content;

    if (isLocal) {
      if (_isVideoOff && !isLocalScreen) {
        content = Container(
            color: Colors.black,
            child: const Center(
                child:
                    Icon(Icons.videocam_off, color: Colors.white54, size: 48)));
      } else if (_engine != null) {
        content = AgoraVideoView(
          controller: VideoViewController(
            rtcEngine: _engine!,
            useFlutterTexture:
                false, // <-- Crucial: Contorna o CanvasKit no Web
            canvas: const VideoCanvas(
              uid: 0,
              renderMode: RenderModeType.renderModeFit,
            ),
          ),
        );
      } else {
        content = const SizedBox.shrink();
      }
    } else {
      if (_engine != null) {
        content = AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: _engine!,
            useFlutterTexture:
                false, // <-- Crucial: Contorna o CanvasKit no Web
            canvas: VideoCanvas(
              uid: uid,
              renderMode: RenderModeType.renderModeFit,
            ),
            connection: RtcConnection(channelId: widget.channelName),
          ),
        );
      } else {
        content = const SizedBox.shrink();
      }
    }

    final label = isLocal
        ? (isLocalScreen ? 'Sua Tela' : 'Você')
        : (CallService.instance.participantNames[uid] ?? 'Participante');

    final borderColor = isLocal
        ? (isLocalScreen ? Colors.blueAccent : Colors.tealAccent)
        : Colors.white24;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black, // Fundo preto para as bordas não preenchidas
        borderRadius: BorderRadius.circular(16),
        border: forceScale
            ? null
            : Border.all(color: borderColor, width: isLocal ? 2 : 1),
        boxShadow: forceScale
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 2)
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(forceScale ? 0 : 14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Para vídeos remotos na web, usar FittedBox para preservar aspect ratio
            // sem zoom excessivo. Referência 9:16 (retrato) pois câmera e tela do celular são portrait.
            if (!isLocal)
              FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 360,
                  height: 640,
                  child: content,
                ),
              )
            else
              content,
            Positioned(
              bottom: 16,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isLocal)
                      const Icon(Icons.person, color: Colors.white, size: 14)
                    else if (isLocalScreen)
                      const Icon(Icons.screen_share,
                          color: Colors.blueAccent, size: 14)
                    else
                      const Icon(Icons.videocam,
                          color: Colors.tealAccent, size: 14),
                    const SizedBox(width: 6),
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isJoined ? Icons.videocam : Icons.videocam_outlined,
                      color: _isJoined ? Colors.greenAccent : Colors.white54,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.callerName,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isJoined
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isJoined ? Colors.green : Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isJoined
                          ? '${CallService.instance.activeRemoteUids.length + 1} participantes'
                          : 'Conectando...',
                      style: TextStyle(
                        color: _isJoined ? Colors.green : Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Colors.white12, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic_none,
                    label: _isMuted ? 'Mutado' : 'Microfone',
                    onPressed: _toggleMute,
                    isActive: _isMuted,
                    activeColor: Colors.redAccent,
                  ),
                  const SizedBox(width: 12),
                  _buildControlButton(
                    icon: _isVideoOff
                        ? Icons.videocam_off
                        : Icons.videocam_outlined,
                    label: _isVideoOff ? 'S/ Câmera' : 'Câmera',
                    onPressed: _toggleVideo,
                    isActive: _isVideoOff,
                    activeColor: Colors.redAccent,
                  ),
                  const SizedBox(width: 12),
                  _buildControlButton(
                    icon: _isScreenSharing
                        ? Icons.stop_screen_share
                        : Icons.screen_share,
                    label: _isScreenSharing ? 'Parar Tela' : 'Apresentar',
                    onPressed: _toggleScreenShare,
                    isActive: _isScreenSharing,
                    activeColor: Colors.blueAccent,
                  ),
                  const SizedBox(
                      width: 24), // Espaçador separando o botão de desligar
                  Container(
                      width: 1,
                      height: 40,
                      color: Colors.white24), // Divisor vert
                  const SizedBox(width: 24),

                  // Botão de Encerrar em Vermelho
                  GestureDetector(
                    onTap: _leaveChannel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.4),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.call_end, color: Colors.white, size: 24),
                          SizedBox(width: 8),
                          Text('Sair',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isActive,
    Color activeColor = Colors.white24,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? activeColor.withValues(alpha: 0.2)
                : Colors.transparent,
            border: Border.all(
                color: isActive
                    ? activeColor.withValues(alpha: 0.5)
                    : Colors.white12,
                width: 1),
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: isActive ? activeColor : Colors.white),
            iconSize: 22,
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                color: isActive ? activeColor : Colors.white70,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}
