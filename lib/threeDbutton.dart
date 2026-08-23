// ignore_for_file: file_names
import 'package:flutter/material.dart';

/// Public shape enum so you can choose between pill and circle.
enum ThreeDButtonShape { pill, circle }

class ThreeDButton3D extends StatelessWidget {
  final VoidCallback? onTap;
  final String? label; // used for pill style (season chip)
  final bool isSelected;
  final ThreeDButtonShape shape;
  final Widget? icon; // used for circle style (play button)
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  const ThreeDButton3D({
    super.key,
    required this.onTap,
    required this.isSelected,
    required this.shape,
    this.label,
    this.icon,
    this.padding,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    const baseColor = Color(0xFFFF8C1A);
    const darkBase = Color(0xFFB05C12);

    final isCircle = shape == ThreeDButtonShape.circle;
    final bodyHeight = height ?? (isCircle ? 40.0 : 32.0);
    final outerHeight = bodyHeight + (isSelected ? 5 : 3);

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding:
            padding ?? const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: SizedBox(
          // Outer size: we can optionally fix width here if provided
          height: outerHeight,
          width:
              width, // THIS is where width is applied, not inside AnimatedContainer
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ---------- bottom plate for 3D depth ----------
              Positioned(
                left: 0,
                right: 0,
                top: isSelected ? 5 : 3,
                child: Container(
                  height: bodyHeight,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: isCircle ? null : BorderRadius.circular(20),
                  ),
                ),
              ),

              // ---------- main body ----------
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  // Inner fixed body size (NON-animated)
                  height: bodyHeight,
                  width: width, // safe: this SizedBox is NOT animated
                  child: AnimatedContainer(
                    // IMPORTANT:
                    //  - NO width
                    //  - NO height
                    //  - NO constraints
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: isCircle ? null : BorderRadius.circular(20),
                      gradient: isSelected
                          ? const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFFFC57A), baseColor, darkBase],
                            )
                          : const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF252A36), Color(0xFF171B26)],
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          offset: const Offset(0, 4),
                          blurRadius: 10,
                          spreadRadius: 0,
                        ),
                        if (isSelected)
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.12),
                            offset: const Offset(0, -2),
                            blurRadius: 4,
                            spreadRadius: 0,
                          ),
                      ],
                    ),
                    padding: isCircle
                        ? EdgeInsets.zero
                        : const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      child: isCircle
                          ? (icon ??
                              Icon(
                                Icons.play_arrow_rounded,
                                size: 20,
                                color:
                                    isSelected ? Colors.black : Colors.white,
                              ))
                          : Text(
                              label ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                letterSpacing: 0.2,
                                color:
                                    isSelected ? Colors.black : Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
