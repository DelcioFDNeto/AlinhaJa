import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/calls/ui/web_agora_view.dart';
import 'package:alinha_ja/core/services/lockscreen_service.dart';
import 'package:alinha_ja/features/calls/ui/widgets/call_control_bar.dart';
import 'package:alinha_ja/features/calls/ui/widgets/participant_grid.dart';

/// Tela de chamada ativa — exibida quando o usuário está em uma ligação.
/// Suporta o Layout de Voz Premium (Redesign) e Layout Multiparticipantes (Vídeo).
class ActiveCallScreen extends StatefulWidget {
  final String callerName;
  final String chatId;
  final bool isVideo;
  final bool isMiniature;
  final bool isRouted;

  const ActiveCallScreen({
    super.key,
    required this.callerName,
    required this.chatId,
    this.isVideo = false,
    this.isMiniature = false,
    this.isRouted = false,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _callService = CallService.instance;
  late final AnimationController _pulseController;
  Duration _callDuration = Duration.zero;
  bool _isConnected = false;
  int? _pinnedUid;
  bool _isHost = false;
  Timer? _callTimer;

  bool _canPop = false;
  bool _hasPopped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Mostra a tela de chamada sobrepondo a tela de bloqueio do SO apenas se não for miniatura
    LockscreenService.setCallScreenVisible(!widget.isMiniature);

    // Animação de pulso no avatar enquanto conecta
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Registrar callbacks do CallService
    _callService.addOnCallStateChangedListener(_onCallStateChanged);
    _callService.addRemoteUserJoinedListener(_onRemoteJoined);
    _callService.addRemoteUserLeftListener(_onRemoteLeft);

    // Timer de duração
    _startDurationTimer();

    // Check Host
    _checkIfHost();
  }

  Future<void> _checkIfHost() async {
    final callId = CallService.instance.currentCallId;
    if (callId == null) return;
    try {
      // Só tenta consultar meetings se for uma videoconferência (prefix 'room_')
      if (_callService.currentChannelName?.startsWith('room_') == true) {
        final roomId =
            _callService.currentChannelName!.replaceFirst('room_', '');
        final meetingData = await supabase
            .from('meetings')
            .select('host_id')
            .eq('id', roomId)
            .maybeSingle();
        if (meetingData != null &&
            meetingData['host_id'] == supabase.auth.currentUser?.id) {
          if (mounted) setState(() => _isHost = true);
          return;
        }
      }

      // Fallback para tabela calls
      final data = await supabase
          .from('calls')
          .select('caller_id')
          .eq('id', callId)
          .maybeSingle();
      if (data != null && data['caller_id'] == supabase.auth.currentUser?.id) {
        if (mounted) setState(() => _isHost = true);
      }
    } catch (e) {
      debugPrint('Erro ao verificar host: $e');
    }
  }

  void _startDurationTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isConnected) {
        setState(() {
          _callDuration += const Duration(seconds: 1);
        });
      }
    });
  }

  void _onCallStateChanged() {
    if (mounted) {
      if (!_callService.isInCall) {
        _callTimer?.cancel();
        if (_pulseController.isAnimating) {
          _pulseController.stop();
        }
        setState(() {
          _canPop = true;
          _isConnected = false;
        });
        // Tenta fechar a tela independentemente de ser routed ou overlay
        if (widget.isRouted && ModalRoute.of(context) != null && !_hasPopped) {
          _hasPopped = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).maybePop();
            }
          });
        }
        // Se não é routed (overlay), o CallOverlayWrapper já reage ao isInCall=false
      } else {
        setState(() {});
      }
    }
  }

  void _onRemoteJoined(int uid) {
    if (mounted) {
      if (!_isConnected) {
        setState(() {
          _isConnected = true;
        });
        _pulseController.stop();
      } else {
        setState(() {}); // Atualiza o grid
      }
    }
  }

  void _onRemoteLeft(int uid) {
    if (mounted) {
      if (_pinnedUid == uid) _pinnedUid = null;
      if (_callService.activeRemoteUids.isEmpty) {
        _callTimer?.cancel();
        if (_pulseController.isAnimating) {
          _pulseController.stop();
        }
      }
      setState(() {
        if (_callService.activeRemoteUids.isEmpty) {
          _isConnected = false;
        }
      });
    }
  }

  Future<void> _endCall() async {
    if (!_isConnected) {
      await _callService.cancelCall();
    } else {
      await _callService.endCall();
    }
    // We only pop if we were pushed as a route. In PiP/Overlay mode, the wrapper handles unmounting.
    if (mounted &&
        widget.isRouted &&
        ModalRoute.of(context) != null &&
        !_hasPopped) {
      setState(() {
        _canPop = true;
        _hasPopped = true;
      });
      Navigator.of(context).maybePop();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Esconde a tela e devolve a restrição do Keyguard
    LockscreenService.setCallScreenVisible(false);

    // Oculto o "endCall" aqui porque a engine deve continuar viva
    // quando a tela recria no formato Miniatura (PIP).
    _callService.removeOnCallStateChangedListener(_onCallStateChanged);
    _callService.removeRemoteUserJoinedListener(_onRemoteJoined);
    _callService.removeRemoteUserLeftListener(_onRemoteLeft);
    _pulseController.dispose();
    _callTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isConnected) {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMiniature) {
      return PopScope<Object?>(
        canPop: _canPop,
        onPopInvokedWithResult: (didPop, result) {
          // No miniature, podemos apenas ignorar ou permitir se _canPop for true (fim da chamada)
        },
        child: _buildBody(context),
      );
    }

    return PopScope<Object?>(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // Exige desbloqueio antes de deixar o usuário sair da tela de chamada ativamente
        // Timeout de 5s para evitar travamento
        final unlockFuture = LockscreenService.requestUnlock();
        final unlocked = await unlockFuture.timeout(
          const Duration(seconds: 5),
          onTimeout: () => false, // Timeout = bloqueia saída por segurança
        );
        if (unlocked && context.mounted && ModalRoute.of(context) != null) {
          setState(() {
            _canPop = true;
          });
          Navigator.of(context).maybePop();
        }
      },
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (kIsWeb && widget.isVideo) {
      return _buildWebVideoCallView();
    }
    if (widget.isVideo) {
      return _buildVideoLayout(context);
    } else {
      return _buildVoiceLayout(context);
    }
  }

  // ─── Web Video Call View (Agora Web SDK) ───
  Widget _buildWebVideoCallView() {
    // Usar o channelName REAL do CallService (pode ser 'room_xxx' para meetings ou 'call_xxx' para 1:1)
    final channelName =
        _callService.currentChannelName ?? 'call_${widget.chatId}';

    return WebAgoraView(
      roomUrl: channelName, // Passa o channelName real para o widget
      callerName: widget.callerName,
      onEndCall: _endCall,
    );
  }

  // ─── LOTE 1: REDESIGN DE VOZ (Background Dinâmico, Caller ID no Topo) ───
  Widget _buildVoiceLayout(BuildContext context) {
    final initial =
        widget.callerName.isNotEmpty ? widget.callerName[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        children: [
          // Background Borrado
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.teal.shade800, Colors.teal.shade900],
                ),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(color: Colors.black.withValues(alpha: 0.6)),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 1),

                  // Avatar pulsante ou fixo
                  if (!_isConnected)
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final scale = 1.0 + (_pulseController.value * 0.08);
                        return Transform.scale(scale: scale, child: child);
                      },
                      child:
                          _buildAvatarItem(initial, isActive: false, size: 140),
                    )
                  else
                    _buildAvatarItem(initial,
                        isActive: _callService.activeRemoteUids.isNotEmpty
                            ? _callService.activeSpeakers[
                                    _callService.activeRemoteUids.first] ==
                                true
                            : false,
                        size: 140),

                  const SizedBox(height: 32),
                  Text(
                    widget.callerName,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isConnected
                        ? _formatDuration(_callDuration)
                        : 'Conectando...',
                    style: TextStyle(
                      fontSize: 18,
                      color: _isConnected
                          ? Colors.greenAccent.shade200
                          : Colors.white60,
                      fontWeight: FontWeight.w400,
                    ),
                  ),

                  if (!widget.isMiniature) ...[
                    const Spacer(flex: 3),
                    CallControlBar(
                      isVideo: false,
                      isHost: _isHost,
                      isMiniature: false,
                      onEndCall: _endCall,
                      onShowParticipants: _showParticipantsBottomSheet,
                      onRefresh: () => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    const Spacer(),
                    // Controles minimalistas
                    CallControlBar(
                      isVideo: false,
                      isHost: _isHost,
                      isMiniature: true,
                      onEndCall: _endCall,
                      onShowParticipants: _showParticipantsBottomSheet,
                      onRefresh: () => setState(() {}),
                    ),
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── LAYOUT DE VÍDEO (NATIVO) ───
  Widget _buildVideoLayout(BuildContext context) {
    final uids = <int>[0, ..._callService.activeRemoteUids];
    final bool isMeeting =
        _callService.currentChannelName?.startsWith('room_') == true;

    return ParticipantGrid(
      uids: uids,
      isMeeting: isMeeting,
      callerName: widget.callerName,
      isMiniature: widget.isMiniature,
      callDuration: _callDuration,
      isConnected: _isConnected,
      bottomControlBar: Positioned.fill(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: CallControlBar(
                  isVideo: true,
                  isHost: _isHost,
                  isMiniature: widget.isMiniature,
                  onEndCall: _endCall,
                  onShowParticipants: _showParticipantsBottomSheet,
                  onRefresh: () => setState(() {}),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarItem(String initial,
      {required bool isActive, double size = 80}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.teal.shade400, Colors.teal.shade700],
        ),
        border:
            isActive ? Border.all(color: Colors.greenAccent, width: 4) : null,
        boxShadow: isActive
            ? [
                BoxShadow(
                    color: Colors.greenAccent.withValues(alpha: 0.6),
                    blurRadius: 20,
                    spreadRadius: 5)
              ]
            : [
                BoxShadow(
                    color: Colors.teal.withValues(alpha: 0.2),
                    blurRadius: 15,
                    spreadRadius: 2)
              ],
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ─── LOTE 4: CONTROLES DE HOST E SESSÃO ───
  void _showParticipantsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            // Listener temporário para atualizar ao vivo
            void onStateChanged() {
              if (sheetCtx.mounted) setSheetState(() {});
            }

            _callService.addOnCallStateChangedListener(onStateChanged);
            // Limpar ao fechar o sheet
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!sheetCtx.mounted) {
                _callService.removeOnCallStateChangedListener(onStateChanged);
              }
            });

            final uids = _callService.activeRemoteUids;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gestão de Participantes',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const SizedBox(height: 16),
                    if (uids.isEmpty)
                      const Text('Nenhum participante conectado.',
                          style: TextStyle(color: Colors.white70)),
                    ...uids.map((uid) => ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.teal.shade700,
                            child: Text(
                                _callService.participantNames[uid]
                                        ?.substring(0, 1) ??
                                    uid.toString().substring(0, 1),
                                style: const TextStyle(color: Colors.white)),
                          ),
                          title: Text(
                              _callService.participantNames[uid] ?? 'ID $uid',
                              style: const TextStyle(color: Colors.white)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Silenciar para mim',
                                icon: const Icon(Icons.volume_off,
                                    color: Colors.orangeAccent),
                                onPressed: () {
                                  _callService.engine?.muteRemoteAudioStream(
                                      uid: uid, mute: true);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Áudio silenciado para você.')));
                                },
                              ),
                              IconButton(
                                tooltip: 'Bloquear Streams',
                                icon: const Icon(Icons.block,
                                    color: Colors.redAccent),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _confirmExpel(uid);
                                },
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmExpel(int uid) {
    final name = _callService.participantNames[uid] ?? 'ID $uid';
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Bloquear Streams',
            style: TextStyle(color: Colors.white)),
        content: Text(
            'Bloquear o áudio e vídeo de $name? '
            '(O participante ainda estará conectado, mas você não receberá seus streams.)',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              _callService.engine?.muteRemoteAudioStream(uid: uid, mute: true);
              _callService.engine?.muteRemoteVideoStream(uid: uid, mute: true);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Streams de $name bloqueados.')));
            },
            child: const Text('Bloquear',
                style: TextStyle(color: Colors.redAccent)),
          )
        ],
      ),
    );
  }
}
