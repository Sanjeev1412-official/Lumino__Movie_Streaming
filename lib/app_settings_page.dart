import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lumino_app_moviestreaming/biometric_service.dart';
import 'package:lumino_app_moviestreaming/language_settings_service.dart';
import 'package:lumino_app_moviestreaming/layout_settings_service.dart';
import 'package:lumino_app_moviestreaming/player_settings_service.dart';
import 'package:lumino_app_moviestreaming/player_subtitle_settings_page.dart';
import 'package:lumino_app_moviestreaming/toast.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumino_app_moviestreaming/check_update_page.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final PlayerSettingsService _playerSettingsService = PlayerSettingsService();
  final LayoutSettingsService _layoutSettingsService = LayoutSettingsService();
  final BiometricService _biometricService = BiometricService();
  final LanguageSettingsService _languageService = LanguageSettingsService();
  final TextEditingController _searchController = TextEditingController();

  late PlayerSettings _playerSettings;
  late LayoutSettings _layoutSettings;
  late LanguageOption _selectedLanguage;

  bool _hardwareDecoding = true;
  bool _autoCheckUpdates = true;
  bool _biometricsEnabled = false;
  String _appVersion = '1.3.4';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _playerSettings = _playerSettingsService.current;
    _layoutSettings = _layoutSettingsService.current;
    _selectedLanguage = _languageService.current;
    _biometricsEnabled = _biometricService.isBiometricsEnabled;

    _playerSettingsService.settingsNotifier.addListener(_onSettingsChanged);
    _layoutSettingsService.settingsNotifier.addListener(_onLayoutSettingsChanged);
    _biometricService.isBiometricsEnabledNotifier.addListener(_onBiometricsChanged);
    _languageService.currentLanguageNotifier.addListener(_onLanguageChanged);

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    _loadPrefs();
  }

  @override
  void dispose() {
    _playerSettingsService.settingsNotifier.removeListener(_onSettingsChanged);
    _layoutSettingsService.settingsNotifier.removeListener(_onLayoutSettingsChanged);
    _biometricService.isBiometricsEnabledNotifier.removeListener(_onBiometricsChanged);
    _languageService.currentLanguageNotifier.removeListener(_onLanguageChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onBiometricsChanged() {
    if (mounted) {
      setState(() {
        _biometricsEnabled = _biometricService.isBiometricsEnabled;
      });
    }
  }

  void _onLanguageChanged() {
    if (mounted) {
      setState(() {
        _selectedLanguage = _languageService.current;
      });
    }
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {
        _playerSettings = _playerSettingsService.current;
      });
    }
  }

  void _onLayoutSettingsChanged() {
    if (mounted) {
      setState(() {
        _layoutSettings = _layoutSettingsService.current;
      });
    }
  }

  Future<void> _updateLayoutSettings(LayoutSettings updated) async {
    setState(() => _layoutSettings = updated);
    await _layoutSettingsService.update(updated);
  }

  Future<void> _loadPrefs() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = info.version;
      });
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _hardwareDecoding = prefs.getBool('lumino_hardware_decoding') ?? true;
        _autoCheckUpdates = prefs.getBool('lumino_auto_check_updates') ?? true;
        _biometricsEnabled = prefs.getBool('lumino_biometric_lock_enabled') ?? false;
      });
    } catch (_) {}
  }

  Future<void> _updateSettings(PlayerSettings updated) async {
    setState(() => _playerSettings = updated);
    await _playerSettingsService.update(updated);
  }

  Future<void> _toggleHardwareDecoding(bool val) async {
    setState(() => _hardwareDecoding = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lumino_hardware_decoding', val);
    if (mounted) {
      AppToast.show(context, 'Hardware acceleration ${val ? "enabled" : "disabled"}');
    }
  }

  Future<void> _toggleAutoCheckUpdates(bool val) async {
    setState(() => _autoCheckUpdates = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lumino_auto_check_updates', val);
    if (mounted) {
      AppToast.show(
        context,
        val ? 'App update check on startup enabled' : 'App update check on startup disabled',
      );
    }
  }

  Future<void> _toggleBiometrics(bool val) async {
    final supported = await _biometricService.isDeviceSupported();
    if (!supported && val && !Platform.isWindows) {
      if (mounted) {
        AppToast.show(context, 'Biometrics not supported or setup on this device');
      }
      return;
    }

    final success = await _biometricService.setBiometricEnabled(val);
    if (!success) {
      if (mounted) {
        setState(() {
          _biometricsEnabled = _biometricService.isBiometricsEnabled;
        });
        AppToast.show(context, 'Authentication cancelled or failed');
      }
      return;
    }

    if (mounted) {
      setState(() {
        _biometricsEnabled = val;
      });
      AppToast.show(context, 'Biometric lock ${val ? "enabled" : "disabled"}');
    }
  }

  void _openLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = LanguageSettingsService.supportedLanguages.where((lang) {
              final q = searchQuery.toLowerCase().trim();
              if (q.isEmpty) return true;
              return lang.name.toLowerCase().contains(q) ||
                  lang.nativeName.toLowerCase().contains(q) ||
                  lang.code.toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                color: const Color(0xFF131520),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _buildDullGreyIcon(Icons.translate_rounded),
                      const SizedBox(width: 12),
                      const Text(
                        'App Language',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'Search language...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 13.5,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onChanged: (val) {
                        setModalState(() => searchQuery = val);
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, index) => Divider(
                        color: Colors.white.withValues(alpha: 0.04),
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final lang = filtered[index];
                        final isSelected = lang.code == _selectedLanguage.code;
                        return InkWell(
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _languageService.setLanguage(lang);
                            if (mounted) {
                              setState(() => _selectedLanguage = lang);
                              AppToast.show(this.context, 'Language set to ${lang.name}');
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lang.name,
                                        style: TextStyle(
                                          color: isSelected ? const Color(0xFFFFB561) : Colors.white,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        lang.nativeName,
                                        style: TextStyle(
                                          color: isSelected
                                              ? const Color(0xFFFFB561).withValues(alpha: 0.7)
                                              : Colors.white38,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    lang.code,
                                    style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFFFFB561), size: 20)
                                else
                                  const Icon(Icons.circle_outlined, color: Colors.white24, size: 20),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openSourcePriorityDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String tempQuality = _playerSettings.preferredQuality;
        String tempProvider = _playerSettings.preferredProvider;

        const qualityOptions = [
          {'label': '1080p Full HD', 'sub': 'Recommended for balanced quality & speed', 'val': '1080p'},
          {'label': '4K Ultra HD', 'sub': 'Highest possible resolution and bitrate', 'val': '4K'},
          {'label': '720p HD', 'sub': 'Fast buffering on slower networks', 'val': '720p'},
          {'label': '480p / Auto', 'sub': 'Data saver mode', 'val': '480p'},
        ];

        const providerOptions = [
          {'label': 'Alpha Server', 'sub': 'Primary high-speed streaming server (plays first by default)', 'val': 'Alpha Server'},
          {'label': 'Beta Server', 'sub': 'Secondary fast fallback streaming server', 'val': 'Beta Server'},
        ];

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              decoration: BoxDecoration(
                color: const Color(0xFF131520),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _buildDullGreyIcon(Icons.tune_rounded),
                        const SizedBox(width: 12),
                        const Text(
                          'Source Priority',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Decide how video sources and servers should be sorted in the player',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12.5),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'PREFERRED QUALITY',
                      style: TextStyle(
                        color: Color(0xFFFFB561),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...qualityOptions.map((opt) {
                      final isSelected = tempQuality.toLowerCase() == (opt['val'] as String).toLowerCase();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: isSelected
                              ? const Color(0xFFFFB561).withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.03),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFFFFB561) : Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            onTap: () => setModalState(() => tempQuality = opt['val'] as String),
                            title: Text(
                              opt['label'] as String,
                              style: TextStyle(
                                color: isSelected ? const Color(0xFFFFB561) : Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              opt['sub'] as String,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: Color(0xFFFFB561), size: 18)
                                : null,
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    const Text(
                      'PREFERRED SERVER',
                      style: TextStyle(
                        color: Color(0xFFFFB561),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...providerOptions.map((opt) {
                      final isSelected = tempProvider.toLowerCase() == (opt['val'] as String).toLowerCase();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: isSelected
                              ? const Color(0xFFFFB561).withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.03),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFFFFB561) : Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            onTap: () => setModalState(() => tempProvider = opt['val'] as String),
                            title: Text(
                              opt['label'] as String,
                              style: TextStyle(
                                color: isSelected ? const Color(0xFFFFB561) : Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              opt['sub'] as String,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: Color(0xFFFFB561), size: 18)
                                : null,
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          _updateSettings(_playerSettings.copyWith(
                            preferredQuality: tempQuality,
                            preferredProvider: tempProvider,
                          ));
                          Navigator.pop(ctx);
                          AppToast.show(context, 'Source priority saved');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB561),
                          foregroundColor: const Color(0xFF0C0D12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Save Preference',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openPlaybackSpeedDialog(BuildContext context) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF131520),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _buildDullGreyIcon(Icons.speed_rounded),
                  const SizedBox(width: 12),
                  const Text(
                    'Default Playback Speed',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Choose default playback rate when launching video player',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: speeds.map((s) {
                  final isSelected = (_playerSettings.defaultPlaybackSpeed - s).abs() < 0.05;
                  return InkWell(
                    onTap: () {
                      _updateSettings(_playerSettings.copyWith(defaultPlaybackSpeed: s));
                      Navigator.pop(ctx);
                      AppToast.show(context, 'Default speed set to ${s}x');
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFFB561).withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFFFB561) : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Text(
                        '${s}x',
                        style: TextStyle(
                          color: isSelected ? const Color(0xFFFFB561) : Colors.white70,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _matchesQuery(String title, String subtitle) {
    if (_searchQuery.isEmpty) return true;
    return title.toLowerCase().contains(_searchQuery) ||
        subtitle.toLowerCase().contains(_searchQuery);
  }

  @override
  Widget build(BuildContext context) {
    final bool isSearching = _searchQuery.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF090A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Material(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(context),
              child: const Center(
                child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),
        ),
        title: const Column(
          children: [
            Text(
              'App Settings',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17.5),
            ),
            Text(
              'Preferences & Configuration',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          // ==================== SEARCH BAR ====================
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF131520),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search settings, player, subtitles...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 13.5,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white38,
                  size: 20,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ==================== SECTION 1: SUBTITLES ====================
          if (_hasMatchingSubtitles()) ...[
            _buildSectionTitle('SUBTITLES'),
            _buildCard([
              _buildActionItem(
                context: context,
                icon: Icons.subtitles_rounded,
                title: 'Player Subtitle Settings',
                subtitle: 'Customize appearance, font size, colors, and background',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlayerSubtitleSettingsPage()),
                  );
                },
              ),
            ]),
            const SizedBox(height: 26),
          ],

          // ==================== SECTION 2: PLAYER FEATURES ====================
          if (_hasMatchingPlayerFeatures()) ...[
            _buildSectionTitle('PLAYER FEATURES'),
            _buildCard([
              // 1. Source Priority
              if (_matchesQuery('Source Priority', 'Decide how video sources should be sorted in the player')) ...[
                _buildActionItem(
                  context: context,
                  icon: Icons.tune_rounded,
                  title: 'Source Priority',
                  subtitle: 'Decide how video sources should be sorted in the player',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB561).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFB561).withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      '${_playerSettings.preferredQuality} • ${_playerSettings.preferredProvider}',
                      style: const TextStyle(
                        color: Color(0xFFFFB561),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  onTap: () => _openSourcePriorityDialog(context),
                ),
                _buildDivider(),
              ],

              // 2. Picture-in-Picture (Android/Mobile only)
              if (!Platform.isWindows && _matchesQuery('Picture-in-Picture', 'Continues playback in a miniature player on top of other apps')) ...[
                _buildSwitchItem(
                  icon: Icons.picture_in_picture_alt_rounded,
                  title: 'Picture-in-Picture',
                  subtitle: 'Continues playback in a miniature player on top of other apps',
                  value: _playerSettings.enablePip,
                  onChanged: (val) => _updateSettings(_playerSettings.copyWith(enablePip: val)),
                ),
                _buildDivider(),
              ],

              // 3. Player Resize Button
              if (_matchesQuery('Player Resize Button', 'Remove the black borders or fit video to screen')) ...[
                _buildSwitchItem(
                  icon: Icons.aspect_ratio_rounded,
                  title: 'Player Resize Button',
                  subtitle: 'Remove the black borders or fit video to screen',
                  value: _playerSettings.showResizeButton,
                  onChanged: (val) => _updateSettings(_playerSettings.copyWith(showResizeButton: val)),
                ),
                _buildDivider(),
              ],

              // 4. Playback Speed
              if (_matchesQuery('Playback Speed', 'Add speed option in player default')) ...[
                _buildSwitchItem(
                  icon: Icons.speed_rounded,
                  title: 'Playback Speed',
                  subtitle: 'Add speed option in player (${_playerSettings.defaultPlaybackSpeed}x default)',
                  value: _playerSettings.enablePlaybackSpeed,
                  onChanged: (val) => _updateSettings(_playerSettings.copyWith(enablePlaybackSpeed: val)),
                  onTapSubtitle: () => _openPlaybackSpeedDialog(context),
                ),
                _buildDivider(),
              ],

              // 5. Autoplay Next Episode
              if (_matchesQuery('Autoplay Next Episode', 'Start the next episode when the current one ends')) ...[
                _buildSwitchItem(
                  icon: Icons.queue_play_next_rounded,
                  title: 'Autoplay Next Episode',
                  subtitle: 'Start the next episode when the current one ends',
                  value: _playerSettings.autoPlayNext,
                  onChanged: (val) => _updateSettings(_playerSettings.copyWith(autoPlayNext: val)),
                ),
                _buildDivider(),
              ],

              // 6. Next Episode Button
              if (_matchesQuery('Next Episode Button', 'Show floating quick button to jump to next episode')) ...[
                _buildSwitchItem(
                  icon: Icons.skip_next_rounded,
                  title: 'Next Episode Button',
                  subtitle: 'Show floating quick button to jump to next episode',
                  value: _playerSettings.showNextEpisodeButton,
                  onChanged: (val) => _updateSettings(_playerSettings.copyWith(showNextEpisodeButton: val)),
                ),
                _buildDivider(),
              ],

              // 7. Episode Drawer
              if (_matchesQuery('Episode Drawer', 'Show side drawer button to browse and pick episodes')) ...[
                _buildSwitchItem(
                  icon: Icons.view_sidebar_rounded,
                  title: 'Episode Drawer',
                  subtitle: 'Show side drawer button to browse and pick episodes',
                  value: _playerSettings.enableEpisodeOverlay,
                  onChanged: (val) => _updateSettings(_playerSettings.copyWith(enableEpisodeOverlay: val)),
                ),
              ],
            ]),
            const SizedBox(height: 26),
          ],

          // ==================== SECTION 3: CONTROLS & GESTURES ====================
          if (_hasMatchingControls()) ...[
            _buildSectionTitle(Platform.isWindows ? 'CONTROLS & SHORTCUTS' : 'GESTURES'),
            _buildCard([
              // 1. Double tap / click to seek
              if (_matchesQuery(
                Platform.isWindows ? 'Double Click to Seek' : 'Double Tap to Seek',
                Platform.isWindows ? 'Double click video sides' : 'Double tap screen sides',
              )) ...[
                _buildSwitchItem(
                  icon: Icons.touch_app_rounded,
                  title: Platform.isWindows ? 'Double Click to Seek' : 'Double Tap to Seek',
                  subtitle: Platform.isWindows
                      ? 'Double click video sides to jump backward or forward'
                      : 'Double tap screen sides to jump backward or forward',
                  value: _playerSettings.enableDoubleTapSeek,
                  onChanged: (val) => _updateSettings(_playerSettings.copyWith(enableDoubleTapSeek: val)),
                ),
                _buildDivider(),
              ],

              // 2. Double tap / click to pause
              if (_matchesQuery(
                Platform.isWindows ? 'Double Click to Pause' : 'Double Tap to Pause',
                Platform.isWindows ? 'Double click center of video' : 'Double tap center of screen',
              )) ...[
                _buildSwitchItem(
                  icon: Icons.pause_circle_outline_rounded,
                  title: Platform.isWindows ? 'Double Click to Pause' : 'Double Tap to Pause',
                  subtitle: Platform.isWindows
                      ? 'Double click center of video to play or pause playback'
                      : 'Double tap center of screen to play or pause playback',
                  value: _playerSettings.enableDoubleTapPause,
                  onChanged: (val) => _updateSettings(_playerSettings.copyWith(enableDoubleTapPause: val)),
                ),
                _buildDivider(),
              ],

              // 3. Swipe to change brightness & volume (Mobile only)
              if (!Platform.isWindows &&
                  _matchesQuery('Swipe to Change Brightness & Volume', 'Vertical swipe on left for brightness, right for volume')) ...[
                _buildSwitchItem(
                  icon: Icons.swipe_vertical_rounded,
                  title: 'Swipe to Change Brightness & Volume',
                  subtitle: 'Vertical swipe on left for brightness, right for volume',
                  value: _playerSettings.enableSwipeBrightnessVolume,
                  onChanged: (val) => _updateSettings(_playerSettings.copyWith(enableSwipeBrightnessVolume: val)),
                ),
                _buildDivider(),
              ],

              // 4. Player seek amount in seconds slider
              if (_matchesQuery('Player Seek Amount', 'interval in seconds')) ...[
                _buildSliderItem(
                  icon: Icons.fast_forward_rounded,
                  title: 'Player Seek Amount',
                  subtitle: Platform.isWindows
                      ? 'Arrow keys, buttons & double-click skip interval in seconds'
                      : 'Double tap & button skip interval in seconds',
                  value: _playerSettings.seekDurationSeconds.toDouble(),
                  min: 5,
                  max: 60,
                  divisions: 11,
                  valueLabel: '${_playerSettings.seekDurationSeconds}s',
                  onChanged: (val) {
                    final rounded = (val / 5).round() * 5;
                    _updateSettings(_playerSettings.copyWith(seekDurationSeconds: rounded));
                  },
                ),
              ],
            ]),
            const SizedBox(height: 26),
          ],

          // ==================== SECTION 4: LAYOUT FEATURES ====================
          if (_hasMatchingLayout()) ...[
            _buildSectionTitle('LAYOUT FEATURES'),
            _buildCard([
              // 1. Search Suggestions
              if (_matchesQuery('Search Suggestions', 'Show real-time suggestions and results while typing')) ...[
                _buildSwitchItem(
                  icon: Icons.manage_search_rounded,
                  title: 'Search Suggestions',
                  subtitle: 'Show real-time suggestions and results while typing',
                  value: _layoutSettings.enableSearchSuggestions,
                  onChanged: (val) => _updateLayoutSettings(_layoutSettings.copyWith(enableSearchSuggestions: val)),
                ),
                _buildDivider(),
              ],

              // 2. Show Trailer
              if (_matchesQuery('Show Trailer', 'Display trailer preview button on movie & series details')) ...[
                _buildSwitchItem(
                  icon: Icons.movie_filter_rounded,
                  title: 'Show Trailer',
                  subtitle: 'Display trailer preview button on movie & series details',
                  value: _layoutSettings.showTrailer,
                  onChanged: (val) => _updateLayoutSettings(_layoutSettings.copyWith(showTrailer: val)),
                ),
                _buildDivider(),
              ],

              // 3. Show Cast Panel
              if (_matchesQuery('Show Cast Panel', 'Display Top Cast & Crew section on details page')) ...[
                _buildSwitchItem(
                  icon: Icons.group_rounded,
                  title: 'Show Cast Panel',
                  subtitle: 'Display Top Cast & Crew section on details page',
                  value: _layoutSettings.showCastPanel,
                  onChanged: (val) => _updateLayoutSettings(_layoutSettings.copyWith(showCastPanel: val)),
                ),
                _buildDivider(),
              ],

              // 4. Show Recommendations
              if (_matchesQuery('Show Recommendations', 'Display "More Like This" recommendations on details page')) ...[
                _buildSwitchItem(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Show Recommendations',
                  subtitle: 'Display "More Like This" recommendations on details page',
                  value: _layoutSettings.showRecommendations,
                  onChanged: (val) => _updateLayoutSettings(_layoutSettings.copyWith(showRecommendations: val)),
                ),
                _buildDivider(),
              ],

              // 5. Download Buttons
              if (_matchesQuery('Download Buttons', 'Show download buttons on details and episode cards')) ...[
                _buildSwitchItem(
                  icon: Icons.download_for_offline_rounded,
                  title: 'Download Buttons',
                  subtitle: 'Show download buttons on details and episode cards',
                  value: _layoutSettings.showDownloadButtons,
                  onChanged: (val) => _updateLayoutSettings(_layoutSettings.copyWith(showDownloadButtons: val)),
                ),
                _buildDivider(),
              ],

              // 6. Confirm Before Exiting App
              if (_matchesQuery('Confirm Before Exit', 'Ask for confirmation before closing the application')) ...[
                _buildSwitchItem(
                  icon: Icons.exit_to_app_rounded,
                  title: 'Confirm Before Exit',
                  subtitle: 'Ask for confirmation before closing the application',
                  value: _layoutSettings.confirmExitApp,
                  onChanged: (val) => _updateLayoutSettings(_layoutSettings.copyWith(confirmExitApp: val)),
                ),
              ],
            ]),
            const SizedBox(height: 26),
          ],

          // ==================== SECTION 5: PLAYBACK ENGINE ====================
          if (_hasMatchingEngine()) ...[
            _buildSectionTitle('PLAYBACK & ENGINE'),
            _buildCard([
              _buildSwitchItem(
                icon: Icons.memory_rounded,
                title: 'Hardware Acceleration',
                subtitle: Platform.isWindows
                    ? 'GPU-accelerated video decoding (D3D11 / WebView2)'
                    : 'GPU-accelerated video decoding (MediaCodec / D3D11)',
                value: _hardwareDecoding,
                onChanged: _toggleHardwareDecoding,
              ),
            ]),
            const SizedBox(height: 26),
          ],

          // ==================== SECTION 6: UPDATE & SECURITY ====================
          if (_hasMatchingSecurity()) ...[
            _buildSectionTitle('UPDATE & SECURITY'),
            _buildCard([
              if (_matchesQuery('Check for Updates', 'Scan for the latest Lumino app release and changelog')) ...[
                _buildActionItem(
                  context: context,
                  icon: Icons.system_update_alt_rounded,
                  title: 'Check for Updates',
                  subtitle: 'Scan for the latest Lumino app release and changelog',
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white38),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CheckUpdatePage()),
                    );
                  },
                ),
                _buildDivider(),
              ],
              if (_matchesQuery('Show App Updates', 'Automatically search for new updates after starting app')) ...[
                _buildSwitchItem(
                  icon: Icons.system_update_rounded,
                  title: 'Show App Updates',
                  subtitle: 'Automatically search for new updates after starting app',
                  value: _autoCheckUpdates,
                  onChanged: _toggleAutoCheckUpdates,
                ),
                _buildDivider(),
              ],
              if (_matchesQuery('Lock with Biometrics', 'Unlock the app with fingerprint, face ID, PIN, pattern, and password')) ...[
                _buildSwitchItem(
                  icon: Icons.fingerprint_rounded,
                  title: 'Lock with Biometrics',
                  subtitle: 'Unlock the app with fingerprint, face ID, PIN, pattern, and password',
                  value: _biometricsEnabled,
                  onChanged: _toggleBiometrics,
                ),
              ],
            ]),
            const SizedBox(height: 26),
          ],

          // ==================== SECTION 7: ABOUT LUMINO ====================
          if (_hasMatchingAbout()) ...[
            _buildSectionTitle('ABOUT LUMINO'),
            _buildCard([
              if (_matchesQuery('Lumino', 'Version $_appVersion')) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    children: [
                      _buildDullGreyIcon(Icons.info_outline_rounded),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Lumino',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Version $_appVersion',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Text(
                          'v$_appVersion',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildDivider(),
              ],

              if (_matchesQuery('App Language Settings', '${_selectedLanguage.name} ${_selectedLanguage.nativeName}')) ...[
                _buildActionItem(
                  context: context,
                  icon: Icons.translate_rounded,
                  title: 'App Language Settings',
                  subtitle: '${_selectedLanguage.name} (${_selectedLanguage.nativeName})',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB561).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFB561).withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      _selectedLanguage.code,
                      style: const TextStyle(
                        color: Color(0xFFFFB561),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  onTap: () => _openLanguagePicker(context),
                ),
              ],
            ]),
          ],

          // ==================== EMPTY SEARCH STATE ====================
          if (isSearching && !_hasAnyMatches()) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.search_off_rounded, color: Colors.white38, size: 30),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No matching settings found',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Try searching for another keyword like "player", "language", or "lock"',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasMatchingSubtitles() {
    return _matchesQuery('Player Subtitle Settings', 'Customize appearance, font size, colors, and background');
  }

  bool _hasMatchingPlayerFeatures() {
    return _matchesQuery('Source Priority', 'Decide how video sources should be sorted') ||
        _matchesQuery('Picture-in-Picture', 'miniature player') ||
        _matchesQuery('Player Resize Button', 'black borders') ||
        _matchesQuery('Playback Speed', 'default playback') ||
        _matchesQuery('Autoplay Next Episode', 'next episode') ||
        _matchesQuery('Next Episode Button', 'quick button') ||
        _matchesQuery('Episode Drawer', 'side drawer');
  }

  bool _hasMatchingControls() {
    return _matchesQuery('Double Click to Seek', 'jump backward or forward') ||
        _matchesQuery('Double Tap to Seek', 'jump backward or forward') ||
        _matchesQuery('Double Click to Pause', 'play or pause') ||
        _matchesQuery('Double Tap to Pause', 'play or pause') ||
        _matchesQuery('Swipe to Change Brightness & Volume', 'left for brightness') ||
        _matchesQuery('Player Seek Amount', 'interval in seconds');
  }

  bool _hasMatchingLayout() {
    return _matchesQuery('Search Suggestions', 'real-time suggestions') ||
        _matchesQuery('Show Trailer', 'trailer preview') ||
        _matchesQuery('Show Cast Panel', 'Cast & Crew') ||
        _matchesQuery('Show Recommendations', 'More Like This') ||
        _matchesQuery('Download Buttons', 'download buttons') ||
        _matchesQuery('Confirm Before Exit', 'closing the application');
  }

  bool _hasMatchingEngine() {
    return _matchesQuery('Hardware Acceleration', 'GPU-accelerated video decoding');
  }

  bool _hasMatchingSecurity() {
    return _matchesQuery('Check for Updates', 'Scan for the latest Lumino app release') ||
        _matchesQuery('Show App Updates', 'search for new updates') ||
        _matchesQuery('Lock with Biometrics', 'fingerprint, face ID, PIN');
  }

  bool _hasMatchingAbout() {
    return _matchesQuery('Lumino', 'Version') ||
        _matchesQuery('App Language Settings', 'language');
  }

  bool _hasAnyMatches() {
    return _hasMatchingSubtitles() ||
        _hasMatchingPlayerFeatures() ||
        _hasMatchingControls() ||
        _hasMatchingLayout() ||
        _hasMatchingEngine() ||
        _hasMatchingSecurity() ||
        _hasMatchingAbout();
  }

  Widget _buildDullGreyIcon(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Icon(icon, color: Colors.white60, size: 19),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 15,
            decoration: BoxDecoration(
              color: const Color(0xFFFFB561),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFB561).withValues(alpha: 0.35),
                  blurRadius: 5,
                  spreadRadius: 0.5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    // Filter out potential null or empty children
    final nonNull = children.where((w) => w is! SizedBox || (w.height != 0 && w.width != 0)).toList();
    if (nonNull.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131520),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      color: Colors.white.withValues(alpha: 0.04),
      height: 1,
      indent: 74,
      endIndent: 16,
    );
  }

  Widget _buildActionItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              _buildDullGreyIcon(icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ?trailing,
              if (trailing == null)
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    VoidCallback? onTapSubtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          _buildDullGreyIcon(icon),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: onTapSubtitle,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: onTapSubtitle != null
                          ? const Color(0xFFFFB561).withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.45),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFFFFB561),
            activeTrackColor: const Color(0xFFFFB561).withValues(alpha: 0.28),
            inactiveThumbColor: Colors.white38,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildDullGreyIcon(icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB561).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFFB561).withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  valueLabel,
                  style: const TextStyle(
                    color: Color(0xFFFFB561),
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFFB561),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
              thumbColor: const Color(0xFFFFB561),
              overlayColor: const Color(0xFFFFB561).withValues(alpha: 0.2),
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
