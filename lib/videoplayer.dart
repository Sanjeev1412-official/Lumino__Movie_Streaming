// ignore_for_file: dead_code, dead_null_aware_expression, deprecated_member_use, unused_element, unused_field, unused_local_variable, use_build_context_synchronously
// lib/video_player_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
// <-- NEW
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lumino_app_moviestreaming/BufferedSliderTrackShape.dart';
import 'package:lumino_app_moviestreaming/primebox_service.dart';
import 'package:lumino_app_moviestreaming/seekcirclebtn.dart';
import 'package:lumino_app_moviestreaming/threeDbutton.dart';
import 'package:lumino_app_moviestreaming/toast.dart';
import 'package:file_picker/file_picker.dart';

// media_kit
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:lumino_app_moviestreaming/config/env_config.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lumino_app_moviestreaming/watch_history_service.dart';
import 'package:lumino_app_moviestreaming/notification_service.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

// --- NEW: resize modes ---
enum _ResizeMode { fit, zoom, stretch }

class TvSeasonMeta {
  final int seasonNumber;
  final String? name;
  final int? episodeCount; // NEW

  const TvSeasonMeta({
    required this.seasonNumber,
    this.name,
    this.episodeCount,
  });
}

class TvEpisodeSummary {
  final int season;
  final int episode;
  final String title;
  final int? runtime;
  final String? overview;
  final String? stillPath;

  const TvEpisodeSummary({
    required this.season,
    required this.episode,
    required this.title,
    this.runtime,
    this.overview,
    this.stillPath,
  });
}

class VideoPlayerScreen extends StatefulWidget {
  // NEW main props
  final String title;
  final String episodeTitle;

  /// 4KHDHub: quality -> provider -> url
  final Map<String, Map<String, String>>? httpSources;

  /// torrent entries from DetailsPage
  final List<Map<String, dynamic>>? torrentStreams;
  final String? initialQuality;

  // Legacy / fallback props (still supported, but we treat them as httpSources/mediaUrl)
  final String? mediaUrl;
  final Map<String, Map<String, String>>? sources;
  final String? initialProviderPreference;

  /// OPTIONAL: URL template to load thumbnails for preview while scrubbing.
  /// Example: 'https://example.com/thumbs/{second}.jpg'
  /// We'll replace '{second}' with the integer second position.
  final String? thumbnailUrlTemplate;

  final bool isTvShow; // true if this is a TV series episode
  final int? tmdbId; // TMDB TV id
  final String? imdbId;
  final String? tmdbApiBase; // e.g. https://api.themoviedb.org/3
  final String? tmdbApiKey;
  final List<TvSeasonMeta>? seasonsMeta; // list of seasons
  final int? initialSeason; // currently playing season
  final int? initialEpisode; // currently playing episode
  final Future<Map<String, dynamic>?> Function(
    int season,
    int episode,
    String title,
  )?
  onEpisodeSelected; // ask parent to fetch and play that episode

  /// Subtitles from LookMovie2 /api/extract.
  /// Format: { "English": ["https://url1", ...], "French": [...] }
  final Map<String, List<String>>? subtitleUrls;

  final bool isLiveTv;

  const VideoPlayerScreen({
    super.key,
    required this.title,
    required this.episodeTitle,
    this.httpSources,
    this.torrentStreams,
    this.initialQuality,
    this.mediaUrl,
    this.sources,
    this.initialProviderPreference,
    this.thumbnailUrlTemplate, // <-- NEW
    // --- TV show / episode browser ---
    this.isTvShow = false,
    this.tmdbId,
    this.imdbId,
    this.tmdbApiBase,
    this.tmdbApiKey,
    this.seasonsMeta,
    this.initialSeason,
    this.initialEpisode,
    this.onEpisodeSelected,
    this.subtitleUrls,
    this.posterPath,
    this.primeboxUrl,
    this.primeboxSubjectType,
    this.primeboxType,
    this.movieboxSubjectId,
    this.initialPosition,
    this.isOffline = false,
    this.videoUrl,
    this.externalDubs,
    this.httpMetadata,
    this.isLiveTv = false,
  });

  final bool isOffline;
  final String? videoUrl;

  final String? posterPath;
  final String? primeboxUrl;
  final int? primeboxSubjectType;
  final String? primeboxType;
  final String? movieboxSubjectId;
  final Duration? initialPosition;
  final List<Map<String, dynamic>>? externalDubs;
  final Map<String, dynamic>? httpMetadata;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

//                                                             vvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with SingleTickerProviderStateMixin {
  // media_kit core
  late final Player _player;
  late final VideoController _videoController;
  Player? _previewPlayer;
  VideoController? _previewController;
  int _lastSeekTime = 0;
  Timer? _seekDebounceTimer;

  // Playback state
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _showControls = true;
  bool _isSwitching = false;
  bool _hasOpenedSource = false;
  int _playerKey = 0; // force Video rebuild if needed
  Timer? _hideControlsTimer;

  // External player state
  bool _isExternalPlayerRunning = false;
  Process? _externalProcess;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  // Panels
  bool _showTracksPanel = false;
  bool _showQualityPanel = false;
  bool _wasPlayingBeforeOverlay = false;

  // Tracks (UI-level)
  Map<int, String> _audioTracks = {};
  int? _selectedAudioTrack; // index in _audioTrackObjs or null
  Map<int, String> _subtitleTracks = {};
  int? _selectedSubtitleTrack; // index in _subtitleTrackObjs or -1 for disabled
  int? _pendingAudioTrack;
  int? _pendingSubtitleTrack;
  bool _tracksLoaded = false;

  // Underlying media_kit track objects
  List<AudioTrack> _audioTrackObjs = [];
  List<SubtitleTrack> _subtitleTrackObjs = [];

  // Quality/Source state
  final List<String> _qOrder = const [
    '4K',
    '2160p',
    '1440p',
    '1080p',
    '720p',
    '480p',
    '360p',
  ];
  String _selectedQuality = '4K';
  String? _selectedProviderLabel; // HTTP provider or torrent label for display
  String? _selectedSourceId; // 'http|quality|provider' or 'torrent|hash'
  bool _selectedIsTorrent = false;

  // Torrent backend state
  String? _currentTorrentStreamId;

  // Gesture controls (Mobile: Right = Volume, Left = Brightness)
  double _volume = 1.0; // 0.0 to 1.0
  double _brightness = 1.0; // 0.01 to 1.0
  bool _showVolumeHud = false;
  bool _showBrightnessHud = false;
  Timer? _gestureHudTimer;

  // Gesture thresholds and edge exclusions
  static const double _edgeHorizontalMargin =
      48.0; // ignore 48px from left & right edges
  static const double _edgeTopMargin =
      50.0; // ignore 50px from top edge (header / controls)
  static const double _edgeBottomMargin =
      65.0; // ignore 65px from bottom edge (seekbar / bottom bar)
  static const double _dragSlopThreshold =
      12.0; // require 12px drag movement to trigger

  // Track active vertical drag to avoid side switching mid-gesture
  bool? _isDraggingLeft;
  bool _hasExceededSlop = false;
  double _accumulatedDy = 0.0;

  // Double tap seek feedback
  bool _showLeftSeekRipple = false;
  bool _showRightSeekRipple = false;
  int _seekAccumulatedSeconds = 0;
  int _seekAnimTriggerKey = 0;
  Timer? _seekRippleTimer;

