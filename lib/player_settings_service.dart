import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerSettings {
  final String preferredQuality;
  final String preferredProvider;
  final bool enablePip;
  final bool showResizeButton;
  final bool enablePlaybackSpeed;
  final double defaultPlaybackSpeed;
  final bool autoPlayNext;
  final bool showNextEpisodeButton;
  final bool enableEpisodeOverlay;
  final bool enableDoubleTapSeek;
  final bool enableDoubleTapPause;
  final bool enableSwipeBrightnessVolume;
  final int seekDurationSeconds;

  const PlayerSettings({
    this.preferredQuality = '1080p',
    this.preferredProvider = 'Alpha Server',
    this.enablePip = true,
    this.showResizeButton = true,
    this.enablePlaybackSpeed = true,
    this.defaultPlaybackSpeed = 1.0,
    this.autoPlayNext = true,
    this.showNextEpisodeButton = true,
    this.enableEpisodeOverlay = true,
    this.enableDoubleTapSeek = true,
    this.enableDoubleTapPause = true,
    this.enableSwipeBrightnessVolume = true,
    this.seekDurationSeconds = 10,
  });

  PlayerSettings copyWith({
    String? preferredQuality,
    String? preferredProvider,
    bool? enablePip,
    bool? showResizeButton,
    bool? enablePlaybackSpeed,
    double? defaultPlaybackSpeed,
    bool? autoPlayNext,
    bool? showNextEpisodeButton,
    bool? enableEpisodeOverlay,
    bool? enableDoubleTapSeek,
    bool? enableDoubleTapPause,
    bool? enableSwipeBrightnessVolume,
    int? seekDurationSeconds,
  }) {
    return PlayerSettings(
      preferredQuality: preferredQuality ?? this.preferredQuality,
      preferredProvider: preferredProvider ?? this.preferredProvider,
      enablePip: enablePip ?? this.enablePip,
      showResizeButton: showResizeButton ?? this.showResizeButton,
      enablePlaybackSpeed: enablePlaybackSpeed ?? this.enablePlaybackSpeed,
      defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      showNextEpisodeButton:
          showNextEpisodeButton ?? this.showNextEpisodeButton,
      enableEpisodeOverlay:
          enableEpisodeOverlay ?? this.enableEpisodeOverlay,
      enableDoubleTapSeek: enableDoubleTapSeek ?? this.enableDoubleTapSeek,
      enableDoubleTapPause: enableDoubleTapPause ?? this.enableDoubleTapPause,
      enableSwipeBrightnessVolume:
          enableSwipeBrightnessVolume ?? this.enableSwipeBrightnessVolume,
      seekDurationSeconds: seekDurationSeconds ?? this.seekDurationSeconds,
    );
  }

  List<String> getQualityPriority() {
    switch (preferredQuality.toLowerCase()) {
      case '4k':
      case '2160p':
        return const ['4K', '2160p', '1440p', '1080p', '1080P', '720p', '720P', '480p', '360p'];
      case '720p':
        return const ['720p', '720P', '1080p', '1080P', '4K', '2160p', '480p', '360p'];
      case '480p':
        return const ['480p', '360p', '720p', '720P', '1080p', '1080P', '4K'];
      case '1080p':
      default:
        return const ['1080p', '1080P', '720p', '720P', '4K', '2160p', '1440p', '480p', '360p'];
    }
  }

  List<String> getProviderPriority() {
    if (preferredProvider.toLowerCase().contains('beta')) {
      return const ['Beta Server', 'Alpha Server'];
    }
    return const ['Alpha Server', 'Beta Server'];
  }
}

class PlayerSettingsService {
  static final PlayerSettingsService _instance = PlayerSettingsService._internal();
  factory PlayerSettingsService() => _instance;
  PlayerSettingsService._internal() {
    _load();
  }

