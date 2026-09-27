import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SubtitleEdgeStyle {
  none,
  dropShadow,
  outline,
  raised,
  depressed,
}

enum SubtitleBackgroundStyle {
  none,
  subtle,
  semiTransparent,
  solid,
}

class SubtitleSettings {
  final double fontSize;
  final Color textColor;
  final bool isBold;
  final String fontFamily;
  final SubtitleEdgeStyle edgeStyle;
  final Color edgeColor;
  final SubtitleBackgroundStyle backgroundStyle;
  final Color backgroundColor;
  final double bottomPadding;
  final TextAlign textAlign;

  const SubtitleSettings({
    this.fontSize = 24.0,
    this.textColor = Colors.white,
    this.isBold = false,
    this.fontFamily = 'sans-serif',
    this.edgeStyle = SubtitleEdgeStyle.outline,
    this.edgeColor = Colors.black,
    this.backgroundStyle = SubtitleBackgroundStyle.none,
    this.backgroundColor = Colors.black,
    this.bottomPadding = 35.0,
    this.textAlign = TextAlign.center,
  });

  SubtitleSettings copyWith({
    double? fontSize,
    Color? textColor,
    bool? isBold,
    String? fontFamily,
    SubtitleEdgeStyle? edgeStyle,
    Color? edgeColor,
    SubtitleBackgroundStyle? backgroundStyle,
    Color? backgroundColor,
    double? bottomPadding,
    TextAlign? textAlign,
  }) {
    return SubtitleSettings(
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      isBold: isBold ?? this.isBold,
      fontFamily: fontFamily ?? this.fontFamily,
      edgeStyle: edgeStyle ?? this.edgeStyle,
      edgeColor: edgeColor ?? this.edgeColor,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      bottomPadding: bottomPadding ?? this.bottomPadding,
      textAlign: textAlign ?? this.textAlign,
    );
  }

  double get bgOpacity {
    switch (backgroundStyle) {
      case SubtitleBackgroundStyle.none:
        return 0.0;
      case SubtitleBackgroundStyle.subtle:
        return 0.35;
      case SubtitleBackgroundStyle.semiTransparent:
        return 0.65;
      case SubtitleBackgroundStyle.solid:
        return 1.0;
    }
  }

  List<Shadow> get shadows {
    switch (edgeStyle) {
      case SubtitleEdgeStyle.none:
        return const [];
      case SubtitleEdgeStyle.dropShadow:
        return [
          Shadow(
            offset: const Offset(2.0, 2.0),
            blurRadius: 4.0,
            color: edgeColor.withValues(alpha: 0.9),
          ),
        ];
      case SubtitleEdgeStyle.outline:
        return [
          Shadow(offset: const Offset(-1.5, -1.5), color: edgeColor),
          Shadow(offset: const Offset(1.5, -1.5), color: edgeColor),
          Shadow(offset: const Offset(-1.5, 1.5), color: edgeColor),
          Shadow(offset: const Offset(1.5, 1.5), color: edgeColor),
          Shadow(offset: const Offset(0, -1.5), color: edgeColor),
          Shadow(offset: const Offset(0, 1.5), color: edgeColor),
          Shadow(offset: const Offset(-1.5, 0), color: edgeColor),
          Shadow(offset: const Offset(1.5, 0), color: edgeColor),
        ];
      case SubtitleEdgeStyle.raised:
        return [
          Shadow(offset: const Offset(-1.0, -1.0), color: Colors.white.withValues(alpha: 0.4)),
          Shadow(offset: const Offset(2.0, 2.0), color: edgeColor),
        ];
      case SubtitleEdgeStyle.depressed:
        return [
          Shadow(offset: const Offset(1.0, 1.0), color: Colors.white.withValues(alpha: 0.35)),
          Shadow(offset: const Offset(-2.0, -2.0), color: edgeColor),
        ];
    }
  }

  TextStyle toTextStyle() {
    return TextStyle(
      fontSize: fontSize,
      height: 1.3,
      color: textColor,
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      fontFamily: fontFamily == 'sans-serif' ? null : fontFamily,
      backgroundColor: bgOpacity > 0 ? backgroundColor.withValues(alpha: bgOpacity) : null,
      shadows: shadows,
      letterSpacing: 0.2,
    );
  }

  SubtitleViewConfiguration toSubtitleViewConfiguration() {
    return SubtitleViewConfiguration(
      style: toTextStyle(),
      textAlign: textAlign,
      padding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, bottomPadding),
      textScaler: TextScaler.noScaling,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fontSize': fontSize,
      'textColor': textColor.toARGB32(),
      'isBold': isBold,
      'fontFamily': fontFamily,
      'edgeStyle': edgeStyle.index,
      'edgeColor': edgeColor.toARGB32(),
      'backgroundStyle': backgroundStyle.index,
      'backgroundColor': backgroundColor.toARGB32(),
      'bottomPadding': bottomPadding,
      'textAlign': textAlign.index,
    };
  }

  factory SubtitleSettings.fromJson(Map<String, dynamic> json) {
    return SubtitleSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 24.0,
      textColor: json['textColor'] != null ? Color(json['textColor'] as int) : Colors.white,
      isBold: json['isBold'] as bool? ?? false,
      fontFamily: json['fontFamily'] as String? ?? 'sans-serif',
      edgeStyle: json['edgeStyle'] != null
          ? SubtitleEdgeStyle.values[(json['edgeStyle'] as int).clamp(0, SubtitleEdgeStyle.values.length - 1)]
          : SubtitleEdgeStyle.outline,
      edgeColor: json['edgeColor'] != null ? Color(json['edgeColor'] as int) : Colors.black,
      backgroundStyle: json['backgroundStyle'] != null
          ? SubtitleBackgroundStyle.values[(json['backgroundStyle'] as int).clamp(0, SubtitleBackgroundStyle.values.length - 1)]
          : SubtitleBackgroundStyle.none,
      backgroundColor: json['backgroundColor'] != null ? Color(json['backgroundColor'] as int) : Colors.black,
      bottomPadding: (json['bottomPadding'] as num?)?.toDouble() ?? 35.0,
      textAlign: json['textAlign'] != null
          ? TextAlign.values[(json['textAlign'] as int).clamp(0, TextAlign.values.length - 1)]
          : TextAlign.center,
    );
  }
}

class SubtitleSettingsService {
  static final SubtitleSettingsService _instance = SubtitleSettingsService._internal();
  factory SubtitleSettingsService() => _instance;
  SubtitleSettingsService._internal() {
    _load();
  }

  static const String _prefKey = 'lumino_player_subtitle_settings_v1';
  final ValueNotifier<SubtitleSettings> settingsNotifier =
      ValueNotifier<SubtitleSettings>(const SubtitleSettings());

  SubtitleSettings get current => settingsNotifier.value;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        settingsNotifier.value = SubtitleSettings.fromJson(data);
      }
    } catch (e) {
      debugPrint('Error loading subtitle settings: $e');
    }
  }

  Future<void> save(SubtitleSettings settings) async {
    settingsNotifier.value = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Error saving subtitle settings: $e');
    }
  }

  Future<void> resetToDefaults() async {
    const defaults = SubtitleSettings();
    await save(defaults);
  }
}
