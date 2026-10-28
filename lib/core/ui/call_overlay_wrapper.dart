import 'package:flutter/material.dart';
import 'package:alinha_ja/core/services/call_service.dart';
import 'package:alinha_ja/features/calls/ui/active_call_screen.dart';
import 'package:alinha_ja/core/services/lockscreen_service.dart';

class CallOverlayWrapper extends StatefulWidget {
  final Widget child;

  const CallOverlayWrapper({super.key, required this.child});

  @override
  State<CallOverlayWrapper> createState() => _CallOverlayWrapperState();
}

class _CallOverlayWrapperState extends State<CallOverlayWrapper> {
  final _callService = CallService.instance;
  bool _isMinimized = false;
  Offset _pipPosition = const Offset(20, 20);

  @override
  void initState() {
    super.initState();
    _callService.addOnCallStateChangedListener(_onCallStateChanged);
  }

  @override
  void dispose() {
    _callService.removeOnCallStateChangedListener(_onCallStateChanged);
    super.dispose();
  }

  void _onCallStateChanged() {
    if (mounted) {
      if (!_callService.isInCall) {
        _isMinimized = false;
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isInCall =
        _callService.isInCall && _callService.currentCallId != null;

    final childStack = Stack(
      children: [
        widget.child,
        if (isInCall)
          if (_isMinimized)
            Positioned(
              left: _pipPosition.dx,
              top: _pipPosition.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  final size = MediaQuery.of(context).size;
                  final pipWidth = size.width * 0.45;
                  final pipHeight = size.height * 0.35;
                  setState(() {
                    _pipPosition += details.delta;
                    _pipPosition = Offset(
                      _pipPosition.dx.clamp(0.0, size.width - pipWidth),
                      _pipPosition.dy.clamp(0.0, size.height - pipHeight),
                    );
                  });
                },
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.45,
                    height: MediaQuery.of(context).size.height * 0.35,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.tealAccent.withValues(alpha: 0.5),
                          width: 2),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // The actual call screen but in a small box
                        ActiveCallScreen(
                          key: const ValueKey('pip_active_call'),
                          callerName: _callService.currentCallerName ??
                              _callService.currentChannelName
                                  ?.replaceAll('room_', '')
                                  .replaceAll('call_', '') ??
                              'Chamada',
                          chatId: _callService.currentChatId ?? '',
                          isVideo: _callService.isCurrentCallVideo,
                          isMiniature: true,
                        ),

                        // Restore Button
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton(
                            icon: const Icon(Icons.open_in_full,
                                color: Colors.white, size: 20),
                            onPressed: () {
                              setState(() => _isMinimized = false);
                            },
                          ),
                        ),

                        // End Call Button
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Material(
                            color: Colors.redAccent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                _callService.endCall();
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.call_end,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              child: Material(
                color: Colors.black,
                child: Stack(
                  children: [
                    ActiveCallScreen(
                      key: const ValueKey('full_active_call'),
                      callerName:
                          _callService.currentCallerName ?? 'Chamada Ativa',
                      chatId: _callService.currentChatId ?? '',
                      isVideo: _callService.isCurrentCallVideo,
                      isMiniature: false,
                    ),

                    // Minimize Button
                    Positioned(
                      top: 48,
                      left: 16,
                      child: IconButton(
                        icon: const Icon(Icons.close_fullscreen,
                            color: Colors.white, size: 28),
                        onPressed: () async {
                          final isLocked =
                              await LockscreenService.isDeviceLocked();
                          if (isLocked) {
                            final unlocked =
                                await LockscreenService.requestUnlock();
                            if (!unlocked) return; // Cancela se não desbloquear
                          }
                          setState(() => _isMinimized = true);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (isInCall && !_isMinimized) {
          final isLocked = await LockscreenService.isDeviceLocked();
          if (isLocked) {
            final unlocked = await LockscreenService.requestUnlock();
            if (!unlocked) {
              return true; // Consumido e bloqueia minimização
            }
          }
          setState(() {
            _isMinimized = true;
          });
          return true; // handled
        }
        return false; // not handled, let system process back button
      },
      child: childStack,
    );
  }
}