  static const String _keyQuality = 'lumino_player_preferred_quality';
  static const String _keyProvider = 'lumino_player_preferred_provider';
  static const String _keyPip = 'lumino_player_enable_pip';
  static const String _keyResize = 'lumino_player_show_resize';
  static const String _keySpeedEnabled = 'lumino_player_speed_enabled';
  static const String _keyDefaultSpeed = 'lumino_player_default_speed';
  static const String _keyAutoPlayNext = 'lumino_autoplay_next';
  static const String _keyNextEpisodeBtn = 'lumino_show_next_episode_btn';
  static const String _keyEpisodeOverlay = 'lumino_enable_episode_overlay';
  static const String _keyDoubleTapSeek = 'lumino_double_tap_seek';
  static const String _keyDoubleTapPause = 'lumino_double_tap_pause';
  static const String _keySwipeBrightnessVolume = 'lumino_swipe_brightness_volume';
  static const String _keySeekDuration = 'lumino_player_seek_duration';

  final ValueNotifier<PlayerSettings> settingsNotifier =
      ValueNotifier<PlayerSettings>(const PlayerSettings());

  PlayerSettings get current => settingsNotifier.value;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final q = prefs.getString(_keyQuality) ?? '1080p';
      var prov = prefs.getString(_keyProvider) ?? 'Alpha Server';
      if (prov != 'Alpha Server' && prov != 'Beta Server') {
        prov = prov.toLowerCase().contains('beta') ? 'Beta Server' : 'Alpha Server';
      }
      final pip = prefs.getBool(_keyPip) ?? true;
      final resize = prefs.getBool(_keyResize) ?? true;
      final speedEnabled = prefs.getBool(_keySpeedEnabled) ?? true;
      final defSpeed = prefs.getDouble(_keyDefaultSpeed) ?? 1.0;
      final autoNext = prefs.getBool(_keyAutoPlayNext) ?? true;
      final nextEpBtn = prefs.getBool(_keyNextEpisodeBtn) ?? true;
      final epOverlay = prefs.getBool(_keyEpisodeOverlay) ?? true;
      final doubleTapSeek = prefs.getBool(_keyDoubleTapSeek) ?? true;
      final doubleTapPause = prefs.getBool(_keyDoubleTapPause) ?? true;
      final swipeBv = prefs.getBool(_keySwipeBrightnessVolume) ?? true;
      final seekDur = prefs.getInt(_keySeekDuration) ?? 10;

      settingsNotifier.value = PlayerSettings(
        preferredQuality: q,
        preferredProvider: prov,
        enablePip: pip,
        showResizeButton: resize,
        enablePlaybackSpeed: speedEnabled,
        defaultPlaybackSpeed: defSpeed,
        autoPlayNext: autoNext,
        showNextEpisodeButton: nextEpBtn,
        enableEpisodeOverlay: epOverlay,
        enableDoubleTapSeek: doubleTapSeek,
        enableDoubleTapPause: doubleTapPause,
        enableSwipeBrightnessVolume: swipeBv,
        seekDurationSeconds: seekDur,
      );
    } catch (e) {
      debugPrint('Error loading player settings: $e');
    }
  }

  Future<void> update(PlayerSettings newSettings) async {
    settingsNotifier.value = newSettings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyQuality, newSettings.preferredQuality);
      await prefs.setString(_keyProvider, newSettings.preferredProvider);
      await prefs.setBool(_keyPip, newSettings.enablePip);
      await prefs.setBool(_keyResize, newSettings.showResizeButton);
      await prefs.setBool(_keySpeedEnabled, newSettings.enablePlaybackSpeed);
      await prefs.setDouble(_keyDefaultSpeed, newSettings.defaultPlaybackSpeed);
      await prefs.setBool(_keyAutoPlayNext, newSettings.autoPlayNext);
      await prefs.setBool(_keyNextEpisodeBtn, newSettings.showNextEpisodeButton);
      await prefs.setBool(_keyEpisodeOverlay, newSettings.enableEpisodeOverlay);
      await prefs.setBool(_keyDoubleTapSeek, newSettings.enableDoubleTapSeek);
      await prefs.setBool(_keyDoubleTapPause, newSettings.enableDoubleTapPause);
      await prefs.setBool(_keySwipeBrightnessVolume, newSettings.enableSwipeBrightnessVolume);
      await prefs.setInt(_keySeekDuration, newSettings.seekDurationSeconds);
    } catch (e) {
      debugPrint('Error saving player settings: $e');
    }
  }
}
