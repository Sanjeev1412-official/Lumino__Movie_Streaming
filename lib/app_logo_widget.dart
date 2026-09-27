import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders either an SVG or a raster network image (PNG/WEBP/JPG) automatically.
/// Normalizes SVG sizing so that vector logos match the visual presence and scale
/// of raster PNG logos within their container.
class AppLogoWidget extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final int? memCacheHeight;
  final Widget? placeholder;
  final Widget Function(BuildContext context)? errorBuilder;
  final double? svgScale;

  const AppLogoWidget({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.centerLeft,
    this.width,
    this.height,
    this.memCacheHeight,
    this.placeholder,
    this.errorBuilder,
    this.svgScale,
  });

  static bool isSvg(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final lower = url.trim().toLowerCase();
    final clean = lower.split('?').first;
    return clean.endsWith('.svg') || lower.contains('.svg');
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      return errorBuilder?.call(context) ?? const SizedBox.shrink();
    }

    if (isSvg(cleanUrl)) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // Normalize SVG scale:
          // SVG movie/show logos typically contain ~15-20% internal margin/padding in their viewBox,
          // whereas TMDB/MovieBox raster PNG logos are tightly cropped to the letterforms.
          // Applying a default normalization factor of 1.18 ensures SVG logos match PNG logos.
          final scale = svgScale ?? 1.18;

          Widget buildSvg({double? w, double? h}) {
            Widget svg = SvgPicture.network(
              cleanUrl,
              fit: fit,
              alignment: alignment,
              width: w,
              height: h,
              placeholderBuilder:
                  placeholder != null ? (_) => placeholder! : null,
              errorBuilder: errorBuilder != null
                  ? (context, error, stackTrace) => errorBuilder!(context)
                  : null,
            );
            if (scale != 1.0) {
              svg = Transform.scale(
                scale: scale,
                alignment: alignment,
                child: svg,
              );
            }
            return svg;
          }

          // 1. If explicit width AND height are passed
          if (width != null && height != null) {
            return SizedBox(
              width: width,
              height: height,
              child: buildSvg(w: width, h: height),
            );
          }

          // 2. If explicit height is passed (e.g. details page with height: 120)
          if (height != null) {
            return SizedBox(
              height: height,
              child: buildSvg(h: height),
            );
          }

          // 3. If explicit width is passed
          if (width != null) {
            return SizedBox(
              width: width,
              child: buildSvg(w: width),
            );
          }

          // 4. Width and height are null, but parent constraints provide bounds
          // (e.g. Card maxHeight: 80, maxWidth: 280 or Hero banner height: 180, width: 550)
          final hasMaxH = constraints.hasBoundedHeight &&
              constraints.maxHeight.isFinite &&
              constraints.maxHeight > 0;
          final hasMaxW = constraints.hasBoundedWidth &&
              constraints.maxWidth.isFinite &&
              constraints.maxWidth > 0;

          if (hasMaxH && hasMaxW) {
            return FittedBox(
              fit: fit,
              alignment: alignment,
              child: buildSvg(),
            );
          }

          if (hasMaxH) {
            return SizedBox(
              height: constraints.maxHeight,
              child: buildSvg(h: constraints.maxHeight),
            );
          }

          if (hasMaxW) {
            return SizedBox(
              width: constraints.maxWidth,
              child: buildSvg(w: constraints.maxWidth),
            );
          }

          // 5. Fallback unconstrained
          return buildSvg();
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: cleanUrl,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      memCacheHeight: memCacheHeight,
      placeholder: placeholder != null ? (_, _) => placeholder! : null,
      errorWidget: errorBuilder != null
          ? (c, _, _) => errorBuilder!(c)
          : (_, _, _) => const SizedBox.shrink(),
    );
  }
}