  Future<void> _initNativeControls() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await FlutterVolumeController.updateShowSystemUI(false);
      }
    } catch (_) {}

    try {
      final currentVol = await FlutterVolumeController.getVolume();
      if (currentVol != null && mounted) {
        setState(() {
          _volume = currentVol.clamp(0.0, 1.0);
        });
        _player.setVolume((_volume * 250.0).clamp(0.0, 350.0));
      }
    } catch (e) {
      debugPrint('Volume controller getVolume error: $e');
    }

    try {
      FlutterVolumeController.addListener((vol) {
        // Prevent async volume listener from clobbering active drag updates
        if (mounted && _isDraggingLeft == null) {
          setState(() {
            _volume = vol.clamp(0.0, 1.0);
            _showVolumeHud = true;
            _showBrightnessHud = false;
          });
          _player.setVolume((_volume * 250.0).clamp(0.0, 350.0));
          _resetGestureHudTimer();
        }
      });
    } catch (e) {
      debugPrint('Volume controller addListener error: $e');
    }

    try {
      final currentBrightness = await ScreenBrightness.instance.application;
      if (mounted && currentBrightness > 0.0) {
        setState(() {
          _brightness = currentBrightness.clamp(0.01, 1.0);
        });
      }
    } catch (_) {
      try {
        final sysBrightness = await ScreenBrightness.instance.system;
        if (mounted && sysBrightness > 0.0) {
          setState(() {
            _brightness = sysBrightness.clamp(0.01, 1.0);
          });
        }
      } catch (e2) {
        debugPrint('Screen brightness init error: $e2');
      }
    }
  }

  Future<void> _setNativeBrightness(double val) async {
    if (kIsWeb) return;
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(val);
    } catch (e) {
      debugPrint('Failed to set application screen brightness: $e');
    }
  }

  Future<void> _setNativeVolume(double val) async {
    try {
      _player.setVolume((val * 250.0).clamp(0.0, 350.0));
    } catch (_) {}

    if (kIsWeb) return;
    try {
      await FlutterVolumeController.setVolume(val);
    } catch (e) {
      debugPrint('Failed to set native volume: $e');
    }
  }

  void _resetGestureHudTimer() {
    _gestureHudTimer?.cancel();
    _gestureHudTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          _showVolumeHud = false;
          _showBrightnessHud = false;
        });
      }
    });
  }

  void _onVerticalDragStart(
    DragStartDetails details,
    BoxConstraints constraints,
  ) {
    final x = details.localPosition.dx;
    final y = details.localPosition.dy;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;

    // 1. Ignore if starting within edge margins (left/right/top/bottom)
    if (x < _edgeHorizontalMargin || x > (width - _edgeHorizontalMargin)) {
      _isDraggingLeft = null;
      return;
    }
    if (y < _edgeTopMargin || y > (height - _edgeBottomMargin)) {
      _isDraggingLeft = null;
      return;
    }

    // 2. Ignore center deadzone (middle 12% between 44% and 56% width)
    if (x > (width * 0.44) && x < (width * 0.56)) {
      _isDraggingLeft = null;
      return;
    }

    _isDraggingLeft = x < (width / 2);
    _hasExceededSlop = false;
    _accumulatedDy = 0.0;
  }

  void _onVerticalDragUpdate(
    DragUpdateDetails details,
    BoxConstraints constraints,
  ) {
    if (_isDraggingLeft == null) return;

    // 3. Miss-touch protection: Accumulate movement until threshold is passed
    if (!_hasExceededSlop) {
      _accumulatedDy += details.delta.dy.abs();
      if (_accumulatedDy < _dragSlopThreshold) {
        return;
      }
      _hasExceededSlop = true;
      _gestureHudTimer?.cancel();
      setState(() {
        if (_isDraggingLeft == true) {
          _showBrightnessHud = true;
          _showVolumeHud = false;
        } else {
          _showVolumeHud = true;
          _showBrightnessHud = false;
        }
      });
    }

    // 4. Smooth delta calculation
    final delta = -details.delta.dy / (constraints.maxHeight * 0.65);

    if (_isDraggingLeft == true) {
      final newBrightness = (_brightness + delta).clamp(0.01, 1.0);
      setState(() {
        _brightness = newBrightness;
        _showBrightnessHud = true;
        _showVolumeHud = false;
      });
      _setNativeBrightness(newBrightness);
    } else {
      final newVolume = (_volume + delta).clamp(0.0, 1.0);
      setState(() {
        _volume = newVolume;
        _showVolumeHud = true;
        _showBrightnessHud = false;
      });
      _setNativeVolume(newVolume);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _isDraggingLeft = null;
    _hasExceededSlop = false;
    _accumulatedDy = 0.0;
    _resetGestureHudTimer();
  }

  void _onVerticalDragCancel() {
    _isDraggingLeft = null;
    _hasExceededSlop = false;
    _accumulatedDy = 0.0;
    _resetGestureHudTimer();
  }

  void _onDoubleTapDown(TapDownDetails details, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final x = details.localPosition.dx;
    if (x < width * 0.4) {
      _triggerSeek(isLeft: true);
    } else if (x > width * 0.6) {
      _triggerSeek(isLeft: false);
    } else {
      _togglePlayPause();
    }
  }

  void _triggerSeek({required bool isLeft}) {
    _seekBy(Duration(seconds: isLeft ? -10 : 10));

    setState(() {
      if (isLeft) {
        if (_showRightSeekRipple) {
          _showRightSeekRipple = false;
          _seekAccumulatedSeconds = 0;
        }
        _showLeftSeekRipple = true;
      } else {
        if (_showLeftSeekRipple) {
          _showLeftSeekRipple = false;
          _seekAccumulatedSeconds = 0;
        }
        _showRightSeekRipple = true;
      }
      _seekAccumulatedSeconds += 10;
      _seekAnimTriggerKey++;
    });

    _seekRippleTimer?.cancel();
    _seekRippleTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) {
        setState(() {
          _showLeftSeekRipple = false;
          _showRightSeekRipple = false;
          _seekAccumulatedSeconds = 0;
        });
      }
    });
  }

  // Subscriptions
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<bool>? _completedSub; // <--- ADD THIS
  StreamSubscription<dynamic>? _errorSub;
  StreamSubscription<double>? _volumeSub;
  Timer? _historyTimer;
  String? _currentEpisodeTitle;

  String _cleanTitle(String t) {
    // 1. Remove bracketed text like [Hindi], [Dual Audio], [720p]
    t = t.replaceAll(RegExp(r'\[.*?\]'), '');
    // 2. Remove Season ranges like S1-S5, S01-S05, S1 to S5
    t = t.replaceAll(RegExp(r'S\d+\s*-\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+\s*to\s*S\d+', caseSensitive: false), '');
    // 3. Remove single Season/Episode markers
    t = t.replaceAll(RegExp(r'Season\s+\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'Episode\s+\d+', caseSensitive: false), '');
    // 4. Remove "Hindi Dubbed", "Eng Sub" etc.
    t = t.replaceAll(RegExp(r'Hindi\s+Dub\w*', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'Eng\w*\s+Sub\w*', caseSensitive: false), '');
    // 5. Remove year in parentheses: (2024)
    t = t.replaceAll(RegExp(r'\(\d{4}\)'), '');
    // 6. Remove special characters but keep spaces/letters/numbers
    t = t.replaceAll(RegExp(r'[^\w\s]'), '');
    return t.trim().replaceAll(RegExp(r'\s+'), ' '); // normalize spaces
  }

  String get _videoTitle {
    final cleanName = _cleanTitle(widget.title);
    if (widget.isTvShow && _currentSeason != null && _currentEpisode != null) {
      return cleanName;
    }
    return cleanName;
  }

  String get _videoSubtitle {
    if (widget.isTvShow && _currentSeason != null && _currentEpisode != null) {
      final epTitle = (_currentEpisodeTitle ?? '').trim();
      if (epTitle.isNotEmpty) {
        return 'S$_currentSeason • E$_currentEpisode — $epTitle';
      } else {
        return 'S$_currentSeason • E$_currentEpisode';
      }
    }
    return _currentEpisodeTitle ?? '';
  }

  Future<void> _loadEpisodeTitleFromTMDB() async {
    if (_currentSeason == null || _currentEpisode == null) return;
    final title = await _fetchEpisodeTitleFromTMDB(
      _currentSeason!,
      _currentEpisode!,
    );
    if (title != null && title.trim().isNotEmpty && mounted) {
      setState(() {
        _currentEpisodeTitle = title;
      });
    }
  }

  Future<void> _fetchDetailsFromApi(String subjectId) async {
    try {
      final res = await http.get(
        Uri.parse(
          '${EnvConfig.lambdaUrl}/details?id=$subjectId',
        ),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data != null && mounted) {
          setState(() {
            if (data['logo'] != null)
              _currentHttpMetadata['logo'] = data['logo'];
            if (data['plot'] != null)
              _currentHttpMetadata['plot'] = data['plot'];
            if (data['rating'] != null)
              _currentHttpMetadata['rating'] = data['rating'];
            if (data['duration'] != null)
              _currentHttpMetadata['duration'] = data['duration'];
            if (data['year'] != null)
              _currentHttpMetadata['year'] = data['year'];
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching details from API: $e');
    }
  }

  late Map<String, Map<String, String>> _currentHttpSources = {};
  Map<String, dynamic> _currentHttpMetadata = {};

  // --- NEW: State variables for in-place episode switching ---
  late int? _currentSeason = widget.initialSeason;
  late int? _currentEpisode = widget.initialEpisode;
  late Map<String, List<String>>? _currentSubtitleUrls = widget.subtitleUrls;
  late List<Map<String, dynamic>> _currentTorrentStreams =
      widget.torrentStreams ?? const [];
  late List<Map<String, dynamic>>? _currentExternalDubs = widget.externalDubs;
  late Duration? _currentInitialPosition = widget.initialPosition;

  Map<String, Map<String, String>> get _httpSources =>
      _currentHttpSources.isNotEmpty
      ? _currentHttpSources
      : (widget.httpSources ?? widget.sources ?? const {});

  List<Map<String, dynamic>> get _torrentStreams => _currentTorrentStreams;

  bool get _hasAnyQualityOptions =>
      _httpSources.isNotEmpty || _torrentStreams.isNotEmpty;

  // Scrubbing state for smooth seeking
  bool _isScrubbing = false;
  double? _scrubValue;
  bool _isHoveringSlider = false;
  double? _hoverValue;

  // --- NEW: current resize mode (default = fit) ---
  _ResizeMode _resizeMode = _ResizeMode.fit;

  // --- NEW: map resize mode -> BoxFit for Video widget ---
  BoxFit get _videoBoxFit {
    switch (_resizeMode) {
      case _ResizeMode.fit:
        // "Default": keep aspect, full video visible
        return BoxFit.contain;
      case _ResizeMode.zoom:
        // Zoom / crop but keep aspect (like "fill to screen")
        return BoxFit.cover;
      case _ResizeMode.stretch:
        // Full fill, aspect may be distorted
        return BoxFit.fill;
    }
  }

  String get _resizeLabel {
    switch (_resizeMode) {
      case _ResizeMode.fit:
        return 'Default';
      case _ResizeMode.zoom:
        return 'Zoom';
      case _ResizeMode.stretch:
        return 'Stretch';
    }
  }

  // Episode picker overlay
  bool _showEpisodeOverlay = false;
  int? _episodeOverlaySeason;
  bool _episodeOverlayLoading = false;
  String? _episodeOverlayError;
  final Map<int, List<TvEpisodeSummary>> _episodeCache =
      {}; // season -> episodes

  bool get _hasEpisodeOverlay =>
      widget.isTvShow &&
      widget.tmdbId != null &&
      widget.tmdbApiBase != null &&
      widget.tmdbApiKey != null &&
      (widget.seasonsMeta?.isNotEmpty ?? false);

  // Last successfully played source
  String? _lastGoodUrl;
  String _lastGoodQuality = 'auto';
  String? _lastGoodProviderLabel;
  bool _lastGoodIsTorrent = false;
  String? _lastGoodSourceId;

  late final FocusNode _keyboardFocusNode;

  bool get _isDesktop {
    if (kIsWeb) return false;
    try {
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  // External subtitles (ADD-ON only)
  final Map<String, SubtitleTrack> _externalSubtitleTracks = {};
  final List<SubtitleTrack> _discoveredSubs =
      []; // <-- NEW: cache discovered but not yet added tracks
  SubtitleTrack?
  _stickySubtitle; // <-- NEW: preserve selection across quality switches

  bool isfullscreen = false;

  void _cycleResizeMode() {
    setState(() {
      switch (_resizeMode) {
        case _ResizeMode.fit:
          _resizeMode = _ResizeMode.zoom;
          break;
        case _ResizeMode.zoom:
          _resizeMode = _ResizeMode.stretch;
          break;
        case _ResizeMode.stretch:
          _resizeMode = _ResizeMode.fit;
          break;
      }
      _showResizeSnack();
    });
  }

  void _showResizeSnack() {
    IconData icon;
    String title;
    String subtitle;

    switch (_resizeMode) {
      case _ResizeMode.fit:
        icon = Icons.crop_original_rounded;
        title = 'View: Default';
        break;
      case _ResizeMode.zoom:
        icon = Icons.crop_free_rounded;
        title = 'View: Zoom';
        break;
      case _ResizeMode.stretch:
        icon = Icons.aspect_ratio_rounded;
        title = 'View: Stretch';
        break;
    }

    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          // keep it bottom, but let width be controlled by constraints below
          margin: const EdgeInsets.only(left: 0, right: 0, bottom: 32),
          duration: const Duration(milliseconds: 1400),
          content: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.90, end: 1.0),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              final t = ((value - 0.90) / 0.10).clamp(0.0, 1.0);
              return Transform.scale(
                scale: value,
                child: Opacity(opacity: t, child: child),
              );
            },
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                // <<< WIDTH CONTROL HERE
                constraints: const BoxConstraints(
                  maxWidth: 300, // change this to make it wider/narrower
                  minWidth: 260,
                ),
                child: Container(
                  // <<< HEIGHT CONTROL HERE (vertical padding)
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF15151B), Color(0xFF09090E)],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1.1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // 3D-ish icon puck
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFFB45A), Color(0xFFFF8C1A)],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            icon,
                            size: 20,
                            color: Colors.black.withValues(alpha: 0.92),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Small pill tag to add that "UI polish"
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    color: Colors.white.withValues(alpha: 0.06),
                                  ),
                                  child: Text(
                                    'Video',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
  }

  // --- NEW: thumbnail preview state ---
  Uint8List? _previewThumbnail;
  double _previewSecond = 0; // current second for which thumbnail is shown
  Timer? _previewDebounceTimer;
  double? _lastRequestedSecond;
  late final AnimationController _playPauseController;
  @override
  void initState() {
    super.initState();
    _currentEpisodeTitle = widget.episodeTitle;
    _currentSeason = widget.initialSeason;
    _currentEpisode = widget.initialEpisode;
    _currentSubtitleUrls = widget.subtitleUrls;

    _currentHttpSources = Map.from(widget.httpSources ?? widget.sources ?? {});
    _currentHttpMetadata = Map.from(widget.httpMetadata ?? {});

    if (widget.movieboxSubjectId != null) {
      _fetchDetailsFromApi(widget.movieboxSubjectId!);
    }

    if (widget.isTvShow &&
        _currentSeason != null &&
        _currentEpisode != null &&
        (_currentEpisodeTitle == null ||
            _currentEpisodeTitle!.trim().isEmpty)) {
      _loadEpisodeTitleFromTMDB();
    }
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);

    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // IMPORTANT: increase bufferSize for smoother streaming (esp. torrent HTTP proxy)
    _player = Player(
      configuration: const PlayerConfiguration(
        // 128 MB cache. You can push this to 256 MB if device RAM is fine.
        bufferSize: 128 * 1024 * 1024,
      ),
    );
    try {
      (_player.platform as dynamic)?.setProperty('volume-max', '350');
    } catch (_) {}
    _videoController = VideoController(_player);
    _previewPlayer = Player(
      configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024),
    );
    _previewController = VideoController(_previewPlayer!);

    _listenToPlayer();
    _initializePlayer();
    WakelockPlus.enable();
    _initNativeControls();
    // Pre-select the current season for overlay
    if (widget.isTvShow) {
      _episodeOverlaySeason =
          _currentSeason ??
          (widget.seasonsMeta?.isNotEmpty == true
              ? widget.seasonsMeta!.first.seasonNumber
              : null);
    }

    _keyboardFocusNode = FocusNode();
    // auto-focus so space works immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });

    _startHistoryTimer();

    // Register TV series watch IMMEDIATELY when the player opens —
    // don't wait for the 10-second timer + 5-second position guard.
    if (widget.isTvShow && widget.title.isNotEmpty) {
      NotificationService.registerSeriesWatch(widget.title);
    }
  }

  void _startHistoryTimer() {
    _historyTimer?.cancel();
    _historyTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _saveCurrentProgress();
    });
  }

  Future<void> _saveCurrentProgress() async {
    if (!_hasOpenedSource || _isSwitching || widget.isLiveTv) return;

    // Don't save if we're at the very beginning or end
    if (_position.inSeconds < 5) return;
    if (_duration.inSeconds > 0 &&
        (_duration.inSeconds - _position.inSeconds) < 5)
      return;

    await WatchHistoryService.saveProgress(
      id: widget.tmdbId,
      title: widget.title,
      posterPath: widget.posterPath,
      mediaType: widget.isTvShow ? 'tv' : 'movie',
      season: _currentSeason,
      episode: _currentEpisode,
      episodeTitle: _currentEpisodeTitle ?? widget.episodeTitle,
      position: _position.inMilliseconds,
      duration: _duration.inMilliseconds,
      primeboxUrl: widget.primeboxUrl,
      primeboxSubjectType: widget.primeboxSubjectType,
      primeboxType: widget.primeboxType,
      movieboxSubjectId: widget.movieboxSubjectId,
      isOffline: widget.isOffline,
    );

    if (widget.isTvShow) {
      await NotificationService.registerSeriesWatch(widget.title);
    }
  }

  Future<void> _enterWindowFullscreen() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!_isDesktop) return;
    isfullscreen = true;
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setFullScreen(true);
  }

  Future<void> _exitWindowFullscreen() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!_isDesktop) return;
    isfullscreen = false;
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setFullScreen(false);
    await windowManager.setAlwaysOnTop(false);
  }
  //************* episode overlay*********************** */

  void _toggleEpisodeOverlay() {
    if (!_hasEpisodeOverlay || _isSwitching) return;

    setState(() {
      _showEpisodeOverlay = !_showEpisodeOverlay;
    });

    if (_showEpisodeOverlay &&
        _episodeOverlaySeason != null &&
        !_episodeCache.containsKey(_episodeOverlaySeason)) {
      _loadSeasonEpisodes(_episodeOverlaySeason!);
    }
  }

  Future<void> _loadSeasonEpisodes(int seasonNumber) async {
    if (!_hasEpisodeOverlay) return;

    // 1. Find the season metadata to get the Primebox episode count
    final seasons = widget.seasonsMeta ?? const <TvSeasonMeta>[];
    final seasonMeta = seasons.firstWhere(
      (s) => s.seasonNumber == seasonNumber,
      orElse: () => TvSeasonMeta(seasonNumber: seasonNumber),
    );

    final int primeboxCount = seasonMeta.episodeCount ?? 0;

    setState(() {
      _episodeOverlayLoading = true;
      _episodeOverlayError = null;
    });

    try {
      List<TvEpisodeSummary>? tmdbEpisodes;

      // 2. Try fetching TMDB metadata if IDs are available
      if (widget.tmdbId != null && widget.tmdbApiKey != null) {
        try {
          final uri = Uri.https(
            'api.themoviedb.org',
            '/3/tv/${widget.tmdbId}/season/$seasonNumber',
            {'api_key': widget.tmdbApiKey!, 'language': 'en-US'},
          );
          final res = await http.get(uri).timeout(const Duration(seconds: 12));
          if (res.statusCode == 200) {
            final decoded = json.decode(res.body);
            final list = (decoded['episodes'] as List?) ?? [];
            tmdbEpisodes = list.map((e) {
              final m = e as Map<String, dynamic>;
              return TvEpisodeSummary(
                season: seasonNumber,
                episode: (m['episode_number'] ?? 0) as int,
                title: (m['name'] ?? '') as String,
                runtime: m['runtime'] as int?,
                overview: m['overview'] as String?,
                stillPath: m['still_path'] as String?,
              );
            }).toList();
          }
        } catch (e) {
          debugPrint('[PlayerOverlay] TMDB Enrichment Failed: $e');
        }
      }

      // 3. Generate the final list based on Primebox count
      // If we have 0 count from Primebox but TMDB has episodes, we fallback to TMDB count
      final count = primeboxCount > 0
          ? primeboxCount
          : (tmdbEpisodes?.length ?? 0);

      final eps = List.generate(count, (index) {
        final epNum = index + 1;
        TvEpisodeSummary? tmdbEp;
        if (tmdbEpisodes != null) {
          try {
            tmdbEp = tmdbEpisodes.firstWhere((e) => e.episode.toInt() == epNum);
          } catch (_) {}
        }

        return TvEpisodeSummary(
          season: seasonNumber,
          episode: epNum,
          title: tmdbEp?.title.isNotEmpty == true
              ? tmdbEp!.title
              : 'Episode $epNum',
          runtime: tmdbEp?.runtime,
          overview: tmdbEp?.overview,
          stillPath: tmdbEp?.stillPath,
        );
      });

      if (!mounted) return;

      setState(() {
        _episodeCache[seasonNumber] = eps;
        _episodeOverlayLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _episodeOverlayLoading = false;
        _episodeOverlayError = 'Failed to sync with episode list.';
      });
    }
  }

  Widget _buildEpisodeOverlay() {
    final seasons = widget.seasonsMeta ?? const <TvSeasonMeta>[];
    if (seasons.isEmpty || !_hasEpisodeOverlay) return const SizedBox.shrink();

    final selectedSeason = _episodeOverlaySeason ?? seasons.first.seasonNumber;
    final episodes =
        _episodeCache[selectedSeason] ?? const <TvEpisodeSummary>[];

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF050509).withValues(alpha: 0.94),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 40,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB561).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.playlist_play_rounded,
                        size: 24,
                        color: Color(0xFFFFB561),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UP NEXT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFFB561),
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(
                            _videoTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.7,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 24,
                          color: Colors.white70,
                        ),
                      ),
                      onPressed: () async {
                        setState(() => _showEpisodeOverlay = false);
                        await _player.play();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: seasons.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final s = seasons[index];
                    final isSelected = s.seasonNumber == selectedSeason;
                    final epCount = s.episodeCount != null
                        ? ' (${s.episodeCount})'
                        : '';
                    return InkWell(
                      onTap: () {
                        if (isSelected) return;
                        setState(() => _episodeOverlaySeason = s.seasonNumber);
                        if (!_episodeCache.containsKey(s.seasonNumber))
                          _loadSeasonEpisodes(s.seasonNumber);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFFFE3B5),
                                    Color(0xFFFFB561),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isSelected
                              ? null
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? Colors.transparent
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          'Season ${s.seasonNumber}$epCount',
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (_episodeOverlayLoading && episodes.isEmpty)
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFFB561),
                        ),
                      );
                    if (_episodeOverlayError != null && episodes.isEmpty)
                      return Center(
                        child: Text(
                          _episodeOverlayError!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    if (episodes.isEmpty)
                      return const Center(
                        child: Text(
                          'No episodes found.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      itemCount: episodes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final e = episodes[index];
                        final isCurrent =
                            (_currentSeason == e.season &&
                            _currentEpisode == e.episode);
                        return InkWell(
                          onTap: () {
                            if (_isSwitching) return;
                            _playNextEpisode(
                              specificSeason: e.season,
                              specificEpisode: e.episode,
                              specificTitle: e.title,
                            );
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isCurrent
                                    ? const Color(
                                        0xFFFFB561,
                                      ).withValues(alpha: 0.4)
                                    : Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Row(
                              children: [
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: SizedBox(
                                        width: 120,
                                        height: 70,
                                        child: e.stillPath != null
                                            ? CachedNetworkImage(
                                                imageUrl:
                                                    'https://image.tmdb.org/t/p/w300${e.stillPath}',
                                                fit: BoxFit.cover,
                                              )
                                            : Container(color: Colors.white10),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black38,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white24,
                                            ),
                                          ),
                                          child: Icon(
                                            isCurrent
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            color: isCurrent
                                                ? const Color(0xFFFFB561)
                                                : Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'EPISODE ${e.episode}',
                                        style: const TextStyle(
                                          color: Color(0xFFFFB561),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        e.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: isCurrent
                                              ? Colors.white
                                              : Colors.white.withValues(
                                                  alpha: 0.9,
                                                ),
                                        ),
                                      ),
                                      if (e.runtime != null && e.runtime! > 0)
                                        Text(
                                          '${e.runtime}m',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.white.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _hideOverlaysInstant() {
    if (!mounted) return;
    setState(() {
      _showTracksPanel = false;
      _showQualityPanel = false;
    });
  }

  void _listenToPlayer() {
    _playingSub = _player.stream.playing.listen((playing) {
      if (!mounted) return;

      setState(() {
        _isPlaying = playing;
      });

      if (playing) {
        _playPauseController.forward();
      } else {
        _playPauseController.reverse();
      }

      if (_showControls && !_showTracksPanel && !_showQualityPanel) {
        _restartHideControlsTimer();
      }
    });

    _bufferingSub = _player.stream.buffering.listen((b) {
      if (!mounted) return;
      setState(() {
        _isBuffering = b || _isSwitching;
      });
    });

    _positionSub = _player.stream.position.listen((pos) {
      if (!mounted) return;
      // Don't fight the user's drag or reset during quality switching.
      if (_isScrubbing || _isSwitching) return;
      setState(() {
        _position = pos;
      });
    });

    _durationSub = _player.stream.duration.listen((dur) {
      if (!mounted) return;
      setState(() {
        _duration = dur;
      });

      _bufferSub = _player.stream.buffer.listen((buf) {
        if (!mounted) return;
        setState(() {
          _buffered = buf;
        });
      });
    });

    _tracksSub = _player.stream.tracks.listen((tracks) {
      _updateTracksFromState();
    });

    _volumeSub = _player.stream.volume.listen((vol) {
      if (mounted && _isDesktop) {
        setState(() => _volume = (vol / 100.0).clamp(0.0, 1.0));
      }
    });

    _completedSub = _player.stream.completed.listen((completed) {
      if (!mounted) return;
      if (completed) {
        _onPlaybackCompleted();
      }
    });

    _errorSub = _player.stream.error.listen((err) async {
      debugPrint('PLAYER ERROR: $err');
      if (!mounted) return;

      if (_isTransientLookMovieReadError(err)) {
        debugPrint('Ignoring transient LookMovie HLS read warning.');
        return;
      }

      setState(() {
        _isBuffering = false;
        _isSwitching = false;
      });

      // If current source is torrent, go back to default HTTP
      if (_selectedIsTorrent) {
        await _fallbackToDefaultSource(resumePosition: _position);
      }
    });
  }

  Future<void> _playNextEpisode({
    bool autoPlay = false,
    int? specificSeason,
    int? specificEpisode,
    String? specificTitle,
  }) async {
    final currentSeason = _currentSeason;
    final currentEpisode = _currentEpisode;

    if (currentSeason != null &&
        currentEpisode != null &&
        widget.onEpisodeSelected != null) {
      setState(() {
        _isSwitching = true;
        _showEpisodeOverlay = false;
      });

      int targetSeason = specificSeason ?? currentSeason;
      int targetEpisode = specificEpisode ?? (currentEpisode + 1);
      String targetTitle = specificTitle ?? '';

      // Only auto-detect if no specific episode was requested
      if (specificSeason == null && specificEpisode == null) {
        final nextTitle = await _fetchEpisodeTitleFromTMDB(
          targetSeason,
          targetEpisode,
        );
        if (nextTitle == null || nextTitle.trim().isEmpty) {
          targetSeason = currentSeason + 1;
          targetEpisode = 1;
          final nextSeasonTitle = await _fetchEpisodeTitleFromTMDB(
            targetSeason,
            1,
          );
          if (nextSeasonTitle != null && nextSeasonTitle.trim().isNotEmpty) {
            targetTitle = nextSeasonTitle;
          } else {
            if (autoPlay && mounted) {
              Navigator.of(context).maybePop();
            } else if (mounted) {
              AppToast.show(context, 'No next episode available');
            }
            if (mounted) setState(() => _isSwitching = false);
            return;
          }
        } else {
          targetTitle = nextTitle;
        }
      }

      final newSources = await widget.onEpisodeSelected!(
        targetSeason,
        targetEpisode,
        targetTitle,
      );

      if (newSources != null && newSources['httpSources'] != null && mounted) {
        await _player.stop();
        _stopCurrentTorrent(erase: true);

        setState(() {
          _currentSeason = targetSeason;
          _currentEpisode = targetEpisode;
          _currentEpisodeTitle = targetTitle;

          final httpS = newSources['httpSources'];
          _currentHttpSources = httpS is Map<String, Map<String, String>>
              ? httpS
              : Map<String, Map<String, String>>.from(httpS as Map);

          _currentSubtitleUrls =
              newSources['subtitleUrls'] as Map<String, List<String>>?;

          final ts = newSources['torrentStreams'];
          _currentTorrentStreams = ts != null
              ? List<Map<String, dynamic>>.from(ts as List)
              : [];

          final ed = newSources['externalDubs'];
          _currentExternalDubs = ed != null
              ? List<Map<String, dynamic>>.from(ed as List)
              : null;

          _currentHttpMetadata =
              newSources['httpMetadata'] as Map<String, dynamic>? ?? {};
          _hasOpenedSource = false;
          _currentInitialPosition = Duration.zero;

          // Clear previous episode's subtitle state
          _selectedSubtitleTrack = null;
          _pendingSubtitleTrack = null;
          _subtitleTracks.clear();
          _subtitleTrackObjs.clear();
        });

        _initializePlayer();
      } else {
        if (mounted) AppToast.show(context, 'Failed to load next episode');
      }

      if (mounted) setState(() => _isSwitching = false);
    } else {
      if (autoPlay && mounted) {
        Navigator.of(context).maybePop();
      } else if (mounted) {
        AppToast.show(context, 'No next episode available');
      }
    }
  }

  Future<void> _onPlaybackCompleted() async {
    // 1. Remove from watch history since it's fully watched
    final mediaType = widget.isTvShow ? 'tv' : 'movie';
    final idOrTitleOrUrl = (widget.tmdbId != null && widget.tmdbId != 0)
        ? widget.tmdbId.toString()
        : (widget.primeboxUrl ?? widget.title);

    await WatchHistoryService.removeFromHistory(mediaType, idOrTitleOrUrl);

    if (!mounted) return;

    // 2. Decide next action: auto-play next episode (series) or go back (movie)
    if (widget.isTvShow && widget.onEpisodeSelected != null) {
      await _playNextEpisode(autoPlay: true);
      return;
    }

    // Default: Automatically go back to the details page
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<String?> _fetchEpisodeTitleFromTMDB(int season, int episode) async {
    try {
      final effectiveApiKey = widget.tmdbApiKey ?? EnvConfig.tmdbApiKey;
      final url = Uri.parse(
        'https://api.themoviedb.org/3/tv/${widget.tmdbId}/season/$season/episode/$episode?api_key=$effectiveApiKey',
      );

      final resp = await http.get(url);

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['name'];
      }
    } catch (_) {}

    return null;
  }

  Future<void> _fallbackToDefaultSource({Duration? resumePosition}) async {
    debugPrint('FALLBACK: opening default source');

    // Stop any torrent backend just in case
    _stopCurrentTorrent(erase: true);

    final httpSources = _httpSources;
    final mediaUrl = widget.mediaUrl;

    // Same priority as your _initializePlayer
    const qPriority = ['1080p', '720p', '480p', '360p', '2160p', '1440p'];
    const providerPriority = ['Pixeldrain', 'FSL', '10Gbps'];

    // 1) Prefer HTTP (4KHDHub)
    if (httpSources.isNotEmpty) {
      String? chosenQuality;
      for (final q in qPriority) {
        if (httpSources.containsKey(q)) {
          chosenQuality = q;
          break;
        }
      }
      chosenQuality ??= httpSources.keys.first;

      final provs = httpSources[chosenQuality]!;
      final sortedProvs = provs.keys.toList()
        ..sort((a, b) {
          final rankA = _getLanguageRank(a);
          final rankB = _getLanguageRank(b);
          if (rankA != rankB) return rankA.compareTo(rankB);
          for (final p in providerPriority) {
            if (a == p && b != p) return -1;
            if (b == p && a != p) return 1;
          }
          return a.compareTo(b);
        });
      final chosenProvider = sortedProvs.first;

      final url = provs[chosenProvider]!;

      await _switchToUrl(
        url: url,
        quality: chosenQuality,
        providerLabel: chosenProvider,
        isTorrent: false,
        sourceId: _httpSourceId(chosenQuality, chosenProvider),
        resumePosition: resumePosition,
      );
      return;
    }

    // 2) Fallback to direct mediaUrl if no HTTP map
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      await _switchToUrl(
        url: mediaUrl,
        quality: '1080p',
        providerLabel: 'Direct',
        isTorrent: false,
        sourceId: 'direct',
        resumePosition: resumePosition,
      );
      return;
    }

    // 3) Nothing to fallback to
    debugPrint('FALLBACK: no default HTTP/mediaUrl source available.');
    if (mounted) {
      setState(() {
        _isBuffering = false;
        _isSwitching = false;
      });
      AppToast.show(
        context,
        'No sources available.fallback to default....',
        icon: Icons.error_rounded,
        tag: 'no source',
      );
    }
  }

  Future<void> _initializePlayer() async {
    if (widget.isOffline && widget.videoUrl != null) {
      if (Platform.isWindows) {
        _launchExternalPlayerWindows(widget.videoUrl!, {});
        return;
      }

      if (mounted) setState(() => _isBuffering = true);
      try {
        await _player.open(
          Media(widget.videoUrl!, start: _currentInitialPosition),
        );
        await _player.setVolume((_volume * 250.0).clamp(0.0, 350.0));
        _hasOpenedSource = true;
      } catch (e) {
        debugPrint('Offline playback error: $e');
      } finally {
        if (mounted) setState(() => _isBuffering = false);
      }
      return;
    }
    final httpSources = _httpSources;
    final torrents = _torrentStreams;

    // ------------ PRIORITY ORDER ------------
    // Quality priority (4k > 1080P > 720P > 480P > etc.)
    const qPriority = ['4K', '2160p', '1440p', '1080p', '720p', '480p', '360p'];

    // Provider priority (Pixeldrain must be default)
    const providerPriority = ['Pixeldrain', 'FSL', '10Gbps'];
    // ----------------------------------------

    // ========== 1) HTTP (4KHDHub) has highest priority ==========
    if (httpSources.isNotEmpty) {
      // Pick best quality
      String? chosenQuality;
      for (final q in qPriority) {
        if (httpSources.containsKey(q)) {
          chosenQuality = q;
          break;
        }
      }
      if (chosenQuality == null) {
        for (final q in qPriority) {
          final match = httpSources.keys.firstWhere(
            (k) => _getBaseQuality(k).toLowerCase() == q.toLowerCase(),
            orElse: () => '',
          );
          if (match.isNotEmpty) {
            chosenQuality = match;
            break;
          }
        }
      }
      chosenQuality ??= httpSources.keys.first;

      // Pick best provider inside that quality by language priority
      final provs = httpSources[chosenQuality]!;
      final sortedProvs = provs.keys.toList()
        ..sort((a, b) {
          final rankA = _getLanguageRank(a);
          final rankB = _getLanguageRank(b);
          if (rankA != rankB) return rankA.compareTo(rankB);
          for (final p in providerPriority) {
            if (a == p && b != p) return -1;
            if (b == p && a != p) return 1;
          }
          return a.compareTo(b);
        });
      final chosenProvider = sortedProvs.first;

      final url = provs[chosenProvider]!;

      _selectedQuality = chosenQuality;
      _selectedProviderLabel = chosenProvider;
      _selectedIsTorrent = false;
      _selectedSourceId = _httpSourceId(chosenQuality, chosenProvider);

      _switchToUrl(
        url: url,
        quality: chosenQuality,
        providerLabel: chosenProvider,
        isTorrent: false,
        sourceId: _selectedSourceId!,
        isInitial: true,
        resumePosition: _currentInitialPosition,
      );
    }
    // ========== 2) No HTTP → use torrent, with 4K > 1080p > 720p priority ==========
    else if (torrents.isNotEmpty) {
      // Find best torrent quality using same priority order
      String? chosenQuality;
      final availableQ = <String>{};
      for (final t in torrents) {
        final q = (t['quality'] as String?) ?? 'auto';
        availableQ.add(q);
        availableQ.add(_getBaseQuality(q));
      }
      for (final q in qPriority) {
        if (availableQ.contains(q)) {
          chosenQuality = q;
          break;
        }
      }
      // if nothing matches qPriority, just use whatever first torrent has
      if (chosenQuality == null && torrents.isNotEmpty) {
        chosenQuality = (torrents.first['quality'] as String?) ?? 'auto';
      }

      // Pick first torrent with that chosenQuality
      Map<String, dynamic> chosenEntry = torrents.first;
      if (chosenQuality != null) {
        final match = torrents.firstWhere((e) {
          final q = (e['quality'] as String?) ?? 'auto';
          return q == chosenQuality || _getBaseQuality(q) == chosenQuality;
        }, orElse: () => torrents.first);
        chosenEntry = match;
      }

      _selectedQuality =
          (chosenEntry['quality'] as String?) ?? chosenQuality ?? 'auto';
      _selectedProviderLabel = 'Torrent';
      _selectedIsTorrent = true;
      final id = _torrentSourceId(chosenEntry);
      _selectedSourceId = id;

      // After first frame, actually start torrent stream
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _selectTorrentSource(chosenEntry, id);
      });
    }
    // ========== 3) No HTTP, no torrent → fallback to direct mediaUrl ==========
    else {
      _selectedQuality = 'auto';
      _selectedProviderLabel = null;
      _selectedIsTorrent = false;
      _selectedSourceId = null;
      final url = widget.mediaUrl;
      if (url != null && url.isNotEmpty) {
        _switchToUrl(
          url: url,
          quality: 'auto',
          providerLabel: 'Direct',
          isTorrent: false,
          sourceId: 'direct',
          isInitial: true,
          resumePosition: _currentInitialPosition,
        );
      }
    }

    // Load backend subtitles (from LookMovie2) after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBackendSubtitles();
    });
  }

  // ======== Torrent helpers =========

  String _torrentSourceId(Map<String, dynamic> e) =>
      'torrent|${identityHashCode(e)}';

  String _httpSourceId(String q, String provider) => 'http|$q|$provider';

  Future<void> _stopCurrentTorrent({bool erase = true}) async {
    final sid = _currentTorrentStreamId;
    if (sid == null) return;
    try {
      final res = await http.post(
        Uri.parse('${EnvConfig.luminoBackendUrl}/stop/$sid'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'erase': erase}),
      );
      if (res.statusCode != 200) {
        debugPrint('Stop failed ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('Stop error: $e');
    } finally {
      _currentTorrentStreamId = null;
    }
  }

  Future<void> _selectTorrentSource(
    Map<String, dynamic> entry,
    String sourceId,
  ) async {
    if (_isSwitching) return;

    // 🔴 Use actual player state position to be absolutely sure
    final resumePos = _player.state.position;

    // Optimistic UI: mark this source as selected
    if (mounted) {
      setState(() {
        _isSwitching = true; // 🔴 Set this immediately
        _selectedSourceId = sourceId;
        _selectedQuality = (entry['quality'] as String?) ?? 'auto';
        _selectedProviderLabel = 'Torrent';
        _selectedIsTorrent = true;
        _isBuffering = true; // show spinner while preparing
      });
    }

    // Stop old torrent backend without blocking UI
    _stopCurrentTorrent(erase: true);

    final magnet = entry['magnet'];
    final int fileIndex = (entry['fileIdx'] as int?) ?? 0;

    if (magnet == null) {
      if (mounted) {
        setState(() => _isBuffering = false);
      }
      return;
    }

    try {
      final startUri = Uri.parse(
        '${EnvConfig.luminoBackendUrl}/start',
      );
      debugPrint('TORRENT /start → $startUri');

      final resp = await http.post(
        startUri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'magnet': magnet, 'fileIndex': fileIndex}),
      );
      if (resp.statusCode != 200) {
        throw Exception('Start ${resp.statusCode}: ${resp.body}');
      }

      final j = json.decode(resp.body) as Map<String, dynamic>;
      final sid = j['streamId']?.toString();
      final streamUrl =
          (j['url'] as String?) ??
          (j['streamUrl'] as String?) ??
          (j['stream'] as String?);

      debugPrint('TORRENT streamId=$sid url=$streamUrl');

      if (sid == null || streamUrl == null) {
        throw Exception('Invalid /start response: missing streamId or url');
      }

      _currentTorrentStreamId = sid;

      // 🔴 NEW: wait until the stream actually responds before opening with FFmpeg
      final ready = await _waitForStreamReady(streamUrl);
      if (!ready) {
        debugPrint('Torrent stream not ready, falling back to default source.');
        if (mounted) {
          AppToast.show(
            context,
            'stream not ready. Switching back to default source..',
            icon: Icons.error_rounded,
            tag: 'no source',
          );
        }

        // Use current position as resume point for default stream
        await _fallbackToDefaultSource(resumePosition: _position);
        return;
      }

      final quality = (entry['quality'] as String?) ?? 'auto';
      final label =
          entry['behaviorHints']?['filename']?.toString() ??
          entry['filename']?.toString() ??
          'Torrent';

      await _switchToUrl(
        url: streamUrl,
        quality: quality,
        providerLabel: label,
        isTorrent: true,
        sourceId: sourceId,
        resumePosition: resumePos,
      );
    } catch (e) {
      debugPrint('Torrent start failed: $e');
      if (mounted) {
        setState(() => _isBuffering = false);
        AppToast.show(
          context,
          'Stream start failed',
          icon: Icons.error_rounded,
          tag: 'Fail',
        );
      }
    }
  }

  Future<void> _selectHttpSource(
    String quality,
    String provider,
    String url,
    String sourceId,
  ) async {
    if (_isSwitching) return;

    // 1. Capture current state BEFORE any modifications
    final resumePos = _player.state.position;
    final wasTorrent = _selectedIsTorrent;

    // 2. Now update UI state
    if (mounted) {
      setState(() {
        _isSwitching = true;
        _selectedSourceId = sourceId;
        _selectedQuality = quality;
        _selectedProviderLabel = provider;
        _selectedIsTorrent = false;
      });
    }

    // stop old torrent in background
    if (wasTorrent) {
      _stopCurrentTorrent(erase: true);
    }

    // Await this so we don't return before the switch logic starts
    await _switchToUrl(
      url: url,
      quality: quality,
      providerLabel: provider,
      isTorrent: false,
      sourceId: sourceId,
      resumePosition: resumePos,
    );
  }

  Map<String, String> _headersForHttpSource({
    required String url,
    required String providerLabel,
  }) {
    const chromeUserAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Safari/537.36';

    final lowerUrl = url.toLowerCase();
    final lowerProvider = providerLabel.toLowerCase();
    final isLookMovie =
        lowerProvider.contains('lookmovie') ||
        lowerUrl.contains('lookmovie2.to') ||
        lowerUrl.contains('bermis.store') ||
        lowerUrl.contains('/storage8/shows/') ||
        lowerUrl.contains('/storage8/movies/');

    if (isLookMovie) {
      return const {
        'User-Agent': chromeUserAgent,
        'Referer': 'https://www.lookmovie2.to/',
        'Origin': 'https://www.lookmovie2.to',
        'Accept': '*/*',
        'Connection': 'keep-alive',
      };
    }

    final isNetfilmOrFmovies =
        lowerUrl.contains('netfilm.world') ||
        lowerUrl.contains('fmoviesunblocked.net') ||
        lowerUrl.contains('hakunaymatata.com');
    if (isNetfilmOrFmovies) {
      String referer = 'https://netfilm.world/';
      if (lowerUrl.contains('fmoviesunblocked.net')) {
        referer = 'https://fmoviesunblocked.net/';
      }
      return {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36',
        'Referer': referer,
        'Accept': '*/*',
        'Connection': 'keep-alive',
      };
    }

    // MovieBox / aoneroom DASH/HLS streams — headers come from httpMetadata
    // so we return minimal headers here; the caller merges meta['headers'] on top.
    final isMovieBox =
        lowerUrl.contains('aoneroom.com') ||
        lowerUrl.contains('cloudfront.net') ||
        lowerUrl.contains('akamaized.net') ||
        lowerUrl.endsWith('.mpd') ||
        lowerUrl.contains('.mpd?');
    if (isMovieBox) {
      return const {'User-Agent': chromeUserAgent};
    }

    return const {'User-Agent': chromeUserAgent};
  }

  bool _isTransientLookMovieReadError(dynamic err) {
    final message = err.toString().toLowerCase();
    final provider = (_selectedProviderLabel ?? '').toLowerCase();
    final isLookMovie = provider.contains('lookmovie');
    return isLookMovie &&
        message.contains('ffurl_read returned') &&
        message.contains('0xffffff76');
  }

  void _launchExternalPlayerWindows(String url, Map<String, String> headers) {
    try {
      final payload = {
        'metadata': _currentHttpMetadata,
        'sources': _httpSources,
        'subtitles': _currentSubtitleUrls,
        'title': _videoTitle,
        // Fallback legacy support in case metadata is empty
        'url': url,
        'headers': headers,
        'is_series': widget.isTvShow,
        'episodes':
            widget.isTvShow &&
                _currentSeason != null &&
                _episodeCache.containsKey(_currentSeason)
            ? _episodeCache[_currentSeason]!
                  .map(
                    (e) => {
                      'season': e.season,
                      'episode': e.episode,
                      'title': e.title,
                      'overview': e.overview,
                      'stillPath': e.stillPath,
                      'runtime': e.runtime,
                    },
                  )
                  .toList()
            : [],
        'continue_watch': {
          'id': widget.tmdbId,
          'title': widget.title,
          'posterPath': widget.posterPath,
          'mediaType': widget.isTvShow ? 'tv' : 'movie',
          'season': _currentSeason,
          'episode': _currentEpisode,
          'episodeTitle': _currentEpisodeTitle ?? widget.episodeTitle,
          'primeboxUrl': widget.primeboxUrl,
          'primeboxSubjectType': widget.primeboxSubjectType,
          'primeboxType': widget.primeboxType,
          'movieboxSubjectId': widget.movieboxSubjectId,
          'isOffline': widget.isOffline,
          'initial_position': widget.initialPosition?.inMilliseconds ?? 0,
        },
      };
      final jsonPayload = jsonEncode(payload);
      final tempDir = Directory.systemTemp;
      final file = File(
        '${tempDir.path}\\lumino_payload_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      file.writeAsStringSync(jsonPayload);

      // Ensure dart:convert is imported. Assuming dart:io is already imported.
      final appDir = p.dirname(Platform.resolvedExecutable);
      final exePath = p.join(
        appDir,
        'ExternalPlayer',
        'LuminoExternalPlayer.exe',
      );
      if (mounted) {
        setState(() {
          _isExternalPlayerRunning = true;
        });
      }
      Process.start(exePath, [file.path]).then((process) async {
        _externalProcess = process;
        await process.exitCode;
        if (mounted) {
          setState(() {
            _isExternalPlayerRunning = false;
            _externalProcess = null;
          });
        }
        final progressFile = File('${file.path}_progress.json');
        if (await progressFile.exists()) {
          try {
            final content = await progressFile.readAsString();
            final data = jsonDecode(content);
            final pos = data['position'] as int?;
            final dur = data['duration'] as int?;
            if (pos != null && dur != null && dur > 0) {
              final cw = payload['continue_watch'] as Map<String, dynamic>;
              await WatchHistoryService.saveProgress(
                id: cw['id'] as int?,
                title: cw['title'] as String,
                posterPath: cw['posterPath'] as String?,
                mediaType: cw['mediaType'] as String,
                season: (data['season'] as int?) ?? (cw['season'] as int?),
                episode: (data['episode'] as int?) ?? (cw['episode'] as int?),
                episodeTitle:
                    (data['episodeTitle'] as String?) ??
                    (cw['episodeTitle'] as String?),
                position: pos,
                duration: dur,
                primeboxUrl: cw['primeboxUrl'] as String?,
                primeboxSubjectType: cw['primeboxSubjectType'] as int?,
                primeboxType: cw['primeboxType'] as String?,
                movieboxSubjectId: cw['movieboxSubjectId'] as String?,
                isOffline: (cw['isOffline'] as bool?) ?? false,
              );
              if (cw['mediaType'] == 'tv') {
                await NotificationService.registerSeriesWatch(
                  cw['title'] as String,
                );
              }
            }

            final action = data['action'] as String?;
            final targetSeason = data['season'] as int?;
            final targetEpisode = data['episode'] as int?;

            if (action == 'next_episode') {
              if (mounted) _playNextEpisode(autoPlay: true);
            } else if (action == 'play_episode' &&
                targetSeason != null &&
                targetEpisode != null) {
              if (mounted)
                _playNextEpisode(
                  specificSeason: targetSeason,
                  specificEpisode: targetEpisode,
                );
            } else {
              if (mounted) Navigator.of(context).pop();
            }
          } catch (e) {
            debugPrint('Error reading progress: $e');
            if (mounted) Navigator.of(context).pop();
          }
          try {
            await progressFile.delete();
            await file.delete();
          } catch (_) {}
        } else {
          if (mounted) Navigator.of(context).pop();
        }
      });
    } catch (e) {
      debugPrint('External player error: $e');
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _switchToUrl({
    required String url,
    required String quality,
    required String providerLabel,
    required bool isTorrent,
    required String sourceId,
    bool isInitial = false,
    Duration? resumePosition,
  }) async {
    debugPrint(
      'Switching to [$quality] provider="$providerLabel" isTorrent=$isTorrent URL=$url',
    );

    _hideControlsTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _isSwitching = !isInitial;
      _isBuffering = true;
      _showControls = true;
      // We'll increment this AFTER the source is ready to avoid
      // flickering or resetting the view during seek
    });

    try {
      final baseHeaders = _headersForHttpSource(
        url: url,
        providerLabel: providerLabel,
      );

      final Map<String, String> headers = {...baseHeaders};
      final meta = _currentHttpMetadata[sourceId];
      if (meta != null && meta is Map && meta['headers'] != null) {
        headers.addAll(Map<String, String>.from(meta['headers']));
      }

      if (Platform.isWindows) {
        _launchExternalPlayerWindows(url, headers);
        return;
      }

      await _player.open(
        Media(url, httpHeaders: headers, start: resumePosition),
      );
      await _player.setVolume((_volume * 150.0).clamp(0.0, 150.0));
      _hasOpenedSource = true;

      // ✅ Only now (after open/seek start) we mark this as last good source
      _lastGoodUrl = url;
      _lastGoodQuality = quality;
      _lastGoodProviderLabel = providerLabel;
      _lastGoodIsTorrent = isTorrent;
      _selectedSourceId = sourceId;

      setState(() {
        _selectedQuality = quality;
        _selectedProviderLabel = providerLabel;
        _selectedIsTorrent = isTorrent;
        _selectedSourceId = sourceId;
        _tracksLoaded = false;
        _isSwitching = false; // Show video surface immediately
        _isBuffering = false;
        _playerKey++; // Rebuild surface now that we are ready

        _previewThumbnail = null;
        _previewSecond = 0;
        _lastRequestedSecond = null;
      });
    } catch (e) {
      debugPrint('Error during switch: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSwitching = false;
          _isBuffering = false;
        });
        _restartHideControlsTimer();
      }
    }
  }

  // ======== Tracks / controls =========

  // -------- Tracks logic ----------

  void _updateTracksFromState([Tracks? tracks]) {
    if (!mounted) return;

    final t = tracks ?? _player.state.tracks;

    // Raw lists from media_kit
    final rawAudios = t.audio;
    final rawSubs = t.subtitle;

    final audioSeenIds = <String>{};
    final subsSeenIds = <String>{};

    final audios = <AudioTrack>[];
    for (final t in rawAudios) {
      final id = t.id ?? '';
      if (id.isEmpty || audioSeenIds.contains(id)) continue;
      if (id == AudioTrack.auto().id || id == AudioTrack.no().id) continue;
      audioSeenIds.add(id);
      audios.add(t);
    }

    final subs = <SubtitleTrack>[];
    for (final t in rawSubs) {
      final id = t.id ?? '';
      if (id.isEmpty || subsSeenIds.contains(id)) continue;
      if (id == SubtitleTrack.auto().id || id == SubtitleTrack.no().id)
        continue;
      subsSeenIds.add(id);
      // USER REQUEST: Only show subtitles from /links (external).
      // We intentionally skip adding embedded `t` to `subs` so they don't clutter the UI.
    }

    final combinedSubs = [...subs];

    // Merge discovered/external subtitles
    for (final ds in _discoveredSubs) {
      if (!subsSeenIds.contains(ds.id)) {
        combinedSubs.add(ds);
        subsSeenIds.add(ds.id ?? '');
      }
    }

    final currentTrack = _player.state.track;
    final currentAudio = currentTrack.audio;
    final currentSub = currentTrack.subtitle;

    int? selectedAudioIndex;
    selectedAudioIndex = audios.indexWhere(
      (t) => (t.id ?? '') == (currentAudio.id ?? ''),
    );
    if (selectedAudioIndex == -1) selectedAudioIndex = null;

    int? selectedSubIndex;
    if (currentSub.id == SubtitleTrack.no().id) {
      selectedSubIndex = -1;
    } else {
      selectedSubIndex = combinedSubs.indexWhere(
        (t) => (t.id ?? '') == (currentSub.id ?? ''),
      );
      if (selectedSubIndex == -1) selectedSubIndex = null;
    }

    // Auto-select English if nothing selected
    if (selectedSubIndex == null || selectedSubIndex == -1) {
      final englishIndex = combinedSubs.indexWhere(
        (s) => (s.title?.toLowerCase().contains('english') ?? false),
      );
      if (englishIndex != -1) {
        selectedSubIndex = englishIndex;
        // Actually apply to player
        _player.setSubtitleTrack(combinedSubs[englishIndex]);
      }
    }
    selectedSubIndex ??= combinedSubs.isNotEmpty ? 0 : -1;

    final isPrimebox = _selectedProviderLabel == 'Primebox';
    final hasExternalDubs =
        isPrimebox &&
        widget.externalDubs != null &&
        widget.externalDubs!.isNotEmpty;

    // Check if we have multiple HTTP audio streams for the current quality
    List<String> matchingProvs = [];
    if (!_selectedIsTorrent) {
      final provs = _httpSources[_selectedQuality] ?? {};
      final currentBaseProvider = _getBaseProvider(
        _selectedProviderLabel ?? '',
      );
      matchingProvs = provs.keys
          .where((p) => _getBaseProvider(p) == currentBaseProvider)
          .toList();
    }

    final Map<int, String> audioMap = {};
    int? resolvedAudioIndex;

    if (matchingProvs.length > 1) {
      // 1. HTTP Multi-Audio Streams (Original Audio, Telugu Audio, Hindi Audio, etc.)
      // Exclude embedded container audio track to avoid duplicate / phantom "hin"/"und" tracks.
      for (int i = 0; i < matchingProvs.length; i++) {
        final p = matchingProvs[i];
        final lang = _getLanguageFromProvider(p);
        final streamAudioIndex = 2000 + i;
        audioMap[streamAudioIndex] = '$lang Audio';

        if (_selectedProviderLabel == p && _activeExternalDubSid == null) {
          resolvedAudioIndex = streamAudioIndex;
        }
      }
      resolvedAudioIndex ??= 2000;
    } else if (hasExternalDubs) {
      // 2. External dubs
      for (int i = 0; i < widget.externalDubs!.length; i++) {
        final dub = widget.externalDubs![i];
        final name = dub['lanName'] ?? 'Dub ${i + 1}';
        final lowerName = name.toLowerCase();
        final externalIndex = 1000 + i;
        audioMap[externalIndex] = name.toLowerCase().contains('audio')
            ? name
            : '$name Audio';

        final activeSid = _activeExternalDubSid;
        if (activeSid != null) {
          if (activeSid == dub['subjectId']) resolvedAudioIndex = externalIndex;
        } else if (lowerName.contains('original')) {
          resolvedAudioIndex = externalIndex;
        }
      }
      resolvedAudioIndex ??= 1000;
    } else {
      // 3. Embedded media_kit container tracks
      for (int i = 0; i < audios.length; i++) {
        audioMap[i] = _buildTrackLabel(
          audios[i].title,
          audios[i].language,
          fallback: 'Audio ${i + 1}',
        );
      }
      resolvedAudioIndex = audios.indexWhere(
        (t) => (t.id ?? '') == (currentAudio.id ?? ''),
      );
      if (resolvedAudioIndex == -1)
        resolvedAudioIndex = audios.isNotEmpty ? 0 : null;
    }

    setState(() {
      _audioTrackObjs = audios;
      _subtitleTrackObjs = combinedSubs;

      _audioTracks = audioMap;
      _selectedAudioTrack = resolvedAudioIndex;

      _subtitleTracks = {
        for (int i = 0; i < combinedSubs.length; i++)
          i:
              (combinedSubs[i].title != null &&
                  combinedSubs[i].title!.trim().isNotEmpty)
              ? combinedSubs[i].title!.trim()
              : _buildTrackLabel(
                  null,
                  combinedSubs[i].language,
                  fallback: 'Subtitle ${i + 1}',
                ),
      };

      _selectedSubtitleTrack = selectedSubIndex;
      _tracksLoaded = true;
    });
  }

  void _restartHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_showTracksPanel && !_showQualityPanel) {
        setState(() => _showControls = false);
      }
    });
  }

  Future<void> _togglePlayPause() async {
    if (!_hasOpenedSource || _isSwitching) return;

    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (e) {
      debugPrint('Error toggling play/pause: $e');
    }
  }

  Future<void> _seekBy(Duration delta) async {
    if (!_hasOpenedSource || _isSwitching) return;

    try {
      final pos = _position;
      final dur = _duration;
      var target = pos + delta;
      if (target < Duration.zero) target = Duration.zero;
      if (dur > Duration.zero && target > dur) target = dur;
      await _player.seek(target);
    } catch (e) {
      debugPrint('Error seeking: $e');
    }
  }

  // -------- Tracks overlay ----------
  Future<void> _openTracksPanel() async {
    _wasPlayingBeforeOverlay = _isPlaying;
    if (_hasOpenedSource && _isPlaying) {
      try {
        await _player.pause();
      } catch (e) {
        debugPrint('Error pausing for tracks panel: $e');
      }
    }
    _pendingAudioTrack = _selectedAudioTrack;
    _pendingSubtitleTrack = _selectedSubtitleTrack;
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _showTracksPanel = true;
        _showQualityPanel = false;
        _showControls = true;
      });
    }
  }

  String? _activeExternalDubSid;

  Future<void> _applyPendingTracksAndClose() async {
    try {
      // Audio
      if (_pendingAudioTrack != null &&
          _pendingAudioTrack != _selectedAudioTrack) {
        if (_pendingAudioTrack! >= 2000) {
          // SWITCH HTTP STREAM FOR AUDIO
          final idx = _pendingAudioTrack! - 2000;
          final provs = _httpSources[_selectedQuality] ?? {};
          final currentBaseProvider = _getBaseProvider(
            _selectedProviderLabel ?? '',
          );
          final matchingProvs = provs.keys
              .where((p) => _getBaseProvider(p) == currentBaseProvider)
              .toList();
          if (idx >= 0 && idx < matchingProvs.length) {
            final targetProvider = matchingProvs[idx];
            final targetUrl = provs[targetProvider]!;
            final targetId = _httpSourceId(_selectedQuality, targetProvider);

            _activeExternalDubSid = null; // Clear external dub state
            _selectHttpSource(
              _selectedQuality,
              targetProvider,
              targetUrl,
              targetId,
            );
          }
        } else if (_pendingAudioTrack! >= 1000) {
          // SWITCH EXTERNAL DUB
          final dubIdx = _pendingAudioTrack! - 1000;
          final dub = widget.externalDubs![dubIdx];
          _switchExternalDub(dub);
        } else if (_pendingAudioTrack! >= 0 &&
            _pendingAudioTrack! < _audioTrackObjs.length) {
          await _player.setAudioTrack(_audioTrackObjs[_pendingAudioTrack!]);
          _selectedAudioTrack = _pendingAudioTrack;
          _activeExternalDubSid = null; // Clear if switched back to internal
        }
      }

      // Subtitles
      if (_pendingSubtitleTrack != null &&
          _pendingSubtitleTrack != _selectedSubtitleTrack) {
        if (_pendingSubtitleTrack == -1) {
          final target = SubtitleTrack.no();
          await _player.setSubtitleTrack(target);
          _selectedSubtitleTrack = -1;
          _stickySubtitle = target;
        } else if (_pendingSubtitleTrack! >= 0 &&
            _pendingSubtitleTrack! < _subtitleTrackObjs.length) {
          final target = _subtitleTrackObjs[_pendingSubtitleTrack!];
          await _player.setSubtitleTrack(target);
          _selectedSubtitleTrack = _pendingSubtitleTrack;
          _stickySubtitle = target;
        }
      }
    } catch (e) {
      debugPrint('Error applying tracks: $e');
    }
    await _closeOverlayRestorePlayback();
  }

  Future<void> _cancelTracksAndClose() async {
    _pendingAudioTrack = _selectedAudioTrack;
    _pendingSubtitleTrack = _selectedSubtitleTrack;
    await _closeOverlayRestorePlayback();
  }

  Future<void> _switchExternalDub(Map<String, dynamic> dub) async {
    final sid = dub['subjectId'];
    final dPath = dub['detailPath'];
    if (sid == null || dPath == null) return;

    if (mounted) {
      setState(() {
        _isSwitching = true;
        _isBuffering = true;
        _activeExternalDubSid = sid;
      });
    }

    try {
      final res = await PrimeboxService.getStreams(
        detailUrl: dPath,
        subjectType: widget.primeboxSubjectType ?? 1,
        subjectIdIn: int.tryParse(sid),
        season: _currentSeason,
        episode: _currentEpisode,
      );

      final newStreams = res['streams'] as Map<String, dynamic>?;
      if (newStreams == null || newStreams.isEmpty) {
        if (mounted) AppToast.show(context, 'No streams for this dub');
        return;
      }

      // Update current sources
      final Map<String, Map<String, String>> updatedHttp = {};
      final Map<String, dynamic> updatedMetadata = {};

      newStreams.forEach((q, data) {
        final normQ = _normalizeQuality(q, q);
        updatedHttp.putIfAbsent(normQ, () => <String, String>{});

        if (data is Map) {
          final url = data['url']?.toString() ?? '';
          updatedHttp[normQ]!['Primebox'] = url;
          final sid = 'http|$normQ|Primebox';
          updatedMetadata[sid] = data;
        } else {
          updatedHttp[normQ]!['Primebox'] = data.toString();
        }
      });

      if (mounted) {
        setState(() {
          _currentHttpSources = updatedHttp;
          _currentHttpMetadata = updatedMetadata;
          _isSwitching = true;
          _isBuffering = true;
        });
      }

      // Pick best quality from new streams
      String? bestQ;
      for (final q in _qOrder) {
        if (updatedHttp.containsKey(q)) {
          bestQ = q;
          break;
        }
      }
      bestQ ??= updatedHttp.keys.first;

      final url = updatedHttp[bestQ]!['Primebox']!;

      await _switchToUrl(
        url: url,
        quality: bestQ,
        providerLabel: 'Primebox',
        isTorrent: false,
        sourceId: _httpSourceId(bestQ, 'Primebox'),
        resumePosition: _player.state.position,
      );
    } catch (e) {
      debugPrint('Dub switch error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSwitching = false;
          _isBuffering = false;
        });
      }
    }
  }

  final String _fallbackQuality = 'auto';

  String _normalizeQuality(dynamic qualityField, String fallbackText) {
    if (qualityField is int) return '${qualityField}p';

    if (qualityField is String && qualityField.trim().isNotEmpty) {
      final v = qualityField.toLowerCase();
      if (v.contains('fhd') || v.contains('full hd')) {
        return '1080p';
      }
      final q = _inferQualityFromFreeText(qualityField);
      if (q != null) return q;
    }

    final ft = fallbackText.toLowerCase();
    if (ft.contains('fhd') || ft.contains('full hd')) {
      return '1080p';
    }

    final inferred = _inferQualityFromFreeText(fallbackText);
    return inferred ?? _fallbackQuality;
  }

  String? _inferQualityFromFreeText(String s) {
    final t = s.toLowerCase();
    final m1 = RegExp(
      r'(?<!\d)(2160|1440|1080|720|480|360)\s*p?(?!\d)',
    ).firstMatch(t);
    if (m1 != null) return '${m1.group(1)}p';
    if (RegExp(r'\b(4k|uhd)\b').hasMatch(t)) return '2160p';
    if (RegExp(r'\b2k\b').hasMatch(t)) return '1440p';
    final m2 = RegExp(r'(2160|1440|1080|720|480|360)[pP]').firstMatch(s);
    if (m2 != null) return '${m2.group(1)}p';
    return null;
  }

  Future<void> _closeOverlayRestorePlayback() async {
    if (mounted) {
      setState(() {
        _showTracksPanel = false;
        _showQualityPanel = false;
      });
    }

    // 🔴 IMPORTANT: If we are currently switching sources, don't interfere
    // with the player state (play/pause) from here. Let _switchToUrl handle it.
    if (_isSwitching) return;

    if (_wasPlayingBeforeOverlay && _hasOpenedSource) {
      try {
        await _player.play();
        if (mounted) {
          _restartHideControlsTimer();
        }
      } catch (e) {
        debugPrint('Error restoring playback: $e');
      }
    }
  }

  Future<bool> _fetchTracks() async {
    try {
      final tracks = _player.state.tracks;
      if ((tracks.audio.isNotEmpty) || (tracks.subtitle.isNotEmpty)) {
        if (mounted) {
          _updateTracksFromState();
        }
        return true;
      }
    } catch (e) {
      debugPrint('Track fetch error: $e');
    }
    return false;
  }

  Future<void> _openQualityPanel() async {
    _wasPlayingBeforeOverlay = _isPlaying;
    if (_hasOpenedSource && _isPlaying) {
      try {
        await _player.pause();
      } catch (e) {
        debugPrint('Error pausing for quality panel: $e');
      }
    }
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _showQualityPanel = true;
        _showTracksPanel = false;
        _showControls = true;
      });
    }
  }

  @override
  void dispose() {
    _saveCurrentProgress(); // Final save
    _historyTimer?.cancel();
    _hideControlsTimer?.cancel();
    _gestureHudTimer?.cancel();
    _seekRippleTimer?.cancel();

    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _tracksSub?.cancel();
    _bufferSub?.cancel(); // NEW
    _completedSub?.cancel(); // <--- ADD THIS
    _previewDebounceTimer?.cancel(); // <-- NEW
    _errorSub?.cancel();
    _volumeSub?.cancel();

    if (!kIsWeb) {
      try {
        FlutterVolumeController.removeListener();
        if (Platform.isAndroid || Platform.isIOS) {
          FlutterVolumeController.updateShowSystemUI(true);
        }
      } catch (_) {}
      try {
        if (Platform.isAndroid || Platform.isIOS) {
          ScreenBrightness.instance.resetApplicationScreenBrightness();
        }
      } catch (_) {}
    }

    _player.dispose();
    _previewPlayer?.dispose();
    _seekDebounceTimer?.cancel();
    _keyboardFocusNode.dispose();
    _stopCurrentTorrent(erase: true);

    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    WakelockPlus.disable();

    _playPauseController.dispose();
    if (_isDesktop) {
      windowManager.setFullScreen(false);
      windowManager.setAlwaysOnTop(false);
    }
    super.dispose();
  }

  // ================= Thumbnail logic =================

  Future<void> _requestThumbnail(double sec) async {
    final template = widget.thumbnailUrlTemplate;
    if (template == null || template.isEmpty) return;

    final secondInt = sec.toInt();
    if (_lastRequestedSecond == secondInt.toDouble()) {
      return; // same second, skip
    }
    _lastRequestedSecond = secondInt.toDouble();

    final url = template.replaceAll('{second}', secondInt.toString());
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _previewThumbnail = res.bodyBytes;
          _previewSecond = secondInt.toDouble();
        });
      }
    } catch (e) {
      debugPrint('Thumbnail fetch failed: $e');
    }
  }

  void _scheduleThumbnailRequest(double sec) {
    _previewDebounceTimer?.cancel();
    // debounce to avoid spam requests
    _previewDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      _requestThumbnail(sec);
    });
  }

  Future<bool> _waitForStreamReady(String url) async {
    final uri = Uri.parse(url);

    // Try a few times with small delay
    for (int attempt = 0; attempt < 4; attempt++) {
      try {
        // Small byte-range GET so we don't read a ton of data
        final res = await http
            .get(
              uri,
              headers: const {
                'Range': 'bytes=0-1',
                'User-Agent': 'Mozilla/5.0',
              },
            )
            .timeout(const Duration(seconds: 3));

        // 200 = full, 206 = partial content – both are fine
        if (res.statusCode == 200 || res.statusCode == 206) {
          debugPrint(
            'Stream looks ready (status ${res.statusCode}) on attempt $attempt',
          );
          return true;
        } else {
          debugPrint(
            'Stream not ready yet: status ${res.statusCode} attempt $attempt',
          );
        }
      } catch (e) {
        debugPrint('Error probing stream readiness (attempt $attempt): $e');
      }

      // Wait a bit before next attempt
      await Future.delayed(const Duration(seconds: 1));
    }

    debugPrint('Stream did not become ready within attempts; giving up.');
    return false;
  }

  final bool _isHovered = false;
  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveCurrentProgress();
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          left: false, // ignore punch-hole / notch horizontally
          right: false,
          top: false,
          bottom: false,
          child: SizedBox.expand(
            child: _isExternalPlayerRunning
                ? _buildExternalPlayerActiveUI()
                : RawKeyboardListener(
                    focusNode: _keyboardFocusNode,
                    autofocus: true,
                    onKey: (event) async {
                      // Only react on key DOWN (avoid double trigger)
                      if (event is RawKeyDownEvent) {
                        // Space bar
                        if (event.logicalKey == LogicalKeyboardKey.space) {
                          _togglePlayPause();
                        }

                        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                          _seekBy(const Duration(seconds: 10));
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          _seekBy(const Duration(seconds: -10));
                        }
                        if (event.logicalKey == LogicalKeyboardKey.keyR) {
                          //videoboxfit
                          _cycleResizeMode();
                        }
                        //enter fullscreen
                        if (event.logicalKey == LogicalKeyboardKey.keyF) {
                          await _enterWindowFullscreen();
                        }
                        if (event.logicalKey == LogicalKeyboardKey.keyQ) {
                          _openQualityPanel();
                        }
                        if (event.logicalKey == LogicalKeyboardKey.keyT) {
                          _openTracksPanel();
                        }
                        if (event.logicalKey == LogicalKeyboardKey.backspace) {
                          if (_showTracksPanel || _showQualityPanel) {
                            _closeOverlayRestorePlayback();
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        }
                        if (event.logicalKey == LogicalKeyboardKey.escape) {
                          await _exitWindowFullscreen();
                        }
                      }
                    },
                    child: MouseRegion(
                      onEnter: (_) {
                        if (_isDesktop) {
                          setState(() {
                            _showControls = true;
                          });
                          _restartHideControlsTimer();
                        }
                      },
                      onHover: (_) {
                        if (_isDesktop) {
                          // If mouse is moving, keep controls visible and refresh timer
                          if (!_showControls) {
                            setState(() => _showControls = true);
                          }
                          _restartHideControlsTimer();
                        }
                      },
                      onExit: (_) {
                        if (_isDesktop) {
                          setState(() {
                            _showControls = false;
                          });
                        }
                      },
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (_) {
                          if (_showControls &&
                              !_showTracksPanel &&
                              !_showQualityPanel) {
                            _restartHideControlsTimer();
                          }
                        },
                        onPointerMove: (_) {
                          if (_showControls &&
                              !_showTracksPanel &&
                              !_showQualityPanel) {
                            _restartHideControlsTimer();
                          }
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 400),
                                opacity: _isSwitching ? 0.0 : 1.0,
                                child: Video(
                                  key: ValueKey('player_$_playerKey'),
                                  controller: _videoController,
                                  controls: NoVideoControls,
                                  fit: _videoBoxFit,
                                  subtitleViewConfiguration:
                                      SubtitleViewConfiguration(
                                        style: const TextStyle(
                                          fontSize: 19.5,
                                          height: 1.3,
                                          color: Colors.white,
                                          fontWeight: FontWeight.normal,
                                        ),
                                        textScaler: const TextScaler.linear(
                                          1.0,
                                        ),
                                        textAlign: TextAlign.center,
                                        padding: const EdgeInsets.fromLTRB(
                                          16.0,
                                          0.0,
                                          16.0,
                                          35.0,
                                        ),
                                      ),
                                ),
                              ),
                            ),

                            // Paused Metadata Overlay
                            if (!_isPlaying &&
                                !_showControls &&
                                _hasOpenedSource &&
                                !_isSwitching)
                              Positioned.fill(
                                child: _buildPausedMetadataOverlay(),
                              ),

                            if (_isBuffering || _isSwitching)
                              Positioned.fill(
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 300),
                                  opacity: 1.0,
                                  child: ClipRect(
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: 10,
                                        sigmaY: 10,
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.black.withValues(
                                                alpha: 0.7,
                                              ),
                                              Colors.black.withValues(
                                                alpha: 0.4,
                                              ),
                                              Colors.black.withValues(
                                                alpha: 0.7,
                                              ),
                                            ],
                                          ),
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  20,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.05),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.1),
                                                  ),
                                                ),
                                                child:
                                                    const CircularProgressIndicator(
                                                      strokeWidth: 3,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                            Color
                                                          >(Color(0xFFFF8C1A)),
                                                    ),
                                              ),
                                              const SizedBox(height: 24),
                                              Text(
                                                _isSwitching
                                                    ? 'Optimizing Stream...'
                                                    : 'Buffering...',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // Dynamic brightness visual overlay
                            if (_brightness < 1.0)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Container(
                                    color: Colors.black.withValues(
                                      alpha: ((1.0 - _brightness) * 0.75).clamp(
                                        0.0,
                                        0.85,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            Positioned.fill(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      if (!_isSwitching) {
                                        setState(
                                          () => _showControls = !_showControls,
                                        );
                                        if (_showControls &&
                                            !_showTracksPanel &&
                                            !_showQualityPanel) {
                                          _restartHideControlsTimer();
                                        }
                                      }
                                    },
                                    onDoubleTapDown: (details) =>
                                        _onDoubleTapDown(details, constraints),
                                    onDoubleTap: () {},
                                    onVerticalDragStart: (details) =>
                                        _onVerticalDragStart(
                                          details,
                                          constraints,
                                        ),
                                    onVerticalDragUpdate: (details) =>
                                        _onVerticalDragUpdate(
                                          details,
                                          constraints,
                                        ),
                                    onVerticalDragEnd: _onVerticalDragEnd,
                                    onVerticalDragCancel: _onVerticalDragCancel,
                                    child: const SizedBox.expand(),
                                  );
                                },
                              ),
                            ),

                            // Gesture HUD (Volume & Brightness Pill indicators + Double Tap ripple)
                            _buildGestureHudOverlay(),

                            if (_showControls &&
                                !_showTracksPanel &&
                                !_showQualityPanel) ...[
                              // Top bar
                              Positioned(
                                left: 30,
                                right: 30,
                                top: 8,
                                child: Row(
                                  children: [
                                    if (defaultTargetPlatform ==
                                        TargetPlatform.windows)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 15,
                                        ),
                                        child: IconButton(
                                          icon: const HugeIcon(
                                            icon: HugeIcons
                                                .strokeRoundedArrowLeft01,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                          onPressed: () async {
                                            await _saveCurrentProgress();
                                            if (mounted)
                                              Navigator.of(context).pop();
                                          },
                                        ),
                                      ),
                                    // Inside your Row children:
                                    Expanded(
                                      // 1. Wrap the Column in Expanded (to fix WIDTH issues in the Row)
                                      child: Column(
                                        mainAxisSize: MainAxisSize
                                            .min, // 2. Tell Column to shrink-wrap vertically
                                        crossAxisAlignment: CrossAxisAlignment
                                            .start, // Align text to the left
                                        children: [
                                          SizedBox(height: 10),
                                          Text(
                                            // 3. Removed 'Expanded' around the Text
                                            _videoTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 17.5,
                                            ),
                                          ),
                                          const SizedBox(
                                            height: 4,
                                          ), // Optional: Add a little spacing
                                          Text(
                                            // 3. Removed 'Expanded' around the Text
                                            _videoSubtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize:
                                                  13, // You might want this smaller, e.g., 12
                                              color: Colors
                                                  .grey, // Optional: Distinguish subtitle
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_hasAnyQualityOptions)
                                      IconButton(
                                        tooltip: 'Quality',
                                        onPressed: _isSwitching
                                            ? null
                                            : _openQualityPanel,
                                        icon: const HugeIcon(
                                          icon:
                                              HugeIcons.strokeRoundedSettings03,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                      ),
                                    IconButton(
                                      tooltip: 'Tracks',
                                      onPressed: _isSwitching
                                          ? null
                                          : _openTracksPanel,
                                      icon: const HugeIcon(
                                        icon:
                                            HugeIcons.strokeRoundedMusicNote01,
                                        color: Colors.white,
                                        size: 29,
                                      ),
                                    ),
                                    // --- NEW: resize button, cycles Default / Zoom / Stretch ---
                                    IconButton(
                                      tooltip: 'Resize: $_resizeLabel',
                                      onPressed: _isSwitching
                                          ? null
                                          : _cycleResizeMode,
                                      icon: const HugeIcon(
                                        icon: HugeIcons
                                            .strokeRoundedResizeFieldRectangle,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    ),
                                    // --- NEW: fullscreen button if desktop ---
                                    if (_isDesktop)
                                      IconButton(
                                        tooltip: 'Fullscreen',
                                        onPressed: isfullscreen
                                            ? _exitWindowFullscreen
                                            : _enterWindowFullscreen,
                                        icon: isfullscreen
                                            ? const HugeIcon(
                                                icon: HugeIcons
                                                    .strokeRoundedMinimizeScreen,
                                                color: Colors.white,
                                                size: 28,
                                              )
                                            : const HugeIcon(
                                                icon: HugeIcons
                                                    .strokeRoundedMaximizeScreen,
                                                color: Colors.white,
                                                size: 28,
                                              ),
                                      ),
                                  ],
                                ),
                              ),

                              // Center controls
                              Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SeekCircleButton(
                                      isForward: false,
                                      onTap: _isSwitching
                                          ? null
                                          : () => _seekBy(
                                              const Duration(seconds: -10),
                                            ),
                                    ),
                                    const SizedBox(width: 50),
                                    _circleBtn(
                                      big: true,
                                      onTap: _isSwitching
                                          ? null
                                          : _togglePlayPause,
                                      customIcon: AnimatedIcon(
                                        icon: AnimatedIcons.play_pause,
                                        progress: _playPauseController,
                                        size: 46,
                                        color: _isSwitching
                                            ? Colors.white24
                                            : Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 50),
                                    SeekCircleButton(
                                      isForward: true,
                                      onTap: _isSwitching
                                          ? null
                                          : () => _seekBy(
                                              const Duration(seconds: 10),
                                            ),
                                    ),
                                  ],
                                ),
                              ),

                              if (_hasEpisodeOverlay)
                                Positioned(
                                  right: 50,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior
                                          .opaque, // Ensures taps are caught accurately
                                      onTap: () async {
                                        await _player.pause();
                                        _toggleEpisodeOverlay();
                                      },
                                      child: const HugeIcon(
                                        icon:
                                            HugeIcons.strokeRoundedArrowLeft01,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                ),

                              // --- NEW: Next Episode Button Overlay ---
                              if (widget.isTvShow &&
                                  widget.onEpisodeSelected != null)
                                Positioned(
                                  right: 30,
                                  bottom: 90, // just above the slider
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(30),
                                      onTap: _isSwitching
                                          ? null
                                          : () {
                                              _player.pause();
                                              _playNextEpisode(autoPlay: false);
                                            },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF14151A,
                                          ).withValues(alpha: 0.95),
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.1,
                                            ),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.5,
                                              ),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              'Next Episode',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const HugeIcon(
                                              icon: HugeIcons
                                                  .strokeRoundedArrowRight01,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // Bottom seek bar + thumbnail preview
                              Positioned(
                                left: 30,
                                right: 30,
                                bottom: 20,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Builder(
                                      builder: (context) {
                                        final durSec = _duration.inSeconds == 0
                                            ? 1.0
                                            : _duration.inSeconds.toDouble();

                                        // While scrubbing, use _scrubValue (thumb position).
                                        // Otherwise, use actual playback position.
                                        final currentPosSec = _isScrubbing
                                            ? (_scrubValue ??
                                                  _position.inSeconds
                                                      .toDouble())
                                            : _position.inSeconds.toDouble();

                                        final value = currentPosSec
                                            .clamp(0.0, durSec)
                                            .toDouble();

                                        return LayoutBuilder(
                                          builder: (context, constraints) {
                                            final trackWidth =
                                                constraints.maxWidth;
                                            final fraction = value <= 0
                                                ? 0.0
                                                : (value / durSec);

                                            // The Slider has a default overlay padding of 24.0 on both sides.
                                            // To perfectly sync the bubble with the thumb, we account for this padding.
                                            final double sliderPadding = 24.0;
                                            final thumbCenterX =
                                                sliderPadding +
                                                fraction *
                                                    (trackWidth -
                                                        sliderPadding * 2);

                                            // --- NEW: Calculate hover center X for the bubble ---
                                            final double previewPosSec =
                                                _isScrubbing
                                                ? (_scrubValue ?? currentPosSec)
                                                : ((_isDesktop &&
                                                          _isHoveringSlider)
                                                      ? (_hoverValue ??
                                                            currentPosSec)
                                                      : currentPosSec);

                                            final double previewFraction =
                                                durSec <= 0
                                                ? 0.0
                                                : (previewPosSec / durSec)
                                                      .clamp(0.0, 1.0);
                                            final double previewCenterX =
                                                sliderPadding +
                                                previewFraction *
                                                    (trackWidth -
                                                        sliderPadding * 2);

                                            // Calculate the dynamic width of our preview bubble
                                            final double bubbleWidth =
                                                (_previewThumbnail != null ||
                                                    _previewController != null)
                                                ? (_isDesktop ? 250.0 : 140.0)
                                                : 90.0;
                                            // NEW: compute buffered fraction
                                            final bufferedSec = _buffered
                                                .inSeconds
                                                .toDouble();
                                            final bufferedClamped = bufferedSec
                                                .clamp(0.0, durSec);
                                            final bufferedFraction =
                                                durSec == 0.0
                                                ? 0.0
                                                : (bufferedClamped / durSec);
                                            return Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                SliderTheme(
                                                  data: SliderTheme.of(context).copyWith(
                                                    trackShape:
                                                        BufferedSliderTrackShape(
                                                          bufferedFraction:
                                                              bufferedFraction,
                                                        ),
                                                    thumbShape:
                                                        RoundSliderThumbShape(
                                                          enabledThumbRadius:
                                                              8.0,
                                                        ),
                                                  ),
                                                  child: MouseRegion(
                                                    onEnter: (_) => setState(
                                                      () => _isHoveringSlider =
                                                          true,
                                                    ),
                                                    onExit: (_) => setState(() {
                                                      _isHoveringSlider = false;
                                                      _hoverValue = null;
                                                    }),
                                                    onHover: (event) {
                                                      if (_isScrubbing) return;
                                                      double hoverFraction =
                                                          (event
                                                                  .localPosition
                                                                  .dx -
                                                              sliderPadding) /
                                                          (trackWidth -
                                                              sliderPadding *
                                                                  2);
                                                      hoverFraction =
                                                          hoverFraction.clamp(
                                                            0.0,
                                                            1.0,
                                                          );
                                                      final v =
                                                          hoverFraction *
                                                          durSec;
                                                      setState(() {
                                                        _hoverValue = v;
                                                      });

                                                      final now = DateTime.now()
                                                          .millisecondsSinceEpoch;
                                                      final seekPos = Duration(
                                                        milliseconds: (v * 1000)
                                                            .toInt(),
                                                      );

                                                      _seekDebounceTimer
                                                          ?.cancel();
                                                      if (now - _lastSeekTime >
                                                          250) {
                                                        _lastSeekTime = now;
                                                        _previewPlayer?.seek(
                                                          seekPos,
                                                        );
                                                      } else {
                                                        _seekDebounceTimer = Timer(
                                                          const Duration(
                                                            milliseconds: 250,
                                                          ),
                                                          () {
                                                            if (_isHoveringSlider &&
                                                                !_isScrubbing) {
                                                              _lastSeekTime =
                                                                  DateTime.now()
                                                                      .millisecondsSinceEpoch;
                                                              _previewPlayer
                                                                  ?.seek(
                                                                    seekPos,
                                                                  );
                                                            }
                                                          },
                                                        );
                                                      }
                                                    },
                                                    child: Slider(
                                                      min: 0.0,
                                                      max: durSec,

                                                      activeColor: const Color(
                                                        0xFFFF8C1A,
                                                      ),
                                                      thumbColor: const Color(
                                                        0xFFFF8C1A,
                                                      ),
                                                      inactiveColor:
                                                          const Color.fromARGB(
                                                            70,
                                                            255,
                                                            255,
                                                            255,
                                                          ),
                                                      value: value,
                                                      onChangeStart: (v) {
                                                        _hideControlsTimer
                                                            ?.cancel();
                                                        setState(() {
                                                          _isScrubbing = true;
                                                          _scrubValue = v;
                                                        });
                                                        _scheduleThumbnailRequest(
                                                          v,
                                                        );
                                                      },
                                                      onChanged: _isSwitching
                                                          ? null
                                                          : (v) {
                                                              setState(() {
                                                                _scrubValue = v;
                                                                _position = Duration(
                                                                  milliseconds:
                                                                      (v * 1000)
                                                                          .toInt(),
                                                                );
                                                              });
                                                              _scheduleThumbnailRequest(
                                                                v,
                                                              );

                                                              final now =
                                                                  DateTime.now()
                                                                      .millisecondsSinceEpoch;
                                                              final seekPos = Duration(
                                                                milliseconds:
                                                                    (v * 1000)
                                                                        .toInt(),
                                                              );

                                                              _seekDebounceTimer
                                                                  ?.cancel();
                                                              if (now -
                                                                      _lastSeekTime >
                                                                  250) {
                                                                _lastSeekTime =
                                                                    now;
                                                                if (_isScrubbing) {
                                                                  _previewPlayer
                                                                      ?.seek(
                                                                        seekPos,
                                                                      );
                                                                }
                                                              } else {
                                                                _seekDebounceTimer = Timer(
                                                                  const Duration(
                                                                    milliseconds:
                                                                        250,
                                                                  ),
                                                                  () {
                                                                    if (_isScrubbing) {
                                                                      _lastSeekTime =
                                                                          DateTime.now()
                                                                              .millisecondsSinceEpoch;
                                                                      _previewPlayer
                                                                          ?.seek(
                                                                            seekPos,
                                                                          );
                                                                    }
                                                                  },
                                                                );
                                                              }
                                                            },
                                                      onChangeEnd: (v) async {
                                                        if (!_isSwitching &&
                                                            _hasOpenedSource) {
                                                          try {
                                                            await _player.seek(
                                                              Duration(
                                                                milliseconds:
                                                                    (v * 1000)
                                                                        .toInt(),
                                                              ),
                                                            );
                                                          } catch (e) {
                                                            debugPrint(
                                                              'Error seeking on slider end: $e',
                                                            );
                                                          }
                                                        }

                                                        setState(() {
                                                          _isScrubbing = false;
                                                          _scrubValue = null;
                                                          _previewThumbnail =
                                                              null;
                                                        });

                                                        if (_isPlaying) {
                                                          _restartHideControlsTimer();
                                                        }
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                // --- NEW: beautifully modern preview bubble above thumb ---
                                                if (_isScrubbing ||
                                                    (_isDesktop &&
                                                        _isHoveringSlider))
                                                  Positioned(
                                                    bottom: 45, // above slider
                                                    left:
                                                        (previewCenterX -
                                                                (bubbleWidth /
                                                                    2))
                                                            .clamp(
                                                              16.0,
                                                              trackWidth -
                                                                  bubbleWidth -
                                                                  16.0,
                                                            ),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (_previewThumbnail !=
                                                                null ||
                                                            _previewController !=
                                                                null) ...[
                                                          Container(
                                                            width: _isDesktop
                                                                ? 250
                                                                : 140,
                                                            height: _isDesktop
                                                                ? 160
                                                                : 80,
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xFF1A1D24,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                              border: Border.all(
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                      alpha:
                                                                          0.15,
                                                                    ),
                                                                width: 1.5,
                                                              ),
                                                              boxShadow: [
                                                                BoxShadow(
                                                                  color: Colors
                                                                      .black
                                                                      .withValues(
                                                                        alpha:
                                                                            0.6,
                                                                      ),
                                                                  blurRadius:
                                                                      15,
                                                                  offset:
                                                                      const Offset(
                                                                        0,
                                                                        8,
                                                                      ),
                                                                ),
                                                              ],
                                                            ),
                                                            clipBehavior:
                                                                Clip.hardEdge,
                                                            child:
                                                                _previewThumbnail !=
                                                                    null
                                                                ? Image.memory(
                                                                    _previewThumbnail!,
                                                                    fit: BoxFit
                                                                        .cover,
                                                                  )
                                                                : Video(
                                                                    controller:
                                                                        _previewController!,
                                                                    controls:
                                                                        NoVideoControls,
                                                                    fit: BoxFit
                                                                        .cover,
                                                                  ),
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                        ],
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 16,
                                                                vertical: 8,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                const Color(
                                                                  0xFF14151A,
                                                                ).withValues(
                                                                  alpha: 0.95,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  20,
                                                                ),
                                                            border: Border.all(
                                                              color: Colors
                                                                  .white
                                                                  .withValues(
                                                                    alpha: 0.1,
                                                                  ),
                                                              width: 1,
                                                            ),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors
                                                                    .black
                                                                    .withValues(
                                                                      alpha:
                                                                          0.5,
                                                                    ),
                                                                blurRadius: 10,
                                                                offset:
                                                                    const Offset(
                                                                      0,
                                                                      4,
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                          child: Text(
                                                            _fmt(
                                                              Duration(
                                                                seconds:
                                                                    previewPosSec
                                                                        .toInt(),
                                                              ),
                                                            ),
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 15,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  color: Colors
                                                                      .white,
                                                                  letterSpacing:
                                                                      0.5,
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    ),

                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 10,
                                          ),
                                          child: Text(
                                            _fmt(_position),
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 10,
                                          ),
                                          child: Text(
                                            _fmt(_duration),
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            if (_showTracksPanel) _buildTracksOverlay(),
                            if (_showQualityPanel) _buildQualityOverlay(),
                            if (_showEpisodeOverlay) _buildEpisodeOverlay(),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // Updated Helper Widget
  Widget _circleBtn({
    IconData? icon,
    Widget? customIcon,
    VoidCallback? onTap,
    bool big = false,
  }) {
    final enabled = onTap != null;
    final size = big ? 84.0 : 52.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: enabled ? 0.010 : 0.05),
                Colors.white.withValues(alpha: enabled ? 0.04 : 0.02),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: enabled ? 0.2 : 0.05),
              width: 1.2,
            ),
          ),
          child: Center(
            child:
                customIcon ??
                Icon(
                  icon,
                  size: big ? 46 : 28,
                  color: enabled ? Colors.white : Colors.white24,
                ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadLocalSubtitleFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;

        final track = SubtitleTrack.uri(
          'file://$path',
          title: name,
          language: 'local',
        );

        setState(() {
          // Add to the beginning of discovered subs so it shows at the top
          _discoveredSubs.insert(0, track);
        });

        // Update tracks and apply
        _updateTracksFromState();
        await _player.setSubtitleTrack(track);

        // Also update the UI indices immediately
        _updateTracksFromState();

        _stickySubtitle = track;

        if (mounted) {
          AppToast.show(
            context,
            'Loaded: $name',
            icon: Icons.subtitles_rounded,
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking subtitle file: $e');
      if (mounted) {
        AppToast.show(
          context,
          'Failed to load subtitle',
          icon: Icons.error_outline,
        );
      }
    }
  }

  /// Load subtitles provided directly by the backend (/api/extract subtitles field).
  /// Called automatically after the initial source opens.
  Future<void> _loadBackendSubtitles() async {
    final urlMap = _currentSubtitleUrls;
    if (urlMap == null || urlMap.isEmpty) return;

    debugPrint('[subtitles] Loading ${urlMap.length} language(s) from backend');

    for (final entry in urlMap.entries) {
      final lang = entry.key;
      final urls = entry.value;
      for (final url in urls) {
        if (url.isEmpty) continue;
        final key = '$lang|$url';
        if (_externalSubtitleTracks.containsKey(key)) continue;

        try {
          final track = SubtitleTrack.uri(
            url,
            title: lang,
            language: lang.toLowerCase(),
          );
          _externalSubtitleTracks[key] = track;
          _discoveredSubs.add(track);
          debugPrint('[subtitles] Discovered backend "$lang" → $url');
        } catch (e) {
          debugPrint('[subtitles] Failed to parse "$lang" → $url : $e');
        }
      }
    }

    if (mounted) {
      _updateTracksFromState();

      // Auto-select if none selected
      if (_discoveredSubs.isNotEmpty &&
          (_selectedSubtitleTrack == -1 || _selectedSubtitleTrack == null)) {
        final sortedSubs = List<SubtitleTrack>.from(_discoveredSubs)
          ..sort((a, b) {
            final rankA = _getLanguageRank(a.title ?? a.language ?? '');
            final rankB = _getLanguageRank(b.title ?? b.language ?? '');
            if (rankA != rankB) return rankA.compareTo(rankB);
            return (a.title ?? a.language ?? '').compareTo(
              b.title ?? b.language ?? '',
            );
          });
        final target = sortedSubs.first;
        await _player.setSubtitleTrack(target);
        _stickySubtitle = target;
      }
    }
  }

  // ------ Overlays ------

  Widget _buildTracksOverlay() {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF050509).withValues(alpha: 0.85),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---------- Header ----------
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFF8C1A,
                          ).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.settings_input_component_rounded,
                          size: 20,
                          color: Color(0xFFFF8C1A),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Media Settings',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                        onPressed: _cancelTracksAndClose,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 10),

                  // ---------- Content ----------
                  Expanded(
                    child: Row(
                      children: [
                        // ----- AUDIO COLUMN -----
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF171B26), Color(0xFF090A10)],
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.10),
                                width: 1.0,
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.audiotrack_rounded,
                                      size: 16,
                                      color: Colors.white54,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'AUDIO TRACK',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        color: Colors.white54,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (_audioTracks.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          color: Colors.white.withValues(
                                            alpha: 0.06,
                                          ),
                                        ),
                                        child: Text(
                                          '${_audioTracks.length} tracks',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white.withValues(
                                              alpha: 0.8,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Divider(
                                  height: 1,
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _audioTracks.isEmpty
                                      ? const Center(
                                          child: Text(
                                            'No audio tracks available.',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.white70,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        )
                                      : () {
                                          final orderedAudioKeys =
                                              _audioTracks.keys.toList()
                                                ..sort((a, b) {
                                                  if (a == _selectedAudioTrack)
                                                    return -1;
                                                  if (b == _selectedAudioTrack)
                                                    return 1;
                                                  return 0;
                                                });

                                          return ListView.separated(
                                            itemCount: orderedAudioKeys.length,
                                            separatorBuilder: (_, _) =>
                                                const SizedBox(height: 8),
                                            itemBuilder: (context, index) {
                                              final id =
                                                  orderedAudioKeys[index];
                                              final title =
                                                  _audioTracks[id] ?? '';
                                              final selected =
                                                  id == _pendingAudioTrack;

                                              return GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    _pendingAudioTrack = id;
                                                  });
                                                },
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                    gradient: selected
                                                        ? const LinearGradient(
                                                            begin: Alignment
                                                                .topLeft,
                                                            end: Alignment
                                                                .bottomRight,
                                                            colors: [
                                                              Color(0xFFFFAD66),
                                                              Color(0xFFFF7A00),
                                                            ],
                                                          )
                                                        : LinearGradient(
                                                            begin: Alignment
                                                                .topLeft,
                                                            end: Alignment
                                                                .bottomRight,
                                                            colors: [
                                                              Colors.white
                                                                  .withValues(
                                                                    alpha: 0.05,
                                                                  ),
                                                              Colors.white
                                                                  .withValues(
                                                                    alpha: 0.01,
                                                                  ),
                                                            ],
                                                          ),
                                                    border: Border.all(
                                                      color: selected
                                                          ? Colors.white
                                                                .withValues(
                                                                  alpha: 0.28,
                                                                )
                                                          : Colors.white
                                                                .withValues(
                                                                  alpha: 0.10,
                                                                ),
                                                      width: selected
                                                          ? 1.2
                                                          : 1.0,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.volume_up_rounded,
                                                        size: 18,
                                                        color: selected
                                                            ? Colors.black
                                                            : Colors.white60,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              title,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: selected
                                                                    ? Colors
                                                                          .black
                                                                    : Colors
                                                                          .white,
                                                              ),
                                                            ),
                                                            if (id ==
                                                                _selectedAudioTrack)
                                                              Text(
                                                                'Current',
                                                                style: TextStyle(
                                                                  fontSize: 9,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  color:
                                                                      selected
                                                                      ? Colors.black.withValues(
                                                                          alpha:
                                                                              0.6,
                                                                        )
                                                                      : const Color(
                                                                          0xFFFF8C1A,
                                                                        ),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      AnimatedContainer(
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 200,
                                                            ),
                                                        width: 18,
                                                        height: 18,
                                                        decoration: BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          border: Border.all(
                                                            color: selected
                                                                ? Colors.black
                                                                : Colors
                                                                      .white24,
                                                            width: selected
                                                                ? 5
                                                                : 1.5,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          );
                                        }(),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // ----- SUBTITLES COLUMN -----
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF171B26), Color(0xFF090A10)],
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.10),
                                width: 1.0,
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.subtitles_rounded,
                                      size: 16,
                                      color: Colors.white54,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'SUBTITLES',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                          color: Colors.white54,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: _loadLocalSubtitleFile,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFFFF8C1A,
                                          ).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFFFF8C1A,
                                            ).withValues(alpha: 0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.folder_open_rounded,
                                              size: 14,
                                              color: Color(0xFFFF8C1A),
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'ADD LOCAL SUB',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFFFF8C1A),
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (_subtitleTracks.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          color: Colors.white.withValues(
                                            alpha: 0.06,
                                          ),
                                        ),
                                        child: Text(
                                          '${_subtitleTracks.length} tracks',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white.withValues(
                                              alpha: 0.8,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Divider(
                                  height: 1,
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: () {
                                    final orderedSubKeys =
                                        [-1, ..._subtitleTracks.keys]
                                          ..sort((a, b) {
                                            if (a == _selectedSubtitleTrack)
                                              return -1;
                                            if (b == _selectedSubtitleTrack)
                                              return 1;
                                            return 0;
                                          });

                                    return ListView.separated(
                                      itemCount: orderedSubKeys.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (context, index) {
                                        final id = orderedSubKeys[index];
                                        if (id == -1) {
                                          final selected =
                                              _pendingSubtitleTrack == -1;
                                          return GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _pendingSubtitleTrack = -1;
                                              });
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                gradient: selected
                                                    ? const LinearGradient(
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
                                                        colors: [
                                                          Color(0xFFFFC57A),
                                                          Color(0xFFFF8C1A),
                                                        ],
                                                      )
                                                    : const LinearGradient(
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
                                                        colors: [
                                                          Color(0xFF202735),
                                                          Color(0xFF131722),
                                                        ],
                                                      ),
                                                border: Border.all(
                                                  color: selected
                                                      ? Colors.white.withValues(
                                                          alpha: 0.28,
                                                        )
                                                      : Colors.white.withValues(
                                                          alpha: 0.10,
                                                        ),
                                                  width: selected ? 1.2 : 1.0,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.subtitles_off_rounded,
                                                    size: 18,
                                                    color: selected
                                                        ? Colors.black
                                                        : Colors.white70,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Disabled',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: selected
                                                                ? Colors.black
                                                                : Colors.white,
                                                          ),
                                                        ),
                                                        if (_selectedSubtitleTrack ==
                                                            -1)
                                                          Text(
                                                            'Current',
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: selected
                                                                  ? Colors.black
                                                                        .withValues(
                                                                          alpha:
                                                                              0.6,
                                                                        )
                                                                  : const Color(
                                                                      0xFFFF8C1A,
                                                                    ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Icon(
                                                    selected
                                                        ? Icons
                                                              .check_circle_rounded
                                                        : Icons
                                                              .radio_button_unchecked,
                                                    size: 18,
                                                    color: selected
                                                        ? Colors.black
                                                        : Colors.white54,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }

                                        final title = _subtitleTracks[id] ?? '';
                                        final selected =
                                            id == _pendingSubtitleTrack;

                                        return GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _pendingSubtitleTrack = id;
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              gradient: selected
                                                  ? const LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
                                                      colors: [
                                                        Color(0xFFFFC57A),
                                                        Color(0xFFFF8C1A),
                                                      ],
                                                    )
                                                  : const LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
                                                      colors: [
                                                        Color(0xFF202735),
                                                        Color(0xFF131722),
                                                      ],
                                                    ),
                                              border: Border.all(
                                                color: selected
                                                    ? Colors.white.withValues(
                                                        alpha: 0.28,
                                                      )
                                                    : Colors.white.withValues(
                                                        alpha: 0.10,
                                                      ),
                                                width: selected ? 1.2 : 1.0,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.subtitles_rounded,
                                                  size: 18,
                                                  color: selected
                                                      ? Colors.black
                                                      : Colors.white60,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: selected
                                                              ? Colors.black
                                                              : Colors.white,
                                                        ),
                                                      ),
                                                      if (id ==
                                                          _selectedSubtitleTrack)
                                                        Text(
                                                          'Current',
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: selected
                                                                ? Colors.black
                                                                      .withValues(
                                                                        alpha:
                                                                            0.6,
                                                                      )
                                                                : const Color(
                                                                    0xFFFF8C1A,
                                                                  ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 200,
                                                  ),
                                                  width: 18,
                                                  height: 18,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: selected
                                                          ? Colors.black
                                                          : Colors.white24,
                                                      width: selected ? 5 : 1.5,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  }(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---------- Footer Buttons ----------
                  Row(
                    children: [
                      ThreeDButton3D(
                        shape: ThreeDButtonShape.pill,
                        label: 'Cancel',
                        height: 40,
                        width: 100,
                        isSelected: false,
                        onTap: () {
                          _cancelTracksAndClose();
                        },
                      ),
                      const Spacer(),
                      ThreeDButton3D(
                        shape: ThreeDButtonShape.pill,
                        label: 'Apply',
                        height: 40,
                        width: 100,
                        isSelected: true,
                        onTap: () {
                          _applyPendingTracksAndClose();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getBaseQuality(String q) {
    final lower = q.toLowerCase();
    if (lower.contains('2160p') ||
        lower.contains('4k') ||
        lower.contains('uhd'))
      return '4K';
    if (lower.contains('1440p') || lower.contains('2k')) return '1440p';
    if (lower.contains('1080p') || lower.contains('fhd')) return '1080p';
    if (lower.contains('720p') || lower.contains('hd')) return '720p';
    if (lower.contains('480p') || lower.contains('sd')) return '480p';
    if (lower.contains('360p')) return '360p';
    if (q.isNotEmpty && q.toLowerCase() != 'auto') return q;
    return '4K';
  }

  String _getBaseProvider(String provider) {
    String p = provider;
    final langs = [
      'hindi',
      'original',
      'ptbr',
      'english',
      'tamil',
      'telugu',
      'malayalam',
      'spanish',
      'portuguese',
      'eng',
    ];
    for (final l in langs) {
      if (p.toLowerCase().startsWith(l)) {
        p = p.substring(l.length).trim();
      } else if (p.toLowerCase().contains(l)) {
        p = p.replaceAll(RegExp(l, caseSensitive: false), '').trim();
      }
    }
    p = p.replaceAll(RegExp(r'^\W+'), '').trim();
    if (p.isEmpty) return 'Server';
    return p;
  }

  static int _getLanguageRank(String str) {
    final lower = str.toLowerCase();
    if (lower.contains('original')) return 0;
    if (lower.contains('malayalam') || lower.contains('mal')) return 1;
    if (lower.contains('tamil') || lower.contains('tam')) return 2;
    if (lower.contains('hindi') || lower.contains('hin')) return 3;
    if (lower.contains('telugu') || lower.contains('tel')) return 4;
    if (lower.contains('kannada') || lower.contains('kan')) return 5;
    if (lower.contains('english') || lower.contains('eng')) return 6;
    if (lower.contains('spanish') ||
        lower.contains('esla') ||
        lower.contains('spa'))
      return 7;
    if (lower.contains('french') ||
        lower.contains('fra') ||
        lower.contains('fre'))
      return 8;
    if (lower.contains('portuguese') ||
        lower.contains('ptbr') ||
        lower.contains('por'))
      return 9;
    return 100;
  }

  String _getLanguageFromProvider(String p) {
    final lower = p.toLowerCase();
    String lang = 'Original';
    if (lower.contains('hindi') || lower.contains('hin'))
      lang = 'Hindi';
    else if (lower.contains('malayalam') || lower.contains('mal'))
      lang = 'Malayalam';
    else if (lower.contains('tamil') || lower.contains('tam'))
      lang = 'Tamil';
    else if (lower.contains('telugu') || lower.contains('tel'))
      lang = 'Telugu';
    else if (lower.contains('ptbr') ||
        lower.contains('pt-br') ||
        lower.contains('portuguese'))
      lang = 'Portuguese (BR)';
    else if (lower.contains('esla') ||
        lower.contains('es-la') ||
        lower.contains('spanish'))
      lang = 'Spanish (LA)';
    else if (lower.contains('eng'))
      lang = 'English';

    if (lang == 'Original' && !lower.contains('original')) {
      final firstWord = p.split(' ').first;
      if (firstWord.isNotEmpty && !firstWord.contains(RegExp(r'[^a-zA-Z]'))) {
        lang = firstWord[0].toUpperCase() + firstWord.substring(1);
      }
    }
    return lang;
  }

  List<String> _orderedQualitiesForOverlay() {
    final qSet = <String>{};
    for (final k in _httpSources.keys) {
      final base = _getBaseQuality(k);
      if (base.toLowerCase() != 'auto') qSet.add(base);
    }
    for (final e in _torrentStreams) {
      final q = (e['quality'] as String?) ?? '';
      final base = _getBaseQuality(q);
      if (base.toLowerCase() != 'auto') qSet.add(base);
    }
    final ordered = <String>[];
    for (final q in _qOrder) {
      if (qSet.contains(q)) ordered.add(q);
    }
    for (final q in qSet) {
      if (!ordered.contains(q)) ordered.add(q);
    }
    return ordered;
  }

  Widget _buildQualityOverlay() {
    final s = _httpSources;
    final ts = _torrentStreams;
    final qualities = _orderedQualitiesForOverlay();

    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF050509).withValues(alpha: 0.85),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---------- HEADER ----------
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFF8C1A,
                          ).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.stream_rounded,
                          size: 20,
                          color: Color(0xFFFF8C1A),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Stream Sources',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      if (_selectedProviderLabel != null &&
                          _selectedQuality.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: const Color(0xFF191D27),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '${_prettyQuality(_selectedQuality)} · ${_cleanProviderLabel(_selectedProviderLabel ?? "")}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                        onPressed: _closeOverlayRestorePlayback,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 10),

                  // ---------- BODY ----------
                  Expanded(
                    child: qualities.isEmpty
                        ? const Center(
                            child: Text(
                              'No quality variants available.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: qualities.length,
                            itemBuilder: (_, i) {
                              final q = qualities[i]; // q is now a BASE quality

                              // Find matching full keys for this base quality
                              final matchingHttpKeys = s.keys
                                  .where((k) => _getBaseQuality(k) == q)
                                  .toList();
                              final httpProviders =
                                  <String, Map<String, String>>{};
                              for (final k in matchingHttpKeys) {
                                final provs = s[k]!;
                                for (final p in provs.keys) {
                                  final bp = _getBaseProvider(p);
                                  if (!httpProviders.containsKey(bp)) {
                                    httpProviders[bp] = {
                                      'fullKey': k,
                                      'originalProvider': p,
                                      'url': provs[p]!,
                                    };
                                  }
                                }
                              }

                              final torrentForQ = ts
                                  .where(
                                    (e) =>
                                        _getBaseQuality(
                                          (e['quality'] as String?) ?? 'auto',
                                        ) ==
                                        q,
                                  )
                                  .toList();

                              if (httpProviders.isEmpty &&
                                  torrentForQ.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              final children = <Widget>[];

                              // Section label: “1080p”, “720p”, ...
                              children.add(
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    12,
                                    8,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF8C1A),
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _prettyQuality(q).toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.0,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              // ---------- HTTP SOURCES ----------
                              final sortedBaseProviders =
                                  httpProviders.keys.toList()..sort((a, b) {
                                    final rankA = _getLanguageRank(a);
                                    final rankB = _getLanguageRank(b);
                                    if (rankA != rankB)
                                      return rankA.compareTo(rankB);
                                    return a.compareTo(b);
                                  });

                              if (sortedBaseProviders.isNotEmpty) {
                                final baseProvider = sortedBaseProviders.first;
                                final data = httpProviders[baseProvider]!;
                                final fullKey = data['fullKey']!;
                                final originalProvider =
                                    data['originalProvider']!;
                                final url = data['url']!;
                                final id = _httpSourceId(
                                  fullKey,
                                  originalProvider,
                                );

                                final isSelected =
                                    !_selectedIsTorrent &&
                                    _getBaseQuality(_selectedQuality) == q;

                                children.add(
                                  _buildQualitySourceCard(
                                    isSelected: isSelected,
                                    leading: _buildQualityBadge(
                                      _prettyQuality(q),
                                      isSelected: isSelected,
                                    ),
                                    title: _videoTitle,
                                    subtitle: 'Alpha Server',
                                    trailingIconSelected:
                                        Icons.check_circle_rounded,
                                    trailingIconUnselected:
                                        Icons.radio_button_unchecked,
                                    onTap: () {
                                      if (!isSelected) {
                                        _selectHttpSource(
                                          fullKey,
                                          originalProvider,
                                          url,
                                          id,
                                        ); // async, no await
                                      }
                                      _closeOverlayRestorePlayback(); // close UI immediately
                                    },
                                  ),
                                );
                              }

                              // ---------- TORRENT SOURCES ----------
                              for (final e in torrentForQ) {
                                final id = _torrentSourceId(e);
                                final isSelected = _selectedSourceId == id;
                                final label =
                                    e['label']?.toString() ?? 'Torrent';
                                final sizeBytes = (e['videoSize'] is num)
                                    ? e['videoSize'] as num
                                    : 0;
                                final sizeStr = sizeBytes > 0
                                    ? _friendlyBytes(sizeBytes.toInt())
                                    : '';

                                children.add(
                                  _buildQualitySourceCard(
                                    isSelected: isSelected,
                                    leading: _buildTorrentBadge(),
                                    title:
                                        '$_videoTitle — ${_prettyQuality(q)}',
                                    subtitle: sizeStr.isNotEmpty
                                        ? '${_cleanProviderLabel(label)} • $sizeStr'
                                        : _cleanProviderLabel(label),
                                    trailingIconSelected:
                                        Icons.check_circle_rounded,
                                    trailingIconUnselected:
                                        Icons.radio_button_unchecked,
                                    onTap: () {
                                      _selectTorrentSource(
                                        e,
                                        id,
                                      ); // async, no await
                                      _closeOverlayRestorePlayback(); // close UI immediately
                                    },
                                  ),
                                );
                              }

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: children,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Card used for each source row (HTTP / Torrent)
  Widget _buildQualitySourceCard({
    required bool isSelected,
    required Widget leading,
    required String title,
    required String subtitle,
    required IconData trailingIconSelected,
    required IconData trailingIconUnselected,
    required VoidCallback onTap,
    //
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isSelected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFAD66), Color(0xFFFF7A00)],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.01),
                  ],
                ),
          border: Border.all(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.10),
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? Colors.black.withValues(alpha: 0.7)
                          : Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.black : Colors.white24,
                  width: isSelected ? 5 : 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityBadge(String label, {required bool isSelected}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          //i need black background if selected
          colors: isSelected
              ? [
                  Colors.black.withValues(alpha: 0.82),
                  Colors.black.withValues(alpha: 0.76),
                ]
              : [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.04),
                ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildTorrentBadge() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: const Center(
        child: Icon(Icons.downloading_rounded, size: 20, color: Colors.white70),
      ),
    );
  }

  String _prettyQuality(String q) {
    switch (q) {
      case '2160p':
        return '4K';
      case '1440p':
        return '1440p';
      case '1080p':
        return '1080p';
      case '720p':
        return '720p';
      case '480p':
        return '480p';
      case '360p':
        return '360p';
      default:
        return q;
    }
  }

  String _cleanProviderLabel(String rawProvider) {
    final lower = rawProvider.toLowerCase().trim();
    if (lower == 'filmyfly') return 'Beta Server';
    if (lower == 'lookmovie') return 'Gamma Server';
    if (lower == 'lookmovie2') return 'Gamma 2 Server';
    if (lower == 'aoneroom') return 'Delta Server';
    if (lower == 'direct') return 'Direct Server';
    if (lower == 'torrent' ||
        lower.contains('torrent') ||
        lower.contains('p2p'))
      return 'P2P Server';
    if (lower == 'cinemaos') return 'Epsilon Server';

    return 'Alpha Server';
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _trackName(int id, String label) {
    final name = label.trim();
    return name.isEmpty ? 'Track $id' : name;
  }

  String _friendlyBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double dbl = bytes.toDouble();
    while (dbl >= 1024 && i < suffixes.length - 1) {
      dbl /= 1024;
      i++;
    }
    return '${dbl.toStringAsFixed(dbl >= 10 ? 0 : 1)} ${suffixes[i]}';
  }

  String _formatLanguageName(String code) {
    final lower = code.toLowerCase().trim();
    const map = {
      'hin': 'Hindi',
      'hindi': 'Hindi',
      'eng': 'English',
      'english': 'English',
      'tel': 'Telugu',
      'telugu': 'Telugu',
      'tam': 'Tamil',
      'tamil': 'Tamil',
      'mal': 'Malayalam',
      'malayalam': 'Malayalam',
      'kan': 'Kannada',
      'kannada': 'Kannada',
      'spa': 'Spanish',
      'spanish': 'Spanish',
      'esla': 'Spanish (LA)',
      'fra': 'French',
      'fre': 'French',
      'french': 'French',
      'ger': 'German',
      'deu': 'German',
      'german': 'German',
      'ita': 'Italian',
      'italian': 'Italian',
      'por': 'Portuguese',
      'ptbr': 'Portuguese (BR)',
      'portuguese': 'Portuguese',
      'rus': 'Russian',
      'russian': 'Russian',
      'jpn': 'Japanese',
      'japanese': 'Japanese',
      'kor': 'Korean',
      'korean': 'Korean',
      'zho': 'Chinese',
      'chi': 'Chinese',
      'chinese': 'Chinese',
      'ara': 'Arabic',
      'arabic': 'Arabic',
      'und': 'Original',
    };
    if (map.containsKey(lower)) return map[lower]!;
    if (lower.length > 2) {
      return lower[0].toUpperCase() + lower.substring(1);
    }
    return code.toUpperCase();
  }

  String _buildTrackLabel(
    String? title,
    String? language, {
    required String fallback,
  }) {
    final t = (title ?? '').trim();
    final rawLang = (language ?? '').trim();
    final lang = rawLang.isNotEmpty ? _formatLanguageName(rawLang) : '';
    if (t.isNotEmpty && lang.isNotEmpty) return '$t ($lang)';
    if (t.isNotEmpty) return t;
    if (lang.isNotEmpty) return '$lang Audio';
    return fallback;
  }

  Widget _buildExternalPlayerActiveUI() {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.monitor_rounded, size: 80, color: Colors.white54),
          const SizedBox(height: 24),
          const Text(
            'Playing in External Player',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.title,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: () {
              if (_externalProcess != null) {
                _externalProcess!.kill();
              }
            },
            icon: const Icon(Icons.close),
            label: const Text('Close Player'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPausedMetadataOverlay() {
    TvEpisodeSummary? epSummary;
    if (widget.isTvShow && _currentSeason != null && _currentEpisode != null) {
      final eps = _episodeCache[_currentSeason!];
      if (eps != null) {
        try {
          epSummary = eps.firstWhere((e) => e.episode == _currentEpisode);
        } catch (_) {}
      }
    }

    final Map<String, dynamic> meta = _currentHttpMetadata;
    final String? logo = meta['logo'] as String?;
    final String? plot =
        (epSummary?.overview != null && epSummary!.overview!.isNotEmpty)
        ? epSummary!.overview
        : (meta['plot'] ?? meta['description'] ?? meta['overview']) as String?;

    final String? rating =
        (meta['rating']?.toString() != "0" &&
            meta['rating']?.toString() != "0.0")
        ? meta['rating']?.toString()
        : null;

    final String? year = meta['year']?.toString();

    int? runtimeMins;
    if (epSummary?.runtime != null && epSummary!.runtime! > 0) {
      runtimeMins = epSummary!.runtime;
    } else if (meta['duration'] != null || meta['runtime'] != null) {
      final dynDur = meta['duration'] ?? meta['runtime'];
      if (dynDur is int)
        runtimeMins = dynDur;
      else if (dynDur is String)
        runtimeMins = int.tryParse(dynDur);
    }
    String? runtimeStr;
    if (runtimeMins != null && runtimeMins > 0) {
      final h = runtimeMins ~/ 60;
      final m = runtimeMins % 60;
      runtimeStr = h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 900;

    final double titleFontSize = isSmallScreen ? 32 : 46;
    final double subtitleFontSize = isSmallScreen ? 16 : 22;
    final double metaFontSize = isSmallScreen ? 13 : 15;
    final double plotFontSize = isSmallScreen ? 13 : 16;
    final double spacing = isSmallScreen ? 12 : 20;

    Widget titleWidget = Padding(
      padding: EdgeInsets.only(bottom: isSmallScreen ? 8 : 10),
      child: Text(
        widget.title,
        style: TextStyle(
          fontSize: titleFontSize,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: -0.5,
          height: 1.1,
          shadows: const [
            Shadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 2)),
          ],
        ),
      ),
    );

    return IgnorePointer(
      child: Container(
        padding: EdgeInsets.only(
          left: isSmallScreen ? 40 : 60,
          top: isSmallScreen ? 20 : 40,
          bottom: isSmallScreen ? 20 : 40,
          right: isSmallScreen ? 60 : 100,
        ),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.90),
              Colors.black.withValues(alpha: 0.75),
              Colors.black.withValues(alpha: 0.40),
              Colors.black.withValues(alpha: 0.10),
              Colors.transparent,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: const [0.0, 0.35, 0.60, 0.85, 1.0],
          ),
        ),
        child: FractionallySizedBox(
          widthFactor: isSmallScreen ? 0.65 : 0.45,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (logo != null && logo.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: spacing),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: isSmallScreen ? 90 : 140,
                        maxWidth: isSmallScreen ? 240 : 340,
                      ),
                      child: CachedNetworkImage(
                        imageUrl: logo,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        errorWidget: (c, u, e) => titleWidget,
                      ),
                    ),
                  )
                else
                  titleWidget,

                if (widget.isTvShow) ...[
                  Text(
                    'Season ${_currentSeason ?? widget.initialSeason ?? 1} Episode ${_currentEpisode ?? widget.initialEpisode ?? 1}${(_currentEpisodeTitle ?? widget.episodeTitle).isNotEmpty ? ' • ' + (_currentEpisodeTitle ?? widget.episodeTitle) : ''}',
                    style: TextStyle(
                      fontSize: subtitleFontSize,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.85),
                      shadows: const [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: spacing),
                ],

                if (rating != null || runtimeStr != null || year != null) ...[
                  Row(
                    children: [
                      if (rating != null) ...[
                        const Icon(
                          Icons.star,
                          color: Color(0xFFF5C518),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          rating,
                          style: TextStyle(
                            fontSize: metaFontSize,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.7),
                            shadows: const [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      if (runtimeStr != null) ...[
                        Text(
                          runtimeStr,
                          style: TextStyle(
                            fontSize: metaFontSize,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.7),
                            shadows: const [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      if (year != null) ...[
                        Text(
                          year,
                          style: TextStyle(
                            fontSize: metaFontSize,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.7),
                            shadows: const [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: spacing),
                ],

                if (plot != null && plot.isNotEmpty) ...[
                  Text(
                    plot,
                    maxLines: isSmallScreen ? 4 : 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: plotFontSize,
                      color: Colors.white.withValues(alpha: 0.75),
                      height: 1.5,
                      shadows: const [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGestureHudOverlay() {
    if (!_showVolumeHud &&
        !_showBrightnessHud &&
        !_showLeftSeekRipple &&
        !_showRightSeekRipple) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // Left Double Tap Feedback (Rewind)
            if (_showLeftSeekRipple)
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.42,
                  heightFactor: 1.0,
                  child: DoubleTapSeekRippleOverlay(
                    key: const ValueKey('seek_left_overlay'),
                    isLeft: true,
                    seconds: _seekAccumulatedSeconds,
                    triggerKey: _seekAnimTriggerKey,
                  ),
                ),
              ),

            // Right Double Tap Feedback (Forward)
            if (_showRightSeekRipple)
              Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.42,
                  heightFactor: 1.0,
                  child: DoubleTapSeekRippleOverlay(
                    key: const ValueKey('seek_right_overlay'),
                    isLeft: false,
                    seconds: _seekAccumulatedSeconds,
                    triggerKey: _seekAnimTriggerKey,
                  ),
                ),
              ),

            // Brightness HUD (Left Side)
            if (_showBrightnessHud)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(left: 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _brightness > 0.6
                            ? Icons.brightness_7_rounded
                            : (_brightness > 0.3
                                  ? Icons.brightness_5_rounded
                                  : Icons.brightness_4_rounded),
                        color: const Color(0xFFFFB561),
                        size: 26,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 6,
                        height: 110,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: 6,
                          height: 110 * _brightness.clamp(0.01, 1.0),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFB561), Color(0xFFFF8C1A)],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${(_brightness * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Volume HUD (Right Side)
            if (_showVolumeHud)
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(right: 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _volume <= 0.001
                            ? Icons.volume_off_rounded
                            : (_volume < 0.5
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_up_rounded),
                        color: const Color(0xFFFFB561),
                        size: 26,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 6,
                        height: 110,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: 6,
                          height: 110 * _volume.clamp(0.0, 1.0),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFB561), Color(0xFFFF8C1A)],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${(_volume * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SideArcClipper extends CustomClipper<Path> {
  final bool isLeft;

  const _SideArcClipper({required this.isLeft});

  @override
  Path getClip(Size size) {
    final path = Path();
    if (isLeft) {
      // Left side: convex inward boundary arc
      path.moveTo(0, 0);
      path.lineTo(size.width * 0.40, 0);
      path.quadraticBezierTo(
        size.width,
        size.height / 2,
        size.width * 0.40,
        size.height,
      );
      path.lineTo(0, size.height);
      path.close();
    } else {
      // Right side: convex inward boundary arc
      path.moveTo(size.width, 0);
      path.lineTo(size.width * 0.60, 0);
      path.quadraticBezierTo(
        0,
        size.height / 2,
        size.width * 0.60,
        size.height,
      );
      path.lineTo(size.width, size.height);
      path.close();
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _SideArcClipper oldClipper) =>
      oldClipper.isLeft != isLeft;
}

class DoubleTapSeekRippleOverlay extends StatefulWidget {
  final bool isLeft;
  final int seconds;
  final int triggerKey;

  const DoubleTapSeekRippleOverlay({
    super.key,
    required this.isLeft,
    required this.seconds,
    required this.triggerKey,
  });

  @override
  State<DoubleTapSeekRippleOverlay> createState() =>
      _DoubleTapSeekRippleOverlayState();
}

class _DoubleTapSeekRippleOverlayState extends State<DoubleTapSeekRippleOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _waveController;
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.88,
          end: 1.14,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.14,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_scaleController);

    _scaleController.forward(from: 0.0);
  }

  @override
  void didUpdateWidget(covariant DoubleTapSeekRippleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.triggerKey != widget.triggerKey) {
      _scaleController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Widget _buildArrow(int index, double progress) {
    // 3 arrows staggered in progress: index 0, 1, 2
    final delay = index * 0.18;
    final shifted = progress - delay;
    final p = shifted < 0
        ? (shifted + 1.0)
        : (shifted > 1.0 ? shifted - 1.0 : shifted);

    final maxDx = widget.isLeft ? -14.0 : 14.0;
    double offset;
    double opacity;

    if (p < 0.5) {
      final t = Curves.easeOutBack.transform(p / 0.5);
      offset = t * maxDx;
      opacity = 0.25 + (t * 0.75); // 0.25 -> 1.0
    } else {
      final t = Curves.easeIn.transform((p - 0.5) / 0.5);
      offset = (1.0 - t) * maxDx;
      opacity = 1.0 - (t * 0.75); // 1.0 -> 0.25
    }

    return Transform.translate(
      offset: Offset(offset, 0),
      child: Opacity(
        opacity: opacity.clamp(0.2, 1.0),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _SideArcClipper(isLeft: widget.isLeft),
      child: Container(
        color: Colors.white.withValues(alpha: 0.12),
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_waveController, _scaleController]),
            builder: (context, child) {
              final progress = _waveController.value;

              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Rubber-band animated arrows (pure white)
                    Transform.rotate(
                      angle: widget.isLeft ? math.pi : 0.0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildArrow(0, progress),
                          const SizedBox(width: 2),
                          _buildArrow(1, progress),
                          const SizedBox(width: 2),
                          _buildArrow(2, progress),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Seconds label (pure white)
                    Text(
                      '${widget.seconds} seconds',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.3,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
