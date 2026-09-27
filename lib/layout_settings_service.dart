import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LayoutSettings {
  final bool enableSearchSuggestions;
  final bool showTrailer;
  final bool showCastPanel;
  final bool showRecommendations;
  final bool showDownloadButtons;
  final bool confirmExitApp;

  const LayoutSettings({
    this.enableSearchSuggestions = true,
    this.showTrailer = true,
    this.showCastPanel = true,
    this.showRecommendations = true,
    this.showDownloadButtons = true,
    this.confirmExitApp = true,
  });

  LayoutSettings copyWith({
    bool? enableSearchSuggestions,
    bool? showTrailer,
    bool? showCastPanel,
    bool? showRecommendations,
    bool? showDownloadButtons,
    bool? confirmExitApp,
  }) {
    return LayoutSettings(
      enableSearchSuggestions:
          enableSearchSuggestions ?? this.enableSearchSuggestions,
      showTrailer: showTrailer ?? this.showTrailer,
      showCastPanel: showCastPanel ?? this.showCastPanel,
      showRecommendations: showRecommendations ?? this.showRecommendations,
      showDownloadButtons: showDownloadButtons ?? this.showDownloadButtons,
      confirmExitApp: confirmExitApp ?? this.confirmExitApp,
    );
  }
}

class LayoutSettingsService {
  static final LayoutSettingsService _instance =
      LayoutSettingsService._internal();
  factory LayoutSettingsService() => _instance;
  LayoutSettingsService._internal() {
    _load();
  }

  static const String _keySearchSuggestions =
      'lumino_layout_search_suggestions';
  static const String _keyShowTrailer = 'lumino_layout_show_trailer';
  static const String _keyShowCastPanel = 'lumino_layout_show_cast_panel';
  static const String _keyShowRecommendations =
      'lumino_layout_show_recommendations';
  static const String _keyShowDownloadButtons =
      'lumino_layout_show_download_buttons';
  static const String _keyConfirmExitApp = 'lumino_layout_confirm_exit_app';

  final ValueNotifier<LayoutSettings> settingsNotifier =
      ValueNotifier<LayoutSettings>(const LayoutSettings());

  LayoutSettings get current => settingsNotifier.value;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final searchSug = prefs.getBool(_keySearchSuggestions) ?? true;
      final trailer = prefs.getBool(_keyShowTrailer) ?? true;
      final cast = prefs.getBool(_keyShowCastPanel) ?? true;
      final recs = prefs.getBool(_keyShowRecommendations) ?? true;
      final downloads = prefs.getBool(_keyShowDownloadButtons) ?? true;
      final confirmExit = prefs.getBool(_keyConfirmExitApp) ?? true;

      settingsNotifier.value = LayoutSettings(
        enableSearchSuggestions: searchSug,
        showTrailer: trailer,
        showCastPanel: cast,
        showRecommendations: recs,
        showDownloadButtons: downloads,
        confirmExitApp: confirmExit,
      );
    } catch (e) {
      debugPrint('Error loading layout settings: $e');
    }
  }

  Future<void> update(LayoutSettings newSettings) async {
    settingsNotifier.value = newSettings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
          _keySearchSuggestions, newSettings.enableSearchSuggestions);
      await prefs.setBool(_keyShowTrailer, newSettings.showTrailer);
      await prefs.setBool(_keyShowCastPanel, newSettings.showCastPanel);
      await prefs.setBool(
          _keyShowRecommendations, newSettings.showRecommendations);
      await prefs.setBool(
          _keyShowDownloadButtons, newSettings.showDownloadButtons);
      await prefs.setBool(_keyConfirmExitApp, newSettings.confirmExitApp);
    } catch (e) {
      debugPrint('Error saving layout settings: $e');
    }
  }
}
