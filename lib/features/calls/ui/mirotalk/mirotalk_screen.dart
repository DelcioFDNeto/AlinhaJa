import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'mirotalk_stub.dart'
    if (dart.library.js_interop) 'mirotalk_web.dart'
    if (dart.library.io) 'mirotalk_mobile.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/core/constants.dart';

class MiroTalkScreen extends StatefulWidget {
  final String roomId;
  final String userName;

  const MiroTalkScreen({
    super.key,
    required this.roomId,
    required this.userName,
  });

  @override
  State<MiroTalkScreen> createState() => _MiroTalkScreenState();
}

class _MiroTalkScreenState extends State<MiroTalkScreen> {
  RealtimeChannel? _presenceChannel;
  bool _isEnding = false;
  String? _roomUrl;
  bool _isHost = false;

  @override
  void initState() {
    super.initState();
    _loadRoomInfo();
  }

  Future<void> _loadRoomInfo() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      final room = await supabase
          .from('meetings')
          .select('host_id, mirotalk_url')
          .eq('id', widget.roomId)
          .maybeSingle();

      if (room != null) {
        final hostId = room['host_id'] as String?;
        final url = room['mirotalk_url'] as String?;

        debugPrint('MiroTalkScreen: Sala carregada. hostId=$hostId, url=$url');

        setState(() {
          _roomUrl = url;
          _isHost = hostId == myId;
        });

        _setupPresence();

        if (!kIsWeb) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint(
                'MiroTalkScreen: Chamando joinMirotalkNative com URL: $_roomUrl');
            joinMirotalkNative(
              roomId: widget.roomId,
              userName: widget.userName,
              onClosed: _onClosed,
              mirotalkUrl: _roomUrl,
            );
          });
        }
      } else {
        debugPrint('MiroTalkScreen: Sala não encontrada no banco!');
      }
    } catch (e) {
      debugPrint('Erro ao carregar info da sala: $e');
    }
  }

  void _setupPresence() async {
    _presenceChannel = supabase.channel('mirotalk_${widget.roomId}');

    _presenceChannel!.onPresenceSync((_) {
      // Usado apenas para manter o estado cacheado pela engine Realtime
    });

    _presenceChannel!.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _presenceChannel!.track({
          'user': widget.userName,
          'joined_at': DateTime.now().toIso8601String()
        });
      }
    });
  }

  void _onClosed() async {
    if (_isEnding) return;

    if (_isHost) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Encerrar Reunião?'),
          content: const Text(
              'Você é o criador desta reunião. Deseja encerrar para todos ou apenas sair?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'leave'),
              child: const Text('Apenas Sair'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'end'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Encerrar para Todos'),
            ),
          ],
        ),
      );

      if (choice == 'cancel' || choice == null) return;
      if (choice == 'end') {
        _endMeetingForEveryone();
        return;
      }
    }

    _isEnding = true;
    debugPrint(
        'MiroTalk: Usuario saindo da tela da reuniao (mantendo reuniao ativa).');

    await _presenceChannel?.untrack();
    if (_presenceChannel != null) {
      await supabase.removeChannel(_presenceChannel!);
    }

    if (mounted) {
      if (GoRouter.of(context).canPop()) {
        context.pop();
      } else {
        context.go('/workspace');
      }
    }
  }

  void _leaveScreenOnly() async {
    if (_isEnding) return;
    _isEnding = true;

    await _presenceChannel?.untrack();
    if (_presenceChannel != null) {
      await supabase.removeChannel(_presenceChannel!);
    }

    if (mounted) {
      if (GoRouter.of(context).canPop()) {
        context.pop();
      } else {
        context.go('/workspace');
      }
    }
  }

  void _endMeetingForEveryone() async {
    if (_isEnding) return;
    _isEnding = true;

    debugPrint('MiroTalk: Host encerra reunião globalmente.');
    final ended = await CallService.instance.endMeetingRoom(widget.roomId);

    await _presenceChannel?.untrack();
    if (_presenceChannel != null) {
      await supabase.removeChannel(_presenceChannel!);
    }

    // A sala é liberada de qualquer jeito — o host pediu para sair —, mas o
    // aviso evita que ele acredite ter encerrado para todos quando não foi.
    if (!ended && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Não foi possível encerrar a reunião para todos. Ela pode seguir aberta.'),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (mounted) {
      if (GoRouter.of(context).canPop()) {
        context.pop();
      } else {
        context.go('/workspace');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Se _roomUrl ainda está carregando, usa fallback
      final effectiveUrl =
          _roomUrl ?? 'https://sfu.mirotalk.com/AlinhaJá_${widget.roomId}';
      return buildMirotalkView(
        roomId: widget.roomId,
        userName: widget.userName,
        onClosed: _onClosed,
        mirotalkUrl: effectiveUrl,
        isHost: _isHost,
        onEndMeeting: _endMeetingForEveryone,
      );
    } else {
      // Mobile: mostra botões para reentrar, sair ou encerrar para o host
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Reunião ${AppConstants.appName}'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _onClosed,
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.video_camera_front_rounded,
                  size: 64,
                  color: Colors.white54,
                ),
                const SizedBox(height: 16),
                Text(
                  _roomUrl != null ? 'Videoconferência ${AppConstants.appName}' : 'Carregando...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (_roomUrl != null)
                  const Text(
                    'Você está conectado à videoconferência.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                const SizedBox(height: 32),
                if (_roomUrl == null)
                  const CircularProgressIndicator()
                else ...[
                  SizedBox(
                    width: 280,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        joinMirotalkNative(
                          roomId: widget.roomId,
                          userName: widget.userName,
                          onClosed: _onClosed,
                          mirotalkUrl: _roomUrl,
                        );
                      },
                      icon: const Icon(Icons.videocam_rounded),
                      label: const Text('Entrar / Reentrar na Chamada'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 280,
                    child: OutlinedButton.icon(
                      onPressed: _leaveScreenOnly,
                      icon: const Icon(Icons.exit_to_app_rounded),
                      label: const Text('Voltar para o Chat'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (_isHost) ...[
                    const SizedBox(height: 24),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 280,
                      child: ElevatedButton.icon(
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
                                  child: const Text('Encerrar'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            _endMeetingForEveryone();
                          }
                        },
                        icon: const Icon(Icons.cancel_presentation_rounded),
                        label: const Text('Encerrar para Todos'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      );
    }
  }
}
