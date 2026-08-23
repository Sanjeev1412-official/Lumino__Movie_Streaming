// ignore_for_file: file_names, unused_element
import 'package:flutter/material.dart';

class BufferedSliderTrackShape extends RoundedRectSliderTrackShape {
  final double bufferedFraction;

  const BufferedSliderTrackShape({required this.bufferedFraction});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    // 1. Draw the normal Material slider track (keeps your existing design).
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );

    // 2. Overlay a thin white "buffer" line.
    if (bufferedFraction <= 0) return;

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final double clamped = bufferedFraction.clamp(0.0, 1.0);
    final double bufferWidth = trackRect.width * clamped;

    // Slightly thinner than the main track so it looks like an overlay line.
    final double bufferHeight = (sliderTheme.trackHeight ?? 4.0) / 3;

    final Rect bufferRect = Rect.fromLTWH(
      trackRect.left,
      trackRect.center.dy - bufferHeight / 2,
      bufferWidth,
      bufferHeight,
    );

    final Paint paint = Paint()
      ..color = Color(0xFFB05C12).withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    context.canvas.drawRRect(
      RRect.fromRectAndRadius(bufferRect, Radius.circular(bufferHeight / 2)),
      paint,
    );
  }
}

class _OverlayHeader extends StatelessWidget {
  final String title;
  const _OverlayHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}