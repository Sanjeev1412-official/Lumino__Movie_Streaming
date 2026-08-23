import 'package:flutter/material.dart';

class SeekCircleButton extends StatefulWidget {
  final bool isForward; // true = 10s forward, false = 10s back
  final VoidCallback? onTap;
  final bool big;

  const SeekCircleButton({
    super.key,
    required this.isForward,
    this.onTap,
    this.big = false,
  });

  @override
  State<SeekCircleButton> createState() => _SeekCircleButtonState();
}

class _SeekCircleButtonState extends State<SeekCircleButton>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _pulseController;
  
  late final Animation<double> _scale;
  late final Animation<double> _rotation;
  late final Animation<double> _pulseOpacity;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    
    // Main scale/rotate animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.85), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.1), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _rotation = Tween<double>(
      begin: 0.0,
      end: widget.isForward ? 0.3 : -0.3,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    // Pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _pulseOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.4), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.4, end: 0.0), weight: 80),
    ]).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));

    _pulseScale = Tween<double>(begin: 0.6, end: 1.5)
        .animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    _controller.forward(from: 0.0);
    _pulseController.forward(from: 0.0);
    widget.onTap!.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final size = widget.big ? 70.0 : 56.0;
    
    return GestureDetector(
      onTap: enabled ? _handleTap : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, _pulseController]),
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Expanding pulse ring
                Transform.scale(
                  scale: _pulseScale.value,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: _pulseOpacity.value),
                        width: 2,
                      ),
                    ),
                  ),
                ),

                // Main glassmorphic button
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: enabled ? 0.10 : 0.05),
                        Colors.white.withValues(alpha: enabled ? 0.04 : 0.02),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 2,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: enabled ? 0.15 : 0.05),
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Transform.rotate(
                        angle: _rotation.value,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              widget.isForward
                                  ? Icons.forward_10_rounded
                                  : Icons.replay_10_rounded,
                              size: widget.big ? 44 : 34,
                              color: enabled ? Colors.white : Colors.white24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}