import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:alinha_ja/core/services/call_service.dart';

class ParticipantGrid extends StatefulWidget {
  final List<int> uids;
  final bool isMeeting;
  final String callerName;
  final bool isMiniature;
  final Duration callDuration;
  final bool isConnected;
  final Widget? bottomControlBar;

  const ParticipantGrid({
    super.key,
    required this.uids,
    required this.isMeeting,
    required this.callerName,
    required this.isMiniature,
    required this.callDuration,
    required this.isConnected,
    this.bottomControlBar,
  });

  @override
  State<ParticipantGrid> createState() => _ParticipantGridState();
}

class _ParticipantGridState extends State<ParticipantGrid> {
  final _callService = CallService.instance;
  int? _pinnedUid;
  Offset _pipOffset = const Offset(16, 160);

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
  Widget build(BuildContext context) {
    // Se é conferência (N:N) ou tem mais de 2 participantes → Grid
    if (widget.isMeeting || widget.uids.length > 2) {
      return _buildConferenceGrid();
    }
    // Se é 1:1 → Layout PIP
    return _buildOneToOneVideoLayout();
  }

  // ─── 1:1 VIDEO: Remoto fullscreen + Local PIP arrastável ───
  Widget _buildOneToOneVideoLayout() {
    final remoteUid = widget.uids.length > 1 ? widget.uids[1] : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fundo: Remoto em fullscreen (ou "Aguardando...")
          if (remoteUid != null &&
              _callService.engine != null &&
              _callService.currentChannelName != null)
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                clipBehavior: Clip.none,
                child: AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: _callService.engine!,
                    canvas: VideoCanvas(
                      uid: remoteUid,
                      renderMode: RenderModeType.renderModeFit,
                    ),
                    connection: RtcConnection(
                        channelId: _callService.currentChannelName!),
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                color: const Color(0xFF13131A),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.tealAccent),
                      const SizedBox(height: 16),
                      Text(
                        'Aguardando ${widget.callerName}...',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // PIP local arrastável (posição rastreada)
          if (_callService.engine != null)
            Positioned(
              right: _pipOffset.dx,
              bottom: _pipOffset.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _pipOffset = Offset(
                      (_pipOffset.dx - details.delta.dx)
                          .clamp(0, MediaQuery.of(context).size.width - 100),
                      (_pipOffset.dy - details.delta.dy)
                          .clamp(0, MediaQuery.of(context).size.height - 100),
                    );
                  });
                },
                child: Builder(
                  builder: (context) {
                    final pipWidth =
                        (MediaQuery.of(context).size.shortestSide * 0.35)
                            .clamp(100.0, 220.0);
                    return Container(
                      width: pipWidth,
                      height: pipWidth * 1.33,
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
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 4.0,
                          clipBehavior: Clip.none,
                          child: AgoraVideoView(
                            controller: VideoViewController(
                              rtcEngine: _callService.engine!,
                              canvas: const VideoCanvas(
                                uid: 0,
                                renderMode: RenderModeType.renderModeFit,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Info do participante remoto
          if (remoteUid != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.videocam,
                                color: Colors.greenAccent, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              widget.callerName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.isConnected
                              ? _formatDuration(widget.callDuration)
                              : 'Conectando...',
                          style: TextStyle(
                            color: widget.isConnected
                                ? Colors.greenAccent
                                : Colors.orange,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Injetar status da rede no topo-direito
          if (remoteUid != null && !widget.isMiniature)
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildNetworkQualityIndicator(),
                ),
              ),
            ),

          // Barra de controle
          if (widget.bottomControlBar != null) widget.bottomControlBar!,
        ],
      ),
    );
  }

  // ─── CONFERÊNCIA N:N: Grid adaptativo ───
  Widget _buildConferenceGrid() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SafeArea(
            child: _pinnedUid != null
                ? _buildSpotlightLayout()
                : _buildGridLayout(),
          ),

          // Header da conferência
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.groups,
                              color: Colors.tealAccent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '${widget.uids.length} participantes',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.isConnected
                            ? _formatDuration(widget.callDuration)
                            : 'Conectando...',
                        style: TextStyle(
                          color: widget.isConnected
                              ? Colors.greenAccent
                              : Colors.orange,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Barra de controle
          if (widget.bottomControlBar != null) widget.bottomControlBar!,
        ],
      ),
    );
  }

  // ─── Helper: Renderiza um tile de vídeo individual ───
  Widget _buildVideoTile(int uid,
      {double? width, double? height, bool showName = true}) {
    final isSpeaker = _callService.activeSpeakers[uid] == true;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: isSpeaker
            ? Border.all(color: Colors.greenAccent, width: 3)
            : Border.all(color: Colors.white10, width: 1),
        color: Colors.grey.shade900,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_callService.engine != null &&
              _callService.currentChannelName != null)
            uid == 0
                ? AgoraVideoView(
                    controller: VideoViewController(
                      rtcEngine: _callService.engine!,
                      canvas: const VideoCanvas(
                        uid: 0,
                        renderMode: RenderModeType.renderModeFit,
                      ),
                    ),
                  )
                : InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    clipBehavior: Clip.none,
                    child: AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: _callService.engine!,
                        canvas: VideoCanvas(
                          uid: uid,
                          renderMode: RenderModeType.renderModeFit,
                        ),
                        connection: RtcConnection(
                            channelId: _callService.currentChannelName!),
                      ),
                    ),
                  ),
          if (showName)
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  uid == 0
                      ? 'Você'
                      : (_callService.participantNames[uid] ?? 'Conectando...'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── SPOTLIGHT MODE: Pinned user fills main area, others in strip ───
  Widget _buildSpotlightLayout() {
    final pinnedUid = _pinnedUid!;
    final otherUids = widget.uids.where((uid) => uid != pinnedUid).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;

        if (isLandscape) {
          // Landscape: pinned à esquerda, strip vertical à direita
          return Padding(
            padding: const EdgeInsets.only(top: 60, bottom: 140),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: GestureDetector(
                      onDoubleTap: () => setState(() => _pinnedUid = null),
                      child: Stack(
                        children: [
                          _buildVideoTile(pinnedUid, showName: true),
                          _buildMobileUnpinBadge(),
                        ],
                      ),
                    ),
                  ),
                ),
                if (otherUids.isNotEmpty)
                  SizedBox(
                    width: 130,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 4),
                      itemCount: otherUids.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final uid = otherUids[index];
                        return GestureDetector(
                          onTap: () => setState(() => _pinnedUid = uid),
                          child: _buildVideoTile(uid, height: 100),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        } else {
          // Portrait: pinned em cima, strip horizontal embaixo
          return Column(
            children: [
              const SizedBox(height: 60),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GestureDetector(
                    onDoubleTap: () => setState(() => _pinnedUid = null),
                    child: Stack(
                      children: [
                        _buildVideoTile(pinnedUid, showName: true),
                        _buildMobileUnpinBadge(),
                      ],
                    ),
                  ),
                ),
              ),
              if (otherUids.isNotEmpty)
                Container(
                  height: 110,
                  margin: const EdgeInsets.only(top: 6),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: otherUids.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final uid = otherUids[index];
                      return GestureDetector(
                        onTap: () => setState(() => _pinnedUid = uid),
                        child: _buildVideoTile(uid, width: 150, height: 110),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 140),
            ],
          );
        }
      },
    );
  }

  Widget _buildMobileUnpinBadge() {
    return Positioned(
      top: 8,
      left: 8,
      child: GestureDetector(
        onTap: () => setState(() => _pinnedUid = null),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.tealAccent.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.push_pin, color: Colors.tealAccent, size: 12),
              SizedBox(width: 4),
              Text('Fixado',
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

  // ─── GRID MODE: Grid adaptativo padrão ───
  Widget _buildGridLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final count = widget.uids.length;
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
        final idealHeight = availableHeight / rowCount;
        final minHeight = constraints.maxHeight * 0.10;
        final clampedHeight = idealHeight > minHeight ? idealHeight : minHeight;
        final aspectRatio = crossAxisCount == 0 || clampedHeight <= 0
            ? 1.0
            : ((constraints.maxWidth / crossAxisCount) / clampedHeight);

        return GridView.builder(
          physics: count <= (crossAxisCount * 3)
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          padding:
              const EdgeInsets.only(top: 60, left: 8, right: 8, bottom: 140),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount == 0 ? 1 : crossAxisCount,
            childAspectRatio: aspectRatio.clamp(0.5, 1.8),
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: count,
          itemBuilder: (context, index) {
            final uid = widget.uids[index];
            return GestureDetector(
              onTap: () => setState(() => _pinnedUid = uid),
              child: _buildVideoTile(uid),
            );
          },
        );
      },
    );
  }

  Widget _buildNetworkQualityIndicator() {
    final tx = _callService.txNetworkQuality;
    final rx = _callService.rxNetworkQuality;
    // Pega o pior quality (maior valor de index no enum)
    final worstQualityIndex = (tx.index > rx.index) ? tx.index : rx.index;

    // 0 = Unknown, 1 = Excellent, 2 = Good, 3 = Poor, 4 = Bad, 5 = VBad, 6 = Down
    IconData icon = Icons.signal_cellular_alt;
    Color color = Colors.greenAccent;
    String label = 'Boa';

    if (worstQualityIndex == 0) {
      color = Colors.grey;
      icon = Icons.signal_cellular_0_bar;
      label = '...';
    } else if (worstQualityIndex <= 2) {
      color = Colors.greenAccent;
      label = 'Boa';
    } else if (worstQualityIndex <= 4) {
      color = Colors.orangeAccent;
      label = 'Média';
    } else {
      color = Colors.redAccent;
      icon = Icons.signal_cellular_connected_no_internet_4_bar;
      label = 'Ruim';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
