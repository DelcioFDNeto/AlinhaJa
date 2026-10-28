import 'package:flutter/material.dart';

/// Botão circular do canto do composer (enviar / microfone).
class ComposerCircleButton extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;

  /// `null` desenha o botão apagado e sem toque.
  final VoidCallback? onTap;

  const ComposerCircleButton({
    super.key,
    required this.icon,
    required this.background,
    required this.foreground,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: onTap == null ? background.withValues(alpha: 0.4) : background,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: foreground, size: 18),
    );

    return onTap == null
        ? button
        : GestureDetector(onTap: onTap, child: button);
  }
}

/// Substitui o campo de texto enquanto o áudio está sendo gravado.
class ComposerRecordingIndicator extends StatelessWidget {
  final Duration duration;

  const ComposerRecordingIndicator({super.key, required this.duration});

  @override
  Widget build(BuildContext context) {
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _PulsingMicIcon(),
          const SizedBox(width: 8),
          Text(
            '${duration.inMinutes}:$seconds',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'Gravando...',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingMicIcon extends StatefulWidget {
  const _PulsingMicIcon();

  @override
  State<_PulsingMicIcon> createState() => _PulsingMicIconState();
}

class _PulsingMicIconState extends State<_PulsingMicIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red.withValues(alpha: 0.2 + 0.3 * _controller.value),
        ),
        child: const Icon(Icons.mic_rounded, color: Colors.red, size: 14),
      ),
    );
  }
}
