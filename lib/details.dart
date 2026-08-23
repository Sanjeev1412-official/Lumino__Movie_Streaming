// ignore_for_file: const_constructor_with_body, const_constructor_with_non_final_field, deprecated_member_use, duplicate_definition, empty_constructor_bodies, expected_class_member, missing_const_final_var_or_type, missing_function_body, must_be_immutable, prefer_typing_uninitialized_variables, strict_top_level_inference, unused_element, unused_field, unused_local_variable, unused_shown_name, use_build_context_synchronously, unused_element_parameter
// lib/details.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'
    show kDebugMode, defaultTargetPlatform, kIsWeb;
import 'package:lottie/lottie.dart';
import 'package:lumino_app_moviestreaming/Scrapper/voe.dart';
import 'package:lumino_app_moviestreaming/download_overlay.dart';
import 'package:lumino_app_moviestreaming/download_page.dart';
import 'package:lumino_app_moviestreaming/my_downloads_page.dart';
import 'package:lumino_app_moviestreaming/primebox_service.dart';
import 'package:lumino_app_moviestreaming/moviebox_service.dart';
import 'package:lumino_app_moviestreaming/network_service.dart';
import 'package:lumino_app_moviestreaming/sync_service.dart';
import 'package:lumino_app_moviestreaming/toast.dart';
import 'package:lumino_app_moviestreaming/trailers.dart';
import 'package:lumino_app_moviestreaming/videoplayer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:lumino_app_moviestreaming/watch_history_service.dart';
import 'package:lumino_app_moviestreaming/auth_service.dart';
import 'package:lumino_app_moviestreaming/login_page.dart';
import 'package:intl/intl.dart' hide TextDirection;


// ---------- Top-level models & helpers for sources from /extract ----------

class _SourceItem {
  final String url;
  final String
  provider; // 'FSL' | '10Gbps' | 'Pixeldrain' | 'CinemaOS' | 'LookMovie2' | 'Other'
  final String quality; // '2160p'...'360p' | 'auto'
  final String label;
  _SourceItem({
    required this.url,
    required this.provider,
    required this.quality,
    required this.label,
  });
}

/// Result from LookMovie2 /api/search
class _LookMovieSearchResult {
  final String url;
  final int? id;
  final String type; // 'Movie' | 'Show'
  final String title;
  _LookMovieSearchResult({
    required this.url,
    required this.id,
    required this.type,
    required this.title,
  });
}

class _PrimeboxStreamBundle {
  /// quality â†’ provider â†’ m3u8 url
  final Map<String, Map<String, String>> sources;

  /// sourceId (quality|provider) â†’ metadata (id, format, etc)
  final Map<String, dynamic> httpMetadata;

  /// language â†’ [subtitle_url, ...]
  final Map<String, List<String>> subtitles;

  final List<Map<String, dynamic>> dubs;

  _PrimeboxStreamBundle({
    required this.sources,
    required this.subtitles,
    this.httpMetadata = const {},
    this.dubs = const [],
  });
}

class _AppScrollBehavior extends ScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}

class DetailsPage extends StatefulWidget {
  final String apiKey;
  final String base; // TMDB API base
  final String imgW185;
  final String imgW500;
  final String imgW780;
  final int id;
  final String mediaType; // 'movie' | 'tv'
  final String
  linkApiBase; // 4KHDHub backend base, e.g. https://one0gbps-server-scrapper.onrender.com
  final String? primeboxUrl;
  final int? primeboxSubjectType;
  final String? primeboxType; // 'Movie' | 'Show'
  final String? initialTitle;
  final String? initialBackdrop;
  /// MovieBox subject ID — when set, use MovieBox /details and /links endpoints
  final String? movieboxSubjectId;

  const DetailsPage({
    super.key,
    required this.apiKey,
    required this.base,
    required this.imgW185,
    required this.imgW500,
    required this.imgW780,
    required this.id,
    required this.mediaType,
    required this.linkApiBase,
    this.primeboxUrl,
    this.primeboxSubjectType,
    this.primeboxType,
    this.initialTitle,
    this.initialBackdrop,
    this.movieboxSubjectId,
  });

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  final ScrollController _scrollController = ScrollController();
  WatchHistoryItem? _historyItem;

  bool _showBannerPlay = true;

  late Future<_DetailBundle?> _future;

  int? _selectedSeasonNumber;
  int _currentEpisodePage = 0;
  Future<_TvSeason?>? _seasonFuture;

  bool _busy = false;
  String _busyMsg = 'Loading...';
  final bool _networkToastShown = false;

  late StreamSubscription<bool> _netSub;
  late StreamSubscription<void> _syncSub;
  bool _isOnline = true;
  bool _contentNotFound = false;

  double? _imdbRating;
  Map<String, dynamic>? _lastPrimeboxData; // Cache for seasons/episodes
  MovieBoxDetails? _movieboxDetails; // Cache for MovieBox /details response
  final Map<int, List<_Episode>> _tmdbEpisodeCache = {};
  String? _logoUrl; // TMDB title logo URL
  String? _currentTitle;
  String? _currentBackdrop;

  final TextEditingController _episodeSearchController =
      TextEditingController();
  String _episodeSearchQuery = '';

  bool get _isDesktop {
    if (kIsWeb) {
      return MediaQuery.of(context).size.width > 800;
    }
    try {
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  late final FocusNode _keyboardFocusNode;

  // -------------------- INIT --------------------
  @override
  void initState() {
    super.initState();
    _currentTitle = widget.initialTitle;
    _currentBackdrop = widget.initialBackdrop;

    _scrollController.addListener(() {
      final atTop = _scrollController.position.pixels <= 1;
      if (atTop != _showBannerPlay) {
        setState(() => _showBannerPlay = atTop);
      }
    });

    _isOnline = true;
    _netSub = NetworkService().onStatusChange.listen((online) {
      if (!mounted) return;
      setState(() => _isOnline = online);
    });
    _syncSub = SyncService.onSyncNotify.stream.listen((_) => _loadHistory());
    _future = _fetchBundle();
    _loadHistory();

    // Trigger logo fetch immediately if it's a standard TMDB navigation
    // This allows it to load in parallel with the main details fetch
    if (widget.movieboxSubjectId == null &&
        (widget.primeboxUrl == null || widget.primeboxUrl!.isEmpty)) {
      _fetchTmdbLogo(widget.id, widget.mediaType);
    }

    //focus node for keyboard events
    _keyboardFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });
  }

  Future<void> _loadHistory({int? currentId}) async {
    final idToUse = (currentId ?? widget.id);
    final history = await WatchHistoryService.getProgress(
      widget.mediaType,
      idToUse != 0 ? idToUse : widget.primeboxUrl ?? '',
    );
    if (mounted) {
      setState(() {
        _historyItem = history;
      });
    }
  }

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

  Future<int?> _findTmdbId(String title, String type, String? year) async {
    try {
      final a = widget.apiKey;
      final b = widget.base;

      final cleanedTitle = _cleanTitle(title).toLowerCase();
      final searchYearStr = (year != null && year.length >= 4)
          ? year.substring(0, 4)
          : null;
      final searchYear = int.tryParse(searchYearStr ?? '');

      if (kDebugMode) {
        debugPrint(
          'Cross-checking TMDB for: "$cleanedTitle" (${searchYear ?? "No Year"})',
        );
      }

      // Search without strict year filter first to get candidates
      final query = Uri.encodeComponent(cleanedTitle);
      final url = '$b/search/$type?api_key=$a&query=$query';

      final res = await _safeGet(Uri.parse(url));
      if (res == null || res.statusCode != 200) return null;

      final json = jsonDecode(res.body);
      final results = json['results'] as List?;
      if (results == null || results.isEmpty) return null;

      for (final item in results) {
        final rawResultTitle = (item['title'] ?? item['name'] ?? '').toString();
        final cleanedResultTitle = _cleanTitle(rawResultTitle).toLowerCase();

        final resultDate =
            (item['release_date'] ?? item['first_air_date'] ?? '').toString();
        final resultYearStr = resultDate.length >= 4
            ? resultDate.substring(0, 4)
            : null;
        final resultYear = int.tryParse(resultYearStr ?? '');

        // Match Strategy:
        // 1. Title Match (Exact or very similar)
        bool exactMatch = (cleanedResultTitle == cleanedTitle);
        bool partialMatch =
            (cleanedResultTitle.contains(cleanedTitle) &&
                cleanedTitle.length > 3) ||
            (cleanedTitle.contains(cleanedResultTitle) &&
                cleanedResultTitle.length > 3);

        if (!exactMatch && !partialMatch) continue;

        // 2. Year Check
        bool yearMatch = false;
        if (searchYear == null || resultYear == null) {
          yearMatch = true; // Can't verify, so we assume title match is enough
        } else {
          final diff = (searchYear - resultYear).abs();
          // Relax year check for TV shows (Primebox often shows the LATEST season year, TMDB shows START year)
          if (type == 'tv') {
            yearMatch = diff <= 8; // Very lenient for shows
          } else {
            yearMatch = diff <= 2; // Slightly more lenient for movies
          }
        }

        if (exactMatch && yearMatch) {
          if (kDebugMode) {
            debugPrint(
              'Found exact TMDB match: $rawResultTitle ($resultYearStr)',
            );
          }
          return item['id'];
        }

        // If it's a partial match and the title is long enough, we can still accept it if the year is close
        if (partialMatch && yearMatch) {
          if (kDebugMode) {
            debugPrint(
              'Found partial TMDB match: $rawResultTitle ($resultYearStr)',
            );
          }
          return item['id'];
        }
      }

      if (kDebugMode) {
        debugPrint(
          'No strong TMDB match found for "$title". Sticking to Primebox data.',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB matching error: $e');
    }
    return null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _netSub.cancel();
    _syncSub.cancel();
    //focus node dispose
    _keyboardFocusNode.dispose();
    _episodeSearchController.dispose();
    // No torrent stream is started from here anymore; VideoPlayerScreen will handle /start & /stop.
    super.dispose();
  }

  /// NEW: Fetch direct video links from World4uFree (m3u8 or mp4)
  Future<Map<String, Map<String, String>>> _fetchWorld4uFreeSources({
    required _Details d,
  }) async {
    try {
      final title = d.displayTitle;
      if (kDebugMode) debugPrint('World4uFree searching for: "$title"');

      final links = await World4uFreeService.getMovieLinks(title);

      if (links.isEmpty) {
        if (kDebugMode) debugPrint('World4uFree: no links found');
        return <String, Map<String, String>>{};
      }

      final map = <String, Map<String, String>>{};

      links.forEach((quality, url) {
        // World4uFree usually gives high-quality streams â†’ label as "World4uFree"
        final standardizedQuality = _standardizeQualityKey(quality);

        map.putIfAbsent(standardizedQuality, () => <String, String>{});
        map[standardizedQuality]!['World4uFree'] = url;
      });

      if (kDebugMode) {
        debugPrint('World4uFree final sources: $map');
      }

      return map;
    } catch (e, st) {
      if (kDebugMode) debugPrint('World4uFree error: $e\n$st');
      return <String, Map<String, String>>{};
    }
  }

  String _standardizeQualityKey(String quality) {
    return quality
        .toLowerCase()
        .replaceAll(' ', '') // remove any spaces
        .replaceAll('4k', '2160p')
        .replaceAll('2k', '1440p')
        .replaceAll('fhd', '1080p')
        .replaceAll('hd', '720p');
  }

  Future<void> _fetchImdbRating(_Details details) async {
    if (_imdbRating != null && _imdbRating! > 0) return;
    final imdbId = details.imdbId;
    if (imdbId == null || imdbId.isEmpty) return;

    // IMPORTANT: use widget.mediaType from TMDB, not "series"/"movie" from player
    final typePath = widget.mediaType == 'movie' ? 'movies' : 'tv';

    final uri = Uri.parse(
      'https://api.simkl.com/$typePath/$imdbId'
      '?extended=full&client_id=c024bfad7cd0fb2e96ee39bde85e7ae1c3449defe5a6832338fb5ba9adcc139f', // put your real client_id
    );

    if (kDebugMode) {
      debugPrint('SIMKL rating GET: $uri');
    }

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 6));

      // 404: Simkl doesn't know this ID â†’ just ignore
      if (res.statusCode == 404) {
        if (kDebugMode) {
          debugPrint('SIMKL: no entry for $imdbId (type=$typePath)');
        }
        return;
      }

      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('SIMKL rating error: ${res.statusCode} ${res.body}');
        }
        return;
      }

      final j = json.decode(res.body) as Map<String, dynamic>;
      final ratings = j['ratings'] as Map<String, dynamic>?;
      final imdb = ratings?['imdb'] as Map<String, dynamic>?;
      final ratingVal = imdb?['rating'];

      if (ratingVal is num && mounted) {
        setState(() {
          _imdbRating = ratingVal.toDouble();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SIMKL rating exception: $e');
      }
    }
  }

  Future<void> _fetchTmdbLogo(int tmdbId, String mediaType) async {
    try {
      final uri = Uri.parse(
        '${widget.base}/$mediaType/$tmdbId/images?api_key=${widget.apiKey}&include_image_language=en,null',
      );
      final res = await _safeGet(uri);
      if (res == null || res.statusCode != 200) return;
      final j = json.decode(res.body);
      final logos = (j['logos'] as List?) ?? [];
      // Pick the best English logo (highest vote average with en language)
      final enLogos = logos.where((l) => l['iso_639_1'] == 'en').toList();
      final best = enLogos.isNotEmpty
          ? enLogos.first
          : (logos.isNotEmpty ? logos.first : null);
      if (best != null && mounted) {
        final url = 'https://image.tmdb.org/t/p/w500${best['file_path']}';

        // Await the actual image loading into memory
        try {
          await precacheImage(NetworkImage(url), context);
        } catch (e) {
          if (kDebugMode) debugPrint('Logo precache error: $e');
        }

        if (mounted) {
          setState(() {
            _logoUrl = url;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Logo fetch error: $e');
    }
  }

  void _setBusy(bool v, [String? msg]) {
    if (!mounted) return;
    setState(() {
      _busy = v;
      if (msg != null) _busyMsg = msg;
    });
  }

  Future<_DetailBundle?> _fetchBundle() async {
    // ── MovieBox path ──────────────────────────────────────────────────────────
    if (widget.movieboxSubjectId != null && widget.movieboxSubjectId!.isNotEmpty) {
      if (kDebugMode) debugPrint('[MovieBox] Fetching details for ${widget.movieboxSubjectId}');
      try {
        final mb = await MovieBoxService.getDetails(widget.movieboxSubjectId!);
        if (mb != null) {
          _movieboxDetails = mb;

          // Set logo from MovieBox directly (no TMDB call needed)
          if (mb.logo != null && mb.logo!.isNotEmpty && mounted) {
            try { await precacheImage(NetworkImage(mb.logo!), context); } catch (_) {}
            if (mounted) setState(() => _logoUrl = mb.logo);
          }

          // Also try TMDB logo if tmdbId available
          if (mb.tmdbId != null && mb.tmdbId! > 0) {
            final tmdbType = mb.isMovie ? 'movie' : 'tv';
            _fetchTmdbLogo(mb.tmdbId!, tmdbType);
          }

          // Parse IMDB rating
          final ratingVal = double.tryParse(mb.rating ?? '');
          if (ratingVal != null && ratingVal > 0 && mounted) {
            setState(() => _imdbRating = ratingVal);
          }

          // Build season stubs from episodes
          final seasonStubs = <_SeasonStub>[];
          if (!mb.isMovie) {
            final seasonNums = mb.episodes.map((e) => e.season).toSet().toList()..sort();
            for (final sn in seasonNums) {
              final epCount = mb.episodes.where((e) => e.season == sn).length;
              seasonStubs.add(_SeasonStub(
                seasonNumber: sn,
                name: 'Season $sn',
                episodeCount: epCount,
              ));
            }
          }

          // Set initial season
          if (!mb.isMovie && seasonStubs.isNotEmpty) {
            _selectedSeasonNumber = seasonStubs.first.seasonNumber;
            // Build season from MovieBox episodes
            _seasonFuture = _fetchMovieBoxSeason(_selectedSeasonNumber!);
          }

          final details = _Details(
            id: mb.tmdbId ?? 0,
            title: mb.title,
            posterPath: mb.poster,
            backdropPath: mb.background ?? mb.poster,
            overview: mb.plot ?? '',
            voteAverage: ratingVal ?? 0.0,
            genres: mb.genre,
            runtime: mb.duration ?? 0,
            seasons: seasonStubs,
            firstAirDate: mb.isMovie ? null : (mb.year != null ? '${mb.year}-01-01' : null),
            releaseDate: mb.isMovie ? (mb.year != null ? '${mb.year}-01-01' : null) : null,
            videos: [],
            imdbId: mb.imdbId,
            trailerUrl: null,
            originalLanguage: 'en',
            status: mb.airingStatus,
            nextAirDate: mb.nextEpisode?.airDate,
            nextEpisodeSeason: mb.nextEpisode?.season,
            nextEpisodeNumber: mb.nextEpisode?.episode,
            lastAirDate: mb.lastEpisode?.airDate,
            lastEpisodeSeason: mb.lastEpisode?.season,
            lastEpisodeNumber: mb.lastEpisode?.episode,
            totalSeasons: mb.totalSeasons,
            totalEpisodes: mb.totalEpisodes,
            inProduction: mb.inProduction,
          );

          final credits = _Credits(
            cast: mb.actors.map((a) => _Person(
              id: 0,
              name: a['name']?.toString() ?? '',
              profilePath: a['avatar']?.toString(),
              role: a['character']?.toString(),
            )).toList(),
            directors: [],
            writers: [],
          );

          // Load history with MovieBox subject id as a string key
          _loadHistory(currentId: mb.tmdbId ?? 0);

          return _DetailBundle(details: details, credits: credits);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[MovieBox] _fetchBundle error: $e');
      }
      // Fallthrough to TMDB if MovieBox fails
    }

    if (widget.primeboxUrl != null &&
        widget.primeboxUrl!.isNotEmpty) {
      String path = widget.primeboxUrl!;
      if (path.contains('detailPath=')) {
        path = path.split('detailPath=').last;
      } else if (path.contains('/detail/')) {
        path = path.split('/detail/').last;
      }

      final uri = Uri.parse(
        'https://hqkkwzafev6lvngmejpksui3mi0bbnoj.lambda-url.ap-south-1.on.aws/detail?detailPath=$path',
      );
      if (kDebugMode) debugPrint('Primebox Bundle GET: $uri');

      try {
        final res = await _safeGet(
          uri,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        );

        if (res != null && res.statusCode == 200) {
          final body = json.decode(res.body);
          if (body['data'] == null &&
              (body['code'] == -1 ||
                  body['message']?.contains('Failed') == true)) {
            if (mounted) setState(() => _contentNotFound = true);
            return null;
          }
          final data = body['data'];
          if (data != null) {
            _lastPrimeboxData = data; // Cache for _fetchSeason
            final subject = data['subject'] ?? {};
            final resource = data['resource'] ?? {};

            final isMovie = subject['subjectType'] == 1;

            final seasonsList = <_SeasonStub>[];
            if (!isMovie && resource['seasons'] != null) {
              for (final s in resource['seasons']) {
                seasonsList.add(
                  _SeasonStub(
                    seasonNumber: s['se'],
                    name: 'Season ${s['se']}',
                    episodeCount: s['maxEp'],
                  ),
                );
              }
            }

            final genresStr = subject['genre'] as String?;
            final genresList =
                genresStr?.split(',').map((e) => e.trim()).toList() ?? [];

            final primeboxRating = double.tryParse(
              subject['imdbRatingValue']?.toString() ??
                  subject['imdbRate']?.toString() ??
                  '',
            );
            if (primeboxRating != null && primeboxRating > 0) {
              _imdbRating = primeboxRating;
            }

            var details = _Details(
              id: 0,
              title: subject['title'] ?? 'Unknown',
              posterPath: subject['cover']?['url'],
              backdropPath: subject['backdrop']?['url'],
              overview: subject['description'] ?? '',
              voteAverage: primeboxRating ?? 0.0,
              genres: genresList,
              runtime: subject['duration'] ?? 0,
              seasons: seasonsList,
              firstAirDate: isMovie ? null : subject['releaseDate'],
              releaseDate: isMovie ? subject['releaseDate'] : null,
              videos: [],
              imdbId: null,
              trailerUrl:
                  subject['trailer']?['videoAddress']?['url'] as String?,
              originalLanguage: 'en', // default for primebox
              status: null,
              nextAirDate: null,
              nextEpisodeSeason: null,
              nextEpisodeNumber: null,
            );
            var credits = _Credits(cast: [], directors: [], writers: []);

            // Parallel enrichment: TMDB search + IMDb rating
            // Wrap in try-catch to ensure Primebox data is shown even if TMDB/SIMKL fail
            try {
              final futures = <Future>[];

              int? tmdbId;
              futures.add(() async {
                try {
                  tmdbId = await _findTmdbId(
                    details.title,
                    isMovie ? 'movie' : 'tv',
                    details.year,
                  );
                  if (tmdbId != null) {
                    if (kDebugMode) {
                      debugPrint(
                        'TMDB ID found: $tmdbId. Fetching extra metadata...',
                      );
                    }
                    final tmdbRes = await _safeGet(
                      Uri.parse(
                        '${widget.base}/${isMovie ? 'movie' : 'tv'}/$tmdbId?api_key=${widget.apiKey}&append_to_response=credits,images,${isMovie ? 'release_dates' : 'content_ratings'}',
                      ),
                    );
                    if (tmdbRes != null && tmdbRes.statusCode == 200) {
                      final tmdbJson = json.decode(tmdbRes.body);

                      final tmdbGenres = ((tmdbJson['genres'] as List?) ?? [])
                          .map((g) => g['name']?.toString() ?? '')
                          .where((s) => s.isNotEmpty)
                          .toList();

                      details = details.copyWith(
                        id: tmdbId!,
                        overview:
                            tmdbJson['overview'] != null &&
                                tmdbJson['overview'].isNotEmpty
                            ? tmdbJson['overview']
                            : details.overview,
                        voteAverage:
                            tmdbJson['vote_average']?.toDouble() ??
                            details.voteAverage,
                        imdbId: tmdbJson['imdb_id'],
                        posterPath:
                            tmdbJson['poster_path'] ?? details.posterPath,
                        backdropPath:
                            tmdbJson['backdrop_path'] ?? details.backdropPath,
                        genres: tmdbGenres.isNotEmpty
                            ? tmdbGenres
                            : details.genres,
                        runtime: tmdbJson['runtime'] ?? details.runtime,
                        contentRating: _Details._parseRating(
                          tmdbJson,
                          isMovie ? 'movie' : 'tv',
                        ),
                        originalLanguage: tmdbJson['original_language'],
                        status: tmdbJson['status'],
                        nextAirDate:
                            tmdbJson['next_episode_to_air']?['air_date'],
                        nextEpisodeSeason:
                            tmdbJson['next_episode_to_air']?['season_number'],
                        nextEpisodeNumber:
                            tmdbJson['next_episode_to_air']?['episode_number'],
                      );
                      if (tmdbJson['credits'] != null) {
                        credits = _Credits.fromJson(tmdbJson['credits']);
                      }
                    }
                  }
                } catch (e) {
                  if (kDebugMode) debugPrint('TMDB Enrichment inner error: $e');
                }
              }());

              futures.add(
                _fetchImdbRating(details).catchError((e) {
                  if (kDebugMode) debugPrint('SIMKL error: $e');
                }),
              );

              await Future.wait(
                futures,
              ).timeout(const Duration(seconds: 15), onTimeout: () => []);
            } catch (e) {
              if (kDebugMode) debugPrint('TMDB Enrichment outer error: $e');
            }

            // Fetch logo after TMDB ID is found and AWAIT it
            if (details.id != 0) {
              await _fetchTmdbLogo(details.id, isMovie ? 'movie' : 'tv');
            }

            // RE-LOAD HISTORY if we found a new ID
            if (details.id != 0) {
              _loadHistory(currentId: details.id);
            }

            if (!isMovie && details.seasons.isNotEmpty) {
              _selectedSeasonNumber = details.seasons.first.seasonNumber;
              _seasonFuture = _fetchSeason(details.id, _selectedSeasonNumber!);
            }

            return _DetailBundle(details: details, credits: credits);
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Primebox detail fetch error: $e');
      }
    }

    final a = widget.apiKey;
    final b = widget.base;
    final id = widget.id;

    if (id == 0) {
      // Fallback for when TMDB ID could not be resolved
      final details = _Details(
        id: 0,
        title: widget.initialTitle ?? 'Unknown',
        posterPath: widget.initialBackdrop,
        backdropPath: widget.initialBackdrop,
        overview:
            'Metadata could not be fetched. You can still try to play the movie.',
        voteAverage: 0,
        genres: [],
        runtime: 0,
        seasons: [],
        videos: [],
        imdbId: null,
        originalLanguage: 'en',
      );
      return _DetailBundle(
        details: details,
        credits: _Credits(cast: [], directors: [], writers: []),
      );
    }

    final detailUri = Uri.parse(
      '$b/${widget.mediaType}/$id?api_key=$a&append_to_response=videos,watch/providers,external_ids,images,${widget.mediaType == 'movie' ? 'release_dates' : 'content_ratings'}',
    );

    final creditsUri = Uri.parse(
      '$b/${widget.mediaType}/$id/credits?api_key=$a',
    );

    // Parallel, resilient network calls
    final results = await Future.wait([
      _safeGet(detailUri),
      _safeGet(creditsUri),
    ]);
    final detailRes = results[0];
    final creditsRes = results[1];

    // Any failure â†’ null â†’ UI shows No Network or Retry screen
    if (detailRes == null || creditsRes == null) return null;

    try {
      final detailsJson = json.decode(detailRes.body);
      final creditsJson = json.decode(creditsRes.body);
      final details = _Details.fromJson(
        detailsJson as Map<String, dynamic>,
        widget.mediaType,
      );
      final credits = _Credits.fromJson(creditsJson as Map<String, dynamic>);

      // Kick off IMDb rating fetch
      _fetchImdbRating(details);

      // Await title logo AND its image loading
      await _fetchTmdbLogo(details.id, widget.mediaType);

      // Precache Backdrop too for a perfect reveal
      if (details.backdropPath != null) {
        final bgUrl = details.backdropPath!.startsWith('http')
            ? details.backdropPath!
            : 'https://image.tmdb.org/t/p/w1280${details.backdropPath}';
        try {
          await precacheImage(NetworkImage(bgUrl), context);
        } catch (_) {}
      }

      if (widget.mediaType == 'tv' && details.seasons.isNotEmpty) {
        _selectedSeasonNumber = details.seasons.first.seasonNumber;
        _seasonFuture = _fetchSeason(details.id, _selectedSeasonNumber!);
      }

      return _DetailBundle(details: details, credits: credits);
    } catch (_) {
      return null;
    }
  }

  /// Build a [_TvSeason] from the already-fetched MovieBox details episodes.
  Future<_TvSeason?> _fetchMovieBoxSeason(int seasonNumber) async {
    final mb = _movieboxDetails;
    if (mb == null) return null;
    final eps = mb.episodes.where((e) => e.season == seasonNumber).toList()
      ..sort((a, b) => a.episode.compareTo(b.episode));
    if (eps.isEmpty) return null;
    return _TvSeason(
      seasonNumber: seasonNumber,
      episodes: eps.map((e) => _Episode(
        episodeNumber: e.episode,
        name: e.title,
        overview: e.description ?? '',
        runtime: e.runtime ?? 0,
        stillPath: e.thumbnail,
      )).toList(),
    );
  }

  Future<_TvSeason?> _fetchSeason(int tvId, int seasonNumber) async {
    // If we have MovieBox data, use it instead of TMDB/Primebox
    if (widget.movieboxSubjectId != null && _movieboxDetails != null) {
      return _fetchMovieBoxSeason(seasonNumber);
    }
    if (widget.primeboxUrl != null && widget.primeboxUrl!.isNotEmpty) {
      try {
        Map<String, dynamic>? data = _lastPrimeboxData;

        // If no cache, fetch it
        if (data == null) {
          String path = widget.primeboxUrl!;
          if (path.contains('detailPath=')) {
            path = path.split('detailPath=').last;
          } else if (path.contains('/detail/')) {
            path = path.split('/detail/').last;
          }

          final uri = Uri.parse(
            'https://hqkkwzafev6lvngmejpksui3mi0bbnoj.lambda-url.ap-south-1.on.aws/detail?detailPath=$path',
          );
          final res = await _safeGet(
            uri,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          );
          if (res != null && res.statusCode == 200) {
            data = json.decode(res.body)['data'];
            _lastPrimeboxData = data;
          }
        }

        if (data != null) {
          final resource = data['resource'] ?? {};
          if (resource['seasons'] != null) {
            for (final s in resource['seasons']) {
              if (s['se'] == seasonNumber) {
                int maxEp = s['maxEp'] ?? 1;

                // Fetch all TMDB episodes once for this show to handle absolute numbering enrichment
                List<_Episode>? allTmdbEpisodes;
                if (tvId != 0) {
                  allTmdbEpisodes = await _fetchAllTmdbEpisodes(tvId);
                }

                int offset = 0;
                final pbSeasons = resource['seasons'] as List;
                for (final ps in pbSeasons) {
                  if ((ps['se'] ?? 0) < seasonNumber) {
                    offset += (ps['maxEp'] as int? ?? 0);
                  }
                }

                final eps = List.generate(maxEp, (index) {
                  final epNum = index + 1;
                  _Episode? tmdbEp;
                  if (allTmdbEpisodes != null) {
                    final absIndex = offset + index;
                    if (absIndex >= 0 && absIndex < allTmdbEpisodes.length) {
                      tmdbEp = allTmdbEpisodes[absIndex];
                    }
                  }

                  return _Episode(
                    episodeNumber: epNum,
                    name: tmdbEp?.name ?? 'Episode $epNum',
                    overview: tmdbEp?.overview ?? '',
                    runtime: tmdbEp?.runtime ?? 0,
                    stillPath: tmdbEp?.stillPath,
                  );
                });
                return _TvSeason(seasonNumber: seasonNumber, episodes: eps);
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Primebox season fetch error: $e');
      }
      return null;
    }

    // Use base if you want, but construct URI properly.
    final uri = Uri.https('api.tmdb.org', '/3/tv/$tvId/season/$seasonNumber', {
      'api_key': widget.apiKey,
      'language': 'en-US',
    });

    if (kDebugMode) {
      debugPrint('TMDB season GET: $uri');
    }

    try {
      // Give it a realistic timeout
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            'TMDB season load failed [${res.statusCode}]: ${res.body}',
          );
        }
        return null;
      }

      final Map<String, dynamic> data =
          json.decode(res.body) as Map<String, dynamic>;
      return _TvSeason.fromJson(data);
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        debugPrint('TMDB season timeout for tvId=$tvId S$seasonNumber: $e');
      }
      return null;
    } on SocketException catch (e) {
      if (kDebugMode) {
        debugPrint('TMDB season network error: $e');
      }
      return null;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('TMDB season unknown error: $e\n$st');
      }
      return null;
    }
  }

  /// Fetches all episodes from all seasons of a TMDB TV show and flattens them.
  /// Used for enriching providers that use absolute numbering or different seasoning.
  Future<List<_Episode>> _fetchAllTmdbEpisodes(int tvId) async {
    if (_tmdbEpisodeCache.containsKey(tvId)) {
      return _tmdbEpisodeCache[tvId]!;
    }

    try {
      // 1. Get show details to find all regular seasons
      final showUri = Uri.https('api.tmdb.org', '/3/tv/$tvId', {
        'api_key': widget.apiKey,
        'language': 'en-US',
      });
      final showRes = await _safeGet(showUri);
      if (showRes == null || showRes.statusCode != 200) return [];

      final showJson = json.decode(showRes.body);
      final seasons = (showJson['seasons'] as List?) ?? [];

      // 2. Fetch all regular seasons in parallel (exclude Season 0/Specials)
      final seasonNumbers = seasons
          .map((s) => s['season_number'] as int?)
          .where((sn) => sn != null && sn > 0)
          .toList();

      // Sort season numbers to ensure correct flattening order
      seasonNumbers.sort();

      final seasonFutures = seasonNumbers.map((sn) {
        return _safeGet(
          Uri.https('api.tmdb.org', '/3/tv/$tvId/season/$sn', {
            'api_key': widget.apiKey,
            'language': 'en-US',
          }),
        );
      }).toList();

      final seasonResponses = await Future.wait(seasonFutures);

      final List<_Episode> allEpisodes = [];
      for (var res in seasonResponses) {
        if (res != null && res.statusCode == 200) {
          final sJson = json.decode(res.body);
          final eps = ((sJson['episodes'] as List?) ?? [])
              .map((e) => _Episode.fromJson(e as Map<String, dynamic>))
              .toList();
          allEpisodes.addAll(eps);
        }
      }

      if (allEpisodes.isNotEmpty) {
        _tmdbEpisodeCache[tvId] = allEpisodes;
      }
      return allEpisodes;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching all TMDB episodes for $tvId: $e');
      }
      return [];
    }
  }

  void _onSeasonChanged(int sn, _Details d) {
    setState(() {
      _selectedSeasonNumber = sn;
      _currentEpisodePage = 0;
      _seasonFuture = _fetchSeason(d.id, sn);
    });
  }

  // =============== Link collection: quality -> provider -> url ===============
  final String _fallbackQuality = '1080p';
  final List<String> _qOrder = const [
    '4K',
    '2160p',
    '1440p',
    '1080p',
    '720p',
    '480p',
    '360p',
  ];

  int _qualIndex(String q) {
    final i = _qOrder.indexOf(q);
    return i < 0 ? 999 : i;
  }

  // --- URL/Provider/Quality helpers (use /extract structured fields first) ---
  String _normalizeUrl(String u) {
    var url = u.trim();
    if (url.startsWith('//')) url = 'https:$url';
    return url;
  }

  bool _allowedPlayableUrl(String u) {
    final lu = u.toLowerCase();
    if (lu.endsWith('.zip') ||
        lu.contains('.mkv.zip') ||
        lu.contains('.zip?')) {
      return false;
    }
    return true;
  }

  String _rewritePixeldrainIfNeeded(String u) {
    final input = _normalizeUrl(u);
    final lu = input.toLowerCase();
    if (!lu.contains('pixeldrain')) return input;
    try {
      final uri = Uri.parse(input);
      final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
      final host = uri.host.isEmpty ? 'pixeldrain.dev' : uri.host;
      final path = uri.path;

      final m = RegExp(r'^/u/([^/?#]+)').firstMatch(path);
      if (m != null) {
        final id = m.group(1)!;
        return '$scheme://$host/api/file/$id?download';
      }
      final m2 = RegExp(r'^/api/file/([^/?#]+)').firstMatch(path);
      if (m2 != null) {
        final id = m2.group(1)!;
        return '$scheme://$host/api/file/$id?download';
      }
    } catch (_) {}
    return input;
  }

  String _normalizeProvider(String? serverOrLabelOrUrl) {
    final t = (serverOrLabelOrUrl ?? '').toLowerCase();
    if (t.contains('10gbps')) return '10Gbps';
    if (t.contains('fsl')) return 'FSL';
    if (t.contains('cinemaos')) return 'CinemaOS';
    if (t.contains('pixeldrain') ||
        t.contains('pixel drain') ||
        t.contains('pd')) {
      return 'Pixeldrain';
    }
    return 'Other';
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

  String _normalizeQuality(dynamic qualityField, String fallbackText) {
    if (qualityField is int) return '${qualityField}p';

    if (qualityField is String && qualityField.trim().isNotEmpty) {
      final v = qualityField.toLowerCase();

      // CinemaOS (and others): "FHD" / "Full HD" â†’ 1080p
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

  String _cleanProviderLabel(String rawProvider) {
    final lower = rawProvider.toLowerCase().trim();
    if (lower == 'filmyfly') return 'Beta Server';
    if (lower == 'lookmovie') return 'Gamma Server';
    if (lower == 'lookmovie2') return 'Gamma 2 Server';
    if (lower == 'aoneroom') return 'Delta Server';
    if (lower == 'direct') return 'Direct Server';
    if (lower == 'torrent' || lower.contains('torrent') || lower.contains('p2p')) return 'P2P Server';
    if (lower == 'cinemaos') return 'Epsilon Server';

    return 'Alpha Server';
  }

  dynamic _safeJson(String body) {
    try {
      return json.decode(body);
    } catch (_) {
      return body;
    }
  }

  String? _firstUrlFromSearch(dynamic sJson) {
    if (sJson is Map) {
      final all = _collectStringsByKey(sJson, 'url');
      if (all.isNotEmpty) return all.first;
    }
    if (sJson is List) {
      for (final e in sJson) {
        final u = _firstUrlFromSearch(e);
        if (u != null) return u;
      }
    }
    final any = _collectStrings(
      sJson,
    ).firstWhere((s) => s.startsWith('http'), orElse: () => '');
    return any.isEmpty ? null : any;
  }

  List<String> _collectStringsByKey(dynamic jsonObj, String key) {
    final out = <String>[];
    void walk(dynamic v) {
      if (v is Map) {
        v.forEach((k, val) {
          if (k.toString().toLowerCase() == key && val is String) {
            out.add(val);
          }
          walk(val);
        });
      } else if (v is List) {
        for (final e in v) {
          walk(e);
        }
      }
    }

    walk(jsonObj);
    return out;
  }

  List<String> _collectStrings(dynamic jsonObj) {
    final out = <String>[];
    void walk(dynamic v) {
      if (v is String) {
        out.add(v);
      } else if (v is Map) {
        v.values.forEach(walk);
      } else if (v is List) {
        v.forEach(walk);
      }
    }

    walk(jsonObj);
    return out;
  }

  // ---------- Collectors that USE structured /extract fields ----------
  List<_SourceItem> _collectSourceItems(dynamic jsonObj) {
    final out = <_SourceItem>[];

    void walk(dynamic v) {
      if (v is Map) {
        final m = v.map((k, val) => MapEntry(k.toString().toLowerCase(), val));

        // Respect structured fields from /extract
        final rawUrl =
            ([m['url'], m['link'], m['play'], m['src'], m['file']].firstWhere(
                  (e) =>
                      e is String &&
                      (e.startsWith('http') || e.startsWith('//')),
                  orElse: () => null,
                )
                as String?);

        if (rawUrl != null) {
          final normalized = _rewritePixeldrainIfNeeded(_normalizeUrl(rawUrl));
          if (_allowedPlayableUrl(normalized)) {
            final server =
                (m['server'] ??
                        m['host'] ??
                        m['provider'] ??
                        m['label'] ??
                        m['title'])
                    ?.toString();
            final label = (m['label'] ?? m['title'] ?? m['name'] ?? '')
                .toString();
            final quality = _normalizeQuality(
              m['quality'],
              '$label $normalized',
            );
            final provider = _normalizeProvider('$server $label $normalized');

            out.add(
              _SourceItem(
                url: normalized,
                provider: provider,
                quality: quality,
                label: label,
              ),
            );
          }
        }

        for (final val in m.values) {
          walk(val);
        }
      } else if (v is List) {
        for (final e in v) {
          walk(e);
        }
      }
    }

    walk(jsonObj);
    return out;
  }

  Future<void> _openDownloadSheet({
    required _Details d,
    required String mediaType, // 'movie' or 'series'
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
  }) async {
    final ctx = context;

    if (!AuthService().isLoggedIn) {
      Navigator.push(ctx, MaterialPageRoute(builder: (_) => const LoginPage()));
      AppToast.show(ctx, 'Please login to download', icon: Icons.login_rounded);
      return;
    }

    WakelockPlus.enable();
    _setBusy(true, 'Finding download linksâ€¦');

    _PrimeboxStreamBundle? bundle;

    try {
      bundle = await _resolveSources(
        query: d.displayTitle,
        season: mediaType == 'series' ? seasonNumber : null,
        episode: mediaType == 'series' ? episodeNumber : null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Download resolve error: $e');
    } finally {
      WakelockPlus.disable();
      _setBusy(false);
    }

    if (!mounted || bundle == null) return;

    // Handle Dub Selection if multiple dubs exist
    if (bundle.dubs.length > 1) {
      final selectedDub = await _showDubSelectionSheet(ctx, bundle.dubs);
      if (selectedDub != null) {
        _setBusy(true, 'Fetching ${selectedDub['lanName']} sourcesâ€¦');
        try {
          bundle = await _resolveSources(
            query: d.displayTitle,
            season: mediaType == 'series' ? seasonNumber : null,
            episode: mediaType == 'series' ? episodeNumber : null,
            subjectId: int.tryParse(selectedDub['subjectId']?.toString() ?? ''),
          );
        } catch (e) {
          if (kDebugMode) debugPrint('Dub source resolve error: $e');
        } finally {
          _setBusy(false);
        }
      }
    }

    if (!mounted || bundle == null || bundle.sources.isEmpty) {
      AppToast.show(
        ctx,
        'No direct download links found.',
        icon: Icons.error_rounded,
        tag: 'Download',
      );
      return;
    }

    final httpSources = bundle.sources;

    // Flatten Map<quality, Map<provider, url>> -> List<DownloadItem>
    final items = <DownloadItem>[];
    httpSources.forEach((quality, providers) {
      providers.forEach((provider, url) {
        final name = '$quality • ${_cleanProviderLabel(provider)}';

        // Pass headers for Primebox/Netfilm sources to avoid 403 Access Denied
        Map<String, String>? headers;
        
        // 1. Try to get dynamic headers from MovieBox httpMetadata
        final sourceId = 'http|$quality|$provider';
        if (bundle!.httpMetadata.containsKey(sourceId)) {
          final metaHeaders = bundle.httpMetadata[sourceId]['headers'];
          if (metaHeaders is Map) {
            headers = metaHeaders.map((k, v) => MapEntry(k.toString(), v.toString()));
          }
        }

        // 2. Fallback to hardcoded headers
        if (headers == null && (provider.toLowerCase().contains('primebox') ||
            url.contains('aoneroom.com') ||
            url.contains('netfilm.world') ||
            url.contains('fmoviesunblocked.net'))) {
          String referer = 'https://netfilm.world/';
          if (url.contains('fmoviesunblocked.net')) {
            referer = 'https://fmoviesunblocked.net/';
          }

          headers = {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': referer,
          };
        }

        items.add(DownloadItem(name: name, url: url, headers: headers));
      });
    });

    final titleSuffix =
        mediaType == 'series' && seasonNumber != null && episodeNumber != null
        ? ' • S${seasonNumber}E$episodeNumber'
        : '';

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DownloadPage(
        title: d.displayTitle + titleSuffix,
        items: items,
        tmdbId: d.id,
        mediaType: mediaType,
        season: seasonNumber,
        episode: episodeNumber,
        posterPath: d.backdropPath,
        primeboxUrl: widget.primeboxUrl,
      ),
    );
  }

  Future<dynamic> _postJsonWithRetry(
    String path,
    Map<String, dynamic> payload, {
    int retries = 3,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    // Normalize base so we don't get double slashes
    var base = widget.linkApiBase.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);

    final uri = Uri.parse('$base$path');

    int attempt = 0;

    while (attempt < retries) {
      attempt++;
      try {
        if (kDebugMode) {
          debugPrint('HDHub POST $uri (attempt $attempt)');
        }

        final res = await http
            .post(
              uri,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(timeout);

        // Success
        if (res.statusCode == 200) {
          return _safeJson(res.body);
        }

        // Retry only for backend problems / rate limit
        if (res.statusCode == 502 ||
            res.statusCode == 503 ||
            res.statusCode == 504 ||
            res.statusCode == 429) {
          if (kDebugMode) {
            debugPrint(
              'HDHub $path server error ${res.statusCode}, retryingâ€¦',
            );
          }
          await Future.delayed(
            Duration(milliseconds: 400 * (attempt * attempt)),
          );
          continue;
        }

        // Any other error: log and give up â†’ treat as "no sources"
        if (kDebugMode) {
          debugPrint('HDHub $path failed: ${res.statusCode} ${res.body}');
        }
        return null;
      } catch (e, st) {
        final isNet =
            e is SocketException ||
            e is TimeoutException ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup') ||
            e.toString().contains('Network is unreachable');

        if (!isNet || attempt >= retries) {
          if (kDebugMode) {
            debugPrint('HDHub $path exception: $e\n$st');
          }
          return null;
        }

        if (kDebugMode) {
          debugPrint('HDHub $path network error, retryingâ€¦ ($e)');
        }
        await Future.delayed(Duration(milliseconds: 400 * (attempt * attempt)));
      }
    }

    return null;
  }

  // ============================================================
  // Primebox source resolution
  // ============================================================

  _PrimeboxStreamBundle _bundleFromPrimeboxJson(dynamic result) {
    final rawStreams = result is Map ? result['streams'] : null;
    final rawSubtitles = result is Map ? result['subtitles'] : null;

    final sources = <String, Map<String, String>>{};
    final httpMetadata = <String, dynamic>{};

    if (rawStreams is Map) {
      rawStreams.forEach((qualityKey, streamData) {
        String url = '';
        if (streamData is Map) {
          url = streamData['url']?.toString().trim() ?? '';
        } else {
          url = streamData?.toString().trim() ?? '';
        }

        if (url.isEmpty) return;

        final quality = _normalizeQuality(qualityKey, qualityKey.toString());
        sources.putIfAbsent(quality, () => <String, String>{});
        sources[quality]!['Primebox'] = url;

        if (streamData is Map) {
          final sourceId = 'http|$quality|Primebox';
          httpMetadata[sourceId] = streamData;
        }
      });
    }

    final subtitles = <String, List<String>>{};
    if (rawSubtitles is Map) {
      rawSubtitles.forEach((lang, urls) {
        final language = lang.toString();
        if (urls is List) {
          final clean = urls
              .map((u) => u?.toString().trim() ?? '')
              .where((u) => u.isNotEmpty)
              .toList();
          if (clean.isNotEmpty) {
            subtitles[language] = clean;
          }
        }
      });
    }

    final rawDubs = result is Map ? result['dubs'] : null;
    final dubs = <Map<String, dynamic>>[];
    if (rawDubs is List) {
      for (var d in rawDubs) {
        if (d is Map) {
          dubs.add(Map<String, dynamic>.from(d));
        }
      }
    }

    return _PrimeboxStreamBundle(
      sources: sources,
      subtitles: subtitles,
      httpMetadata: httpMetadata,
      dubs: dubs,
    );
  }

  Future<_PrimeboxStreamBundle> _resolveDirectPrimeboxSources({
    required bool isShow,
    int? season,
    int? episode,
    int? subjectId,
  }) async {
    final url = widget.primeboxUrl?.trim();
    if (url == null || url.isEmpty) {
      return _PrimeboxStreamBundle(sources: {}, subtitles: {});
    }

    final type = widget.primeboxType ?? (isShow ? 'Show' : 'Movie');
    final subjectType = widget.primeboxSubjectType ?? (type == 'Movie' ? 1 : 2);

    if (kDebugMode) debugPrint('[Primebox] direct resolve: $url');

    final result = await PrimeboxService.getStreams(
      detailUrl: url,
      subjectType: subjectType,
      subjectIdIn: subjectId ?? widget.id,
      season: season,
      episode: episode,
    );

    return _bundleFromPrimeboxJson(result);
  }

  Future<_PrimeboxStreamBundle> _resolvePrimeboxSources({
    required String query,
    required bool isShow,
    int? season,
    int? episode,
    int? subjectId,
  }) async {
    final emptyBundle = _PrimeboxStreamBundle(sources: {}, subtitles: {});

    String removeYear(String s) =>
        s.replaceAll(RegExp(r'\(\d{4}\)'), '').trim();
    String removePunct(String s) => s
        .replaceAll(RegExp(r'[:\-â€“_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final queries = <String>{
      query.trim(),
      removeYear(query),
      removePunct(query),
    }.where((q) => q.isNotEmpty).toList();

    PrimeboxItem? hit;
    final cleanQuery = removePunct(removeYear(query)).toLowerCase();

    for (final q in queries) {
      if (kDebugMode) debugPrint('[Primebox] search: "$q"');
      final results = await PrimeboxService.search(q);
      if (results.isEmpty) continue;

      final wanted = isShow ? 2 : 1;
      for (final r in results) {
        final rTitle = r.title.toLowerCase();
        // Check if type matches AND title is relevant to avoid "S Line" type hits
        if (r.subjectType == wanted &&
            (rTitle.contains(cleanQuery) || cleanQuery.contains(rTitle))) {
          hit = r;
          break;
        }
      }
      if (hit != null) break;
    }

    if (hit == null || hit.link.isEmpty) {
      if (kDebugMode) debugPrint('[Primebox] no search hit for "$query"');
      return emptyBundle;
    }

    if (kDebugMode) debugPrint('[Primebox] hit: ${hit.title} -> ${hit.link}');

    final streamsData = await PrimeboxService.getStreams(
      detailUrl: hit.link,
      subjectType: hit.subjectType,
      subjectIdIn: subjectId ?? hit.subjectId,
      season: season,
      episode: episode,
    );

    return _bundleFromPrimeboxJson(streamsData);
  }

  /// Resolve streams from MovieBox /links endpoint.
  /// [data] = subjectId for movies; "subjectId|season|episode" for series.
  Future<_PrimeboxStreamBundle> _resolveMovieBoxSources({
    required String data,
  }) async {
    if (kDebugMode) debugPrint('[MovieBox] Fetching links for: $data');
    try {
      final result = await MovieBoxService.getLinks(data);
      if (result.streams.isEmpty) {
        if (kDebugMode) debugPrint('[MovieBox] No streams returned for $data');
        return _PrimeboxStreamBundle(sources: {}, subtitles: {});
      }

      final built = MovieBoxService.buildSourceMaps(result.streams);
      final subtitles = MovieBoxService.buildSubtitleMap(result.subtitles);

      if (kDebugMode) {
        debugPrint('[MovieBox] ${built.httpSources.length} quality levels, ${result.subtitles.length} subtitles');
      }

      return _PrimeboxStreamBundle(
        sources: built.httpSources,
        subtitles: subtitles,
        httpMetadata: built.httpMetadata,
        dubs: const [],
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[MovieBox] _resolveMovieBoxSources error: $e');
      return _PrimeboxStreamBundle(sources: {}, subtitles: {});
    }
  }



  /// Legacy wrapper kept for download sheet compatibility.
  Future<_PrimeboxStreamBundle> _resolveSources({
    required String query,
    int? season,
    int? episode,
    int? subjectId,
  }) async {
    final isShow = season != null || episode != null;

    // 1. MovieBox /links endpoint
    final mbId = subjectId?.toString() ?? widget.movieboxSubjectId;
    if (mbId != null && mbId.isNotEmpty) {
      final mbData = isShow && season != null && episode != null
          ? '$mbId|$season|$episode'
          : mbId;
      try {
        final mbBundle = await _resolveMovieBoxSources(data: mbData)
            .timeout(const Duration(seconds: 60), onTimeout: () => _PrimeboxStreamBundle(sources: {}, subtitles: {}));
        if (mbBundle.sources.isNotEmpty) {
          return mbBundle;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[MovieBox] resolve error: $e');
      }
    }



    final directBundle = await _resolveDirectPrimeboxSources(
      isShow: isShow,
      season: season,
      episode: episode,
      subjectId: subjectId,
    );
    if (directBundle.sources.isNotEmpty) return directBundle;

    return await _resolvePrimeboxSources(
      query: query,
      isShow: isShow,
      season: season,
      episode: episode,
      subjectId: subjectId,
    );
  }

  Future<Map<String, dynamic>?> _showDubSelectionSheet(
    BuildContext context,
    List<Map<String, dynamic>> dubs,
  ) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: const Color(0xFF0C0D12),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Language',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              itemCount: dubs.length,
              itemBuilder: (ctx, i) {
                final dub = dubs[i];
                return ListTile(
                  leading: const Icon(
                    Icons.language_rounded,
                    color: Color(0xFFFFB561),
                  ),
                  title: Text(dub['lanName'] ?? 'Unknown'),
                  onTap: () => Navigator.pop(ctx, dub),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Merge HTTP sources with priority: [primary] wins on collisions.
  /// Used to keep 4KHDHub first, then CinemaOS.
  Map<String, Map<String, String>> _mergeHttpSourcesMaps(
    Map<String, Map<String, String>> primary,
    Map<String, Map<String, String>> secondary,
  ) {
    final out = <String, Map<String, String>>{};

    void addFrom(
      Map<String, Map<String, String>> src, {
      required bool overwrite,
    }) {
      src.forEach((q, providers) {
        out.putIfAbsent(q, () => <String, String>{});
        providers.forEach((provider, url) {
          if (overwrite || !out[q]!.containsKey(provider)) {
            out[q]![provider] = url;
          }
        });
      });
    }

    // 4KHDHub first (overwrite = true), CinemaOS later (overwrite = false)
    addFrom(primary, overwrite: true);
    addFrom(secondary, overwrite: false);

    return out;
  }

  Future<Map<String, Map<String, String>>> _fetchCinemaOSSources({
    required _Details d,
    required String mediaType, // 'movie' or 'series'
    int? season,
    int? episode,
  }) async {
    String sanitizeHost(String rawHost) {
      var h = rawHost.trim();
      if (h.startsWith('http://')) h = h.substring(7);
      if (h.startsWith('https://')) h = h.substring(8);
      if (h.startsWith('//')) h = h.substring(2);
      // drop any trailing path
      final slashIdx = h.indexOf('/');
      if (slashIdx >= 0) h = h.substring(0, slashIdx);
      return h;
    }

    final params = <String, String>{'tmdb_id': d.id.toString()};
    if (mediaType == 'series') {
      if (season != null) params['season'] = season.toString();
      if (episode != null) params['episode'] = episode.toString();
    }
    final year = d.year;
    if (year != null && year.isNotEmpty) params['year'] = year;
    final title = d.displayTitle;
    if (title.isNotEmpty) params['title'] = title;

    // put your known hosts here (raw strings ok); function will sanitize
    final hostsToTryRaw = <String>['https://lumino-backend-cnmu.onrender.com'];
    final hosts = hostsToTryRaw
        .map(sanitizeHost)
        .where((h) => h.isNotEmpty)
        .toList();

    const int attemptsPerHost = 2;
    const Duration timeout = Duration(seconds: 15);

    if (kDebugMode) debugPrint('CinemaOS params: $params; hosts: $hosts');

    for (final host in hosts) {
      final uri = Uri.https(host, '/cinemaos', params);

      for (int attempt = 1; attempt <= attemptsPerHost; attempt++) {
        if (kDebugMode) debugPrint('CinemaOS GET: $uri (attempt $attempt)');
        try {
          final res = await http.get(uri).timeout(timeout);

          if (kDebugMode) {
            debugPrint(
              'CinemaOS response [${res.statusCode}] from $host: ${res.body.length} bytes',
            );
          }

          // If we get HTML (placeholder page) treat as transient
          final bodyTrim = res.body.trimLeft();
          final looksLikeHtml =
              bodyTrim.startsWith('<') ||
              (res.headers['content-type']?.contains('text/html') ?? false);
          if (looksLikeHtml) {
            if (kDebugMode) {
              debugPrint(
                'CinemaOS: HTML response (space prepping?) from $host.',
              );
            }
            if (attempt < attemptsPerHost) {
              await Future.delayed(Duration(milliseconds: 400 * attempt));
              continue;
            } else {
              // try next host
              break;
            }
          }

          if (res.statusCode == 404) {
            if (kDebugMode) {
              debugPrint('CinemaOS: 404 from $host, trying next host.');
            }
            break;
          }

          if (res.statusCode != 200) {
            if (kDebugMode) {
              debugPrint(
                'CinemaOS unexpected status ${res.statusCode} from $host; returning empty.',
              );
            }
            return <String, Map<String, String>>{};
          }

          final bodyJson = _safeJson(res.body);
          if (bodyJson is! Map) {
            if (kDebugMode) {
              debugPrint(
                'CinemaOS: response not a JSON object; bodyType=${bodyJson.runtimeType}',
              );
            }
            return <String, Map<String, String>>{};
          }

          final sources = bodyJson['sources'];
          if (sources is! List) {
            if (kDebugMode) {
              debugPrint('CinemaOS: "sources" missing or not a List.');
            }
            return <String, Map<String, String>>{};
          }

          final items = <_SourceItem>[];
          for (final s in sources) {
            if (s is! Map) continue;
            final m = Map<String, dynamic>.from(s);
            final rawUrl = (m['url'] as String?)?.trim();
            if (rawUrl == null || rawUrl.isEmpty) continue;
            final normalized = _rewritePixeldrainIfNeeded(
              _normalizeUrl(rawUrl),
            );
            if (!_allowedPlayableUrl(normalized)) continue;
            final label = (m['label'] ?? m['name'] ?? '') as String;
            final qualityRaw = m['quality'];
            final quality = _normalizeQuality(qualityRaw, '$label $normalized');
            items.add(
              _SourceItem(
                url: normalized,
                provider: 'CinemaOS',
                quality: quality,
                label: label,
              ),
            );
          }

          if (items.isEmpty) return <String, Map<String, String>>{};
          final map = <String, Map<String, String>>{};
          for (final it in items) {
            final q = it.quality;
            map.putIfAbsent(q, () => <String, String>{});
            final providerName = it.label.isNotEmpty
                ? 'CinemaOS (${it.label})'
                : 'CinemaOS';
            map[q]![providerName] = it.url;
          }
          return map;
        } catch (e, st) {
          final isNet =
              e is SocketException ||
              e.toString().contains('SocketException') ||
              e.toString().contains('Failed host lookup') ||
              e is TimeoutException;
          if (kDebugMode) {
            debugPrint(
              'CinemaOS exception for $host (attempt $attempt): $e\n$st',
            );
          }
          if (!isNet) {
            return <String, Map<String, String>>{};
          }
          if (attempt < attemptsPerHost) {
            await Future.delayed(Duration(milliseconds: 450 * attempt));
            continue;
          } else {
            break; // try next host
          }
        }
      } // attempts per host
    } // hosts loop

    if (kDebugMode) {
      debugPrint('CinemaOS: exhausted hosts, returning empty map.');
    }
    return <String, Map<String, String>>{};
  }

  // -------------------- Torrent magnet helpers (metadata only here) --------------------

  Future<List<Map<String, dynamic>>> _fetchMagnets({
    required String mediaType,
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    final uri = mediaType == 'movie'
        ? Uri.parse(
            'https://lumino-backend-cnmu.onrender.com/magnet/movie/$imdbId',
          )
        : Uri.parse(
            'https://lumino-backend-cnmu.onrender.com/magnet/series/$imdbId/${season ?? 0}/${episode ?? 0}',
          );

    if (kDebugMode) debugPrint('Magnet lookup GET: $uri');

    try {
      final res = await http.get(uri).timeout(Duration(seconds: 15));

      if (kDebugMode) {
        debugPrint(
          'Magnet response [${res.statusCode}] length=${res.body.length}',
        );
      }

      // If HTML or non-JSON (HF Space preparing), treat as transient/no-data
      final looksLikeHtml =
          res.body.trimLeft().startsWith('<') ||
          (res.headers['content-type']?.contains('text/html') ?? false);
      if (looksLikeHtml) {
        if (kDebugMode) {
          debugPrint(
            'Magnet lookup returned HTML (space not ready). Returning empty list.',
          );
        }
        return <Map<String, dynamic>>[];
      }

      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            'Magnet lookup non-200: ${res.statusCode}. Returning empty list.',
          );
        }
        return <Map<String, dynamic>>[];
      }

      final j = _safeJson(res.body);
      if (j is! Map) {
        if (kDebugMode) {
          debugPrint(
            'Magnet lookup returned non-Map JSON. Returning empty list.',
          );
        }
        return <Map<String, dynamic>>[];
      }

      final streams = (j['streams'] as List<dynamic>?) ?? <dynamic>[];
      final out = <Map<String, dynamic>>[];
      for (final s in streams) {
        if (s is Map) {
          out.add(Map<String, dynamic>.from(s));
        } else if (s is String) {
          out.add({'magnet': s});
        } else {
          out.add({'magnet': s.toString()});
        }
      }
      return out;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Magnet lookup exception: $e\n$st');
      // Network or timeout â†’ return empty instead of throwing
      return <Map<String, dynamic>>[];
    }
  }

  /// Expand raw magnet streams into entries usable by VideoPlayerScreen.
  /// Each entry: { magnet, label, fileIdx, quality, videoSize, raw }
  List<Map<String, dynamic>> _expandMagnetStreams(
    List<Map<String, dynamic>> streams,
  ) {
    final entries = <Map<String, dynamic>>[];

    for (final s in streams) {
      final dynamic magnetField = s['magnet'] ?? s;

      final filesList =
          s['files'] ?? s['fileList'] ?? s['file_entries'];
      if (filesList is List && filesList.isNotEmpty) {
        for (var i = 0; i < filesList.length; i++) {
          final f = filesList[i];
          final fname = (f is Map && (f['name'] is String))
              ? f['name'] as String
              : f.toString();
          final fsize = (f is Map && (f['size'] is int))
              ? f['size'] as int
              : (f is Map && f['length'] is int)
              ? f['length'] as int
              : null;
          final fileIdx = (f is Map && (f['fileIdx'] != null))
              ? (f['fileIdx'] as int)
              : i;
          final label = '${s['name'] ?? s['title'] ?? fname}';
          final quality = _normalizeQuality(
            s['quality'] ??
                (f is Map ? f['quality'] : null) ??
                s['name'] ??
                fname,
            label,
          );

          entries.add({
            'magnet': magnetField,
            'label': label,
            'fileIdx': fileIdx,
            'raw': s,
            'quality': quality,
            'videoSize': fsize ?? (s['videoSize'] ?? s['video_size'] ?? 0),
          });
        }
      } else {
        final fileIdx =
            (s['fileIdx'] ?? s['fileIndex'] ?? s['fileIndexFromSource'] ?? 0)
                as int?;
        final behaviorHints = s['behaviorHints'];
        final bhFilename = (behaviorHints is Map)
            ? behaviorHints['filename'] as String?
            : null;
        final label =
            (s['behaviorHints']?['filename']?.toString()) ??
            bhFilename ??
            (s['description'] as String?) ??
            'Stream';
        final quality = _normalizeQuality(s['quality'] ?? label, label);
        final vsize = s['videoSize'] ?? s['video_size'];

        entries.add({
          'magnet': magnetField,
          'label': label,
          'fileIdx': fileIdx ?? 0,
          'raw': s,
          'quality': quality,
          'videoSize': vsize,
        });
      }
    }

    // sort by quality (best first) then by size desc (prefer larger video size)
    entries.sort((a, b) {
      final qa = (a['quality'] as String?) ?? _fallbackQuality;
      final qb = (b['quality'] as String?) ?? _fallbackQuality;
      final qi = _qualIndex(qa), qj = _qualIndex(qb);
      if (qi != qj) return qi.compareTo(qj);
      final sa = (a['videoSize'] is num) ? (a['videoSize'] as num) : 0;
      final sb = (b['videoSize'] is num) ? (b['videoSize'] as num) : 0;
      return sb.compareTo(sa);
    });

    return entries;
  }

  String _pickInitialQualityFromCombined(
    Map<String, Map<String, String>> httpSources,
    List<Map<String, dynamic>> torrentEntries,
  ) {
    final qs = <String>{};
    qs.addAll(httpSources.keys);
    for (final e in torrentEntries) {
      final q = e['quality'] as String?;
      if (q != null && q.isNotEmpty) {
        qs.add(q);
      }
    }
    if (qs.isEmpty) return _fallbackQuality;

    for (final desired in _qOrder) {
      if (qs.contains(desired)) return desired;
    }
    return qs.first;
  }

  // -------------------- Play entry points --------------------

  Future<void> _openPlayerWithSources({
    required _Details d,
    required String mediaType, // 'movie' or 'series'
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
  }) async {
    // Capture context BEFORE any await, so we don't touch State.context later.
    final ctx = context;

    final query = d.displayTitle;
    final isShow = mediaType == 'tv' || mediaType == 'series';

    WakelockPlus.enable();
    _setBusy(true, 'Finding streamsâ€¦');

    // Primary: MovieBox (DASH/HLS streams) or Primebox (m3u8 streams + subtitles)
    _PrimeboxStreamBundle primeboxBundle = _PrimeboxStreamBundle(
      sources: {},
      subtitles: {},
    );

    try {
      // 0. MovieBox path — use /links endpoint when we have a subject ID
      if (widget.movieboxSubjectId != null && widget.movieboxSubjectId!.isNotEmpty) {
        final mbData = isShow && seasonNumber != null && episodeNumber != null
            ? '${widget.movieboxSubjectId}|$seasonNumber|$episodeNumber'
            : widget.movieboxSubjectId!;
        primeboxBundle = await _resolveMovieBoxSources(data: mbData)
            .timeout(const Duration(seconds: 60), onTimeout: () => _PrimeboxStreamBundle(sources: {}, subtitles: {}));
      }

      // 1. Existing Primebox direct + search resolve (fallback)
      if (primeboxBundle.sources.isEmpty) {
        // Parallelize Direct Resolve and Search Resolve for faster results on mobile
        final results =
            await Future.wait([
              _resolveDirectPrimeboxSources(
                isShow: isShow,
                season: isShow ? seasonNumber : null,
                episode: isShow ? episodeNumber : null,
              ),
              _resolvePrimeboxSources(
                query: query,
                isShow: isShow,
                season: isShow ? seasonNumber : null,
                episode: isShow ? episodeNumber : null,
              ),
            ]).timeout(
              const Duration(seconds: 60),
              onTimeout: () => [
                _PrimeboxStreamBundle(sources: {}, subtitles: {}),
                _PrimeboxStreamBundle(sources: {}, subtitles: {}),
              ],
            );

        final directBundle = results[0];
        final searchBundle = results[1];

        if (directBundle.sources.isNotEmpty) {
          primeboxBundle = directBundle;
        } else if (searchBundle.sources.isNotEmpty) {
          primeboxBundle = searchBundle;
        }
      }

      // Use Primebox sources only
      final httpSources = primeboxBundle.sources;
      final torrentStreams = <Map<String, dynamic>>[];

      WakelockPlus.disable();
      _setBusy(false);

      // If this widget got disposed while we were waiting, bail out.
      if (!mounted) return;

      if (httpSources.isEmpty && torrentStreams.isEmpty) {
        AppToast.show(ctx, 'No sources found.', icon: Icons.error_rounded);
        return;
      }

      final initialQuality = _pickInitialQualityFromCombined(
        httpSources,
        torrentStreams,
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            title: d.displayTitle,
            episodeTitle: !isShow ? '' : episodeTitle ?? '',
            httpSources: httpSources,
            torrentStreams: torrentStreams,
            initialQuality: initialQuality,
            imdbId: d.imdbId,
            subtitleUrls: primeboxBundle.subtitles.isNotEmpty
                ? primeboxBundle.subtitles
                : null,
            isTvShow: isShow,
            tmdbId: d.id != 0 ? d.id : null,
            tmdbApiBase: widget.base,
            tmdbApiKey: widget.apiKey,
            initialSeason: seasonNumber,
            initialEpisode: episodeNumber,
            posterPath: d.backdropPath,
            primeboxUrl: widget.primeboxUrl,
            primeboxSubjectType: widget.primeboxSubjectType,
            primeboxType: widget.primeboxType,
            movieboxSubjectId: widget.movieboxSubjectId,
            externalDubs: primeboxBundle.dubs,
            httpMetadata: {
              ...(primeboxBundle.httpMetadata ?? {}),
              if (d.logoPath != null) 'logo': d.logoPath,
              if (d.overview != null) 'plot': d.overview,
              if (d.voteAverage != null) 'rating': d.voteAverage,
              if (d.runtime != null) 'duration': d.runtime,
              if (d.releaseDate != null && d.releaseDate!.length >= 4) 'year': d.releaseDate!.substring(0, 4)
              else if (d.firstAirDate != null && d.firstAirDate!.length >= 4) 'year': d.firstAirDate!.substring(0, 4),
            },
            initialPosition:
                (_historyItem != null &&
                    _historyItem!.mediaType == (!isShow ? 'movie' : 'tv') &&
                    (!isShow ||
                        (_historyItem!.season == seasonNumber &&
                            _historyItem!.episode == episodeNumber)))
                ? Duration(milliseconds: _historyItem!.position)
                : null,
            seasonsMeta: isShow
                ? d.seasons
                      .map(
                        (s) => TvSeasonMeta(
                          seasonNumber: s.seasonNumber,
                          name: s.name,
                          episodeCount: s.episodeCount,
                        ),
                      )
                      .toList()
                : null,
            // When user picks another episode from the overlay
            onEpisodeSelected: isShow
                ? (sn, en, epTitle) async {
                    // Fetch new episode sources quietly without popping the player
                    final query = d.displayTitle;
                    _PrimeboxStreamBundle epBundle = _PrimeboxStreamBundle(
                      sources: {},
                      subtitles: {},
                    );

                    try {
                      // 0. MovieBox path
                      if (widget.movieboxSubjectId != null && widget.movieboxSubjectId!.isNotEmpty) {
                        final mbData = '${widget.movieboxSubjectId}|$sn|$en';
                        epBundle = await _resolveMovieBoxSources(data: mbData)
                            .timeout(const Duration(seconds: 60), onTimeout: () => _PrimeboxStreamBundle(sources: {}, subtitles: {}));
                      }

                      // 1. Primebox fallback
                      if (epBundle.sources.isEmpty) {
                        final results = await Future.wait([
                          _resolveDirectPrimeboxSources(
                            isShow: true,
                            season: sn,
                            episode: en,
                          ),
                          _resolvePrimeboxSources(
                            query: query,
                            isShow: true,
                            season: sn,
                            episode: en,
                          ),
                        ]).timeout(
                          const Duration(seconds: 60),
                          onTimeout: () => [
                            _PrimeboxStreamBundle(sources: {}, subtitles: {}),
                            _PrimeboxStreamBundle(sources: {}, subtitles: {}),
                          ],
                        );

                        final directBundle = results[0];
                        final searchBundle = results[1];

                        if (directBundle.sources.isNotEmpty) {
                          epBundle = directBundle;
                        } else if (searchBundle.sources.isNotEmpty) {
                          epBundle = searchBundle;
                        }
                      }

                      return {
                        'httpSources': epBundle.sources,
                        'subtitleUrls': epBundle.subtitles.isNotEmpty
                            ? epBundle.subtitles
                            : null,
                        'externalDubs': epBundle.dubs,
                        'httpMetadata': epBundle.httpMetadata,
                      };
                    } catch (e) {
                      if (kDebugMode) debugPrint('[_onEpisodeSelected Fetch Error] $e');
                      return null;
                    }
                  }
                : null,
          ),
        ),
      ).then((_) => _loadHistory());
    } catch (e) {
      WakelockPlus.disable();
      _setBusy(false);
      if (kDebugMode) debugPrint('[_openPlayerWithSources] error: $e');
      if (mounted) {
        AppToast.show(ctx, 'Error finding streams.', icon: Icons.error_rounded);
      }
    }
  }

  Future<void> _playMovie(_Details d) async {
    await _openPlayerWithSources(d: d, mediaType: 'movie');
  }

  Future<void> _playEpisode({
    required _Details d,
    required int seasonNumber,
    required int episodeNumber,
    required String episodeTitle,
  }) async {
    await _openPlayerWithSources(
      d: d,
      mediaType: 'series',
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
    );
  }

  void _onBannerPlayPressed(_Details d) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Trailer(
        title: d.displayTitle,
        imdbId: d.imdbId,
        type: widget.mediaType, // 'movie' or 'tv'
        directUrl: d.trailerUrl, // NEW: Primebox direct MP4 link
      ),
    );
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).size.width * 0.00;
    final h = MediaQuery.of(context).size.height;
    final isMovie = widget.mediaType == 'movie';

    return Stack(
      children: [
        Scaffold(
          body: FutureBuilder<_DetailBundle?>(
            future: _future,
            builder: (context, snap) {
              // 1. Still loading or busy
              if (snap.connectionState != ConnectionState.done) {
                return const _Loader();
              }

              // Device truly offline (NetworkService)
              if (!_isOnline && !snap.hasData) {
                return const _NoNetworkState();
              }

              if (_contentNotFound) {
                return const _NoNetworkState(isNotFound: true);
              }

              // TMDB fetch failed (null)
              if (!snap.hasData || snap.data == null) {
                return const _NoNetworkState(); // treat TMDB failure as offline
              }

              // 4) Safe: we have data
              final bundle = snap.data!;
              final d = bundle.details;
              final c = bundle.credits;

              final bgPosterUrl = d.backdropPath != null
                  ? (d.backdropPath!.startsWith('http')
                        ? d.backdropPath!
                        : 'https://image.tmdb.org/t/p/w1280${d.backdropPath}')
                  : null;

              final posterUrl = d.posterPath != null
                  ? (d.posterPath!.startsWith('http')
                        ? d.posterPath!
                        : 'https://image.tmdb.org/t/p/w780${d.posterPath}')
                  : null;

              final finalBgUrl = !_isDesktop && posterUrl != null
                  ? posterUrl
                  : bgPosterUrl;

              final isMovie = widget.mediaType == 'movie';

              return RawKeyboardListener(
                focusNode: _keyboardFocusNode,
                onKey: (event) {
                  if (event is RawKeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _scrollController.animateTo(
                        (_scrollController.offset - 100).clamp(
                          0.0,
                          _scrollController.position.maxScrollExtent,
                        ),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      );
                    } else if (event.logicalKey ==
                        LogicalKeyboardKey.arrowDown) {
                      _scrollController.animateTo(
                        (_scrollController.offset + 100).clamp(
                          0.0,
                          _scrollController.position.maxScrollExtent,
                        ),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      );
                    }
                    if (event.logicalKey == LogicalKeyboardKey.escape) {
                      Navigator.of(context).maybePop();
                    }
                  }
                },
                child: Stack(
                  children: [
                    // LAYERED BACKDROP: Clear top, blurred bottom
                    Positioned.fill(
                      child: bgPosterUrl != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                // 1. Base clear image
                                CachedNetworkImage(
                                  imageUrl: finalBgUrl!,
                                  fit: BoxFit.cover,
                                  alignment: _isDesktop
                                      ? Alignment.topCenter
                                      : Alignment.center,
                                ),
                                // 2. Blurred image masked with a gradient (butter smooth transition)
                                ShaderMask(
                                  shaderCallback: (rect) =>
                                      const LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.transparent,
                                          Colors.black,
                                          Colors.black,
                                        ],
                                        stops: [0.0, 0.48, 0.65, 1.0],
                                      ).createShader(rect),
                                  blendMode: BlendMode.dstIn,
                                  child: ImageFiltered(
                                    imageFilter: ImageFilter.blur(
                                      sigmaX: 80,
                                      sigmaY: 80,
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: finalBgUrl,
                                      fit: BoxFit.cover,
                                      alignment: _isDesktop
                                          ? Alignment.topCenter
                                          : Alignment.center,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const ColoredBox(color: Color(0xFF0C0D12)),
                    ),
                    // Butter smooth dark gradient overlay for text readability
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: _isDesktop ? 0.1 : 0.4),
                              Colors.black.withValues(alpha: _isDesktop ? 0.3 : 0.5),
                              Colors.black.withValues(alpha: 0.6),
                              Colors.black.withValues(alpha: 0.85),
                              Colors.black,
                            ],
                            stops: _isDesktop
                                ? const [0.0, 0.35, 0.6, 0.85, 1.0]
                                : const [0.0, 0.20, 0.45, 0.80, 1.0],
                          ),
                        ),
                      ),
                    ),

                    CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        // Back button pinned at top (safe area aware for notch)
                        SliverToBoxAdapter(
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                pad + 8,
                                8,
                                pad + 8,
                                0,
                              ),
                              child: Row(
                                children: [
                                  _roundBtn(
                                    icon: Icons.arrow_back_ios_new,
                                    onTap: () =>
                                        Navigator.of(context).maybePop(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Hero spacer + info panel (adaptive top offset)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              _isDesktop ? 40 : 16,
                              _isDesktop
                                  ? h * 0.20
                                  : h * 0.27, // Starts at 50% on mobile
                              _isDesktop ? 40 : 16,
                              12,
                            ),
                            child: _HeroInfoPanel(
                              logoUrl: _logoUrl,
                              title: d.displayTitle,
                              imdbRating: _imdbRating ?? d.voteAverage,
                              contentRating: d.contentRating,
                              metaDuration: d.metaDuration,
                              seasons: d.seasons,
                              year: d.year,
                              genres: d.genres,
                              mediaType: widget.mediaType,
                              historyItem: _historyItem,
                              languageLabel: d.languageLabel,
                              status: d.status,
                              nextAirDate: d.nextAirDate,
                              nextEpisodeSeason: d.nextEpisodeSeason,
                              nextEpisodeNumber: d.nextEpisodeNumber,
                              lastAirDate: d.lastAirDate,
                              lastEpisodeSeason: d.lastEpisodeSeason,
                              lastEpisodeNumber: d.lastEpisodeNumber,
                              totalSeasons: d.totalSeasons,
                              totalEpisodes: d.totalEpisodes,
                              inProduction: d.inProduction,
                              onPlay: () {
                                if (isMovie) {
                                  _playMovie(d);
                                } else {
                                  if (_historyItem != null &&
                                      _historyItem!.season != null &&
                                      _historyItem!.episode != null) {
                                    _playEpisode(
                                      d: d,
                                      seasonNumber: _historyItem!.season!,
                                      episodeNumber: _historyItem!.episode!,
                                      episodeTitle:
                                          _historyItem!.episodeTitle ?? '',
                                    );
                                  } else {
                                    _playEpisode(
                                      d: d,
                                      seasonNumber: 1,
                                      episodeNumber: 1,
                                      episodeTitle: '',
                                    );
                                  }
                                }
                              },
                              onDownload: () => _openDownloadSheet(
                                d: d,
                                mediaType: isMovie ? 'movie' : 'series',
                                seasonNumber: 1,
                                episodeNumber: 1,
                                episodeTitle: '',
                              ),
                              onTrailer: () => _onBannerPlayPressed(d),
                              isDesktop: _isDesktop,
                            ),
                          ),
                        ),

                        // Storyline
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              _isDesktop ? 40 : 16,
                              12,
                              _isDesktop ? 40 : 16,
                              0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Story Line',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _ExpandableText(d.overview ?? 'No overview.'),
                              ],
                            ),
                          ),
                        ),
                        // Cast & Crew
                        ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              _isDesktop ? 40 : 16,
                              20,
                              _isDesktop ? 40 : 16,
                              0,
                            ),
                            child: const Text(
                              'Cast and Crew',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              _isDesktop ? 35 : 8,
                              0,
                              0,
                              0,
                            ),
                            child: _PeopleRow(
                              title: '',
                              people: c.cast.take(20).toList(),
                              imgW185: widget.imgW185,
                            ),
                          ),
                        ),
                      ],
                        // Episodes
                        if (widget.mediaType == 'tv' &&
                            d.seasons.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 24, 0, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: _isDesktop ? 40 : 16,
                                    ),
                                    child: const _SectionTitle('Episodes'),
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    height: 45,
                                    child: ScrollConfiguration(
                                      behavior: const _AppScrollBehavior(),
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        physics: const BouncingScrollPhysics(),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: _isDesktop ? 40 : 16,
                                        ),
                                        itemCount: d.seasons.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(width: 10),
                                        itemBuilder: (context, index) {
                                          final s = d.seasons[index];
                                          final isSelected =
                                              s.seasonNumber ==
                                              _selectedSeasonNumber;
                                          return InkWell(
                                            onTap: () => _onSeasonChanged(
                                              s.seasonNumber,
                                              d,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                  ),
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                gradient: isSelected
                                                    ? const LinearGradient(
                                                        colors: [
                                                          Color(0xFFFFE3B5),
                                                          Color(0xFFFFB561),
                                                        ],
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
                                                      )
                                                    : null,
                                                color: isSelected
                                                    ? null
                                                    : Colors.white10,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? Colors.transparent
                                                      : Colors.white24,
                                                ),
                                              ),
                                              child: Text(
                                                'Season ${s.seasonNumber}${s.episodeCount != null ? " (${s.episodeCount})" : ""}',
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? Colors.black
                                                      : Colors.white70,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 25),
                                ],
                              ),
                            ),
                          ),

                          SliverToBoxAdapter(
                            child: FutureBuilder<_TvSeason?>(
                              future: _seasonFuture,
                              builder: (context, snap) {
                                if (snap.connectionState !=
                                    ConnectionState.done) {
                                  return const Padding(
                                    padding: EdgeInsets.all(60),
                                    child: Center(
                                      child: SizedBox(
                                        width: 35,
                                        height: 35,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: Color(0xFFFFB561),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final season = snap.data;
                                if (season == null || season.episodes.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text('No episodes found.'),
                                  );
                                }
                                final allEpisodes = season.episodes;

                                // Filter episodes based on search query
                                final filteredEpisodes = allEpisodes.where((e) {
                                  if (_episodeSearchQuery.isEmpty) return true;
                                  final q = _episodeSearchQuery.toLowerCase();
                                  final title = (e.name ?? '').toLowerCase();
                                  final epNum = e.episodeNumber.toString();
                                  return title.contains(q) ||
                                      epNum == q ||
                                      epNum.contains(q);
                                }).toList();

                                final totalEpisodes = filteredEpisodes.length;
                                const pageSize = 25;

                                // If searching, show all matches without pagination for better UX
                                final isSearching =
                                    _episodeSearchQuery.isNotEmpty;
                                final totalPages = isSearching
                                    ? 1
                                    : (totalEpisodes / pageSize).ceil();

                                final pagedEpisodes = isSearching
                                    ? filteredEpisodes
                                    : filteredEpisodes
                                          .skip(_currentEpisodePage * pageSize)
                                          .take(pageSize)
                                          .toList();

                                return Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    _isDesktop ? 40 : 12,
                                    0,
                                    _isDesktop ? 40 : 12,
                                    24,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // ---- Search Bar ----
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 20,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Container(
                                                height: 45,
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.05),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.white10,
                                                  ),
                                                ),
                                                child: TextField(
                                                  controller:
                                                      _episodeSearchController,
                                                  onChanged: (v) => setState(() {
                                                    _episodeSearchQuery = v;
                                                    _currentEpisodePage =
                                                        0; // Reset page on search
                                                  }),
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                  ),
                                                  decoration: InputDecoration(
                                                    hintText:
                                                        'Search episode by name or number...',
                                                    hintStyle: TextStyle(
                                                      color: Colors.white
                                                          .withValues(alpha: 0.3),
                                                      fontSize: 13,
                                                    ),
                                                    prefixIcon: Icon(
                                                      Icons.search_rounded,
                                                      color: Colors.white
                                                          .withValues(alpha: 0.3),
                                                      size: 20,
                                                    ),
                                                    suffixIcon:
                                                        _episodeSearchQuery
                                                            .isNotEmpty
                                                        ? IconButton(
                                                            icon: const Icon(
                                                              Icons
                                                                  .clear_rounded,
                                                              size: 18,
                                                            ),
                                                            onPressed: () {
                                                              _episodeSearchController
                                                                  .clear();
                                                              setState(() {
                                                                _episodeSearchQuery =
                                                                    '';
                                                                _currentEpisodePage =
                                                                    0;
                                                              });
                                                            },
                                                          )
                                                        : null,
                                                    border: InputBorder.none,
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 10,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      if (totalPages > 1 && !isSearching)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 20,
                                          ),
                                          child: Center(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.05,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                                border: Border.all(
                                                  color: Colors.white10,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.chevron_left,
                                                    ),
                                                    onPressed:
                                                        _currentEpisodePage > 0
                                                        ? () => setState(
                                                            () =>
                                                                _currentEpisodePage--,
                                                          )
                                                        : null,
                                                  ),
                                                  Container(
                                                    height: 24,
                                                    width: 1,
                                                    color: Colors.white10,
                                                  ),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 20,
                                                        ),
                                                    child: Text(
                                                      'Page ${_currentEpisodePage + 1} of $totalPages',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    height: 24,
                                                    width: 1,
                                                    color: Colors.white10,
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.chevron_right,
                                                    ),
                                                    onPressed:
                                                        _currentEpisodePage <
                                                            totalPages - 1
                                                        ? () => setState(
                                                            () =>
                                                                _currentEpisodePage++,
                                                          )
                                                        : null,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      // ---- Responsive Grid ----
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final cols =
                                              constraints.maxWidth >= 900
                                              ? 4
                                              : 2;
                                          final gap = 12.0;
                                          final cardWidth =
                                              (constraints.maxWidth -
                                                  gap * (cols - 1)) /
                                              cols;
                                          return Wrap(
                                            spacing: gap,
                                            runSpacing: gap,
                                            children: pagedEpisodes.map((e) {
                                              return SizedBox(
                                                width: cardWidth,
                                                child: _EpisodeCard(
                                                  thumbUrl: e.stillPath != null
                                                      ? (e.stillPath!
                                                                .startsWith(
                                                                  'http',
                                                                )
                                                            ? e.stillPath
                                                            : '${widget.imgW780}${e.stillPath}')
                                                      : (d.backdropPath != null
                                                            ? (d.backdropPath!
                                                                      .startsWith(
                                                                        'http',
                                                                      )
                                                                  ? d.backdropPath
                                                                  : '${widget.imgW780}${d.backdropPath}')
                                                            : null),
                                                  number: e.episodeNumber,
                                                  runtime: e.runtime,
                                                  title:
                                                      e.name ??
                                                      'Episode ${e.episodeNumber}',
                                                  overview: e.overview ?? '',
                                                  onPlay: () => _playEpisode(
                                                    d: d,
                                                    seasonNumber:
                                                        season.seasonNumber,
                                                    episodeNumber:
                                                        e.episodeNumber,
                                                    episodeTitle:
                                                        e.name ??
                                                        'Episode ${e.episodeNumber}',
                                                  ),
                                                  onDownload: () =>
                                                      _openDownloadSheet(
                                                        d: d,
                                                        mediaType: 'series',
                                                        seasonNumber:
                                                            season.seasonNumber,
                                                        episodeNumber:
                                                            e.episodeNumber,
                                                        episodeTitle:
                                                            e.name ??
                                                            'Episode ${e.episodeNumber}',
                                                      ),
                                                ),
                                              );
                                            }).toList(),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        // Extra bottom padding for home bar / nav bar
                        SliverToBoxAdapter(
                          child: SafeArea(
                            top: false,
                            child: const SizedBox(height: 32),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const DownloadOverlay(),
        if (_busy)
          Positioned.fill(
            child: Stack(
              children: [
                // FULL BLACK BASE BACKGROUND (behind everything)
                const Positioned.fill(
                  child: ColoredBox(color: Color.fromARGB(255, 17, 17, 17)),
                ),
                const Center(child: AppLoader(size: 250)),
              ],
            ),
          ),
      ],
    );
  }

  // ---- small UI helpers (same as before) ----
  Widget _roundBtn({
    required IconData icon,
    Color? color,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(40),
    child: Container(
      decoration: const BoxDecoration(
        color: WidgetStateColor.transparent,
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(10),
      child: Icon(icon, color: color ?? Colors.white),
    ),
  );

  Widget _ctaButtons({
    required String mediaType,
    required VoidCallback onPlay,
    required VoidCallback onDownload,
    required VoidCallback onShare,
    WatchHistoryItem? historyItem,
  }) {
    final playButtonSection = Column(
      crossAxisAlignment: _isDesktop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _isDesktop ? 200 : null,
          child: _PlayButton3D(
            onPressed: onPlay,
            mediaType: mediaType,
            historyItem: historyItem,
          ),
        ),
        if (!_isDesktop && historyItem != null && historyItem.duration > 0) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: _isDesktop ? 220 : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (historyItem.position / historyItem.duration).clamp(
                      0.0,
                      1.0,
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    color: const Color(0xFFFFB561),
                    minHeight: 3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(historyItem.position / 60000).toInt()}m watched',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    return Row(
      children: [
        if (_isDesktop)
          playButtonSection
        else
          Expanded(flex: 3, child: playButtonSection),
        const SizedBox(width: 12),
        Column(
          children: [
            _IconButton3D(
              onPressed: onDownload,
              icon: Icons.download_for_offline_rounded,
            ),
            if (historyItem != null && historyItem.duration > 0)
              const SizedBox(height: 18),
          ],
        ),
        const SizedBox(width: 12),
        Column(
          children: [
            _IconButton3D(onPressed: onShare, icon: Icons.share_rounded),
            if (historyItem != null && historyItem.duration > 0)
              const SizedBox(height: 18),
          ],
        ),
      ],
    );
  }

  Widget _buildGenreChips(List<String> genres) {
    if (genres.isEmpty) return const SizedBox.shrink();
    // Show at least 5 genres if available
    final displayGenres = genres.take(5).toList();
    //normal text chips
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: displayGenres
          .map(
            (g) => Text(
              "$g • ",
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMetaChip({
    required String label,
    required IconData icon,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2531),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? Colors.white54),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color != null ? color.withValues(alpha: 0.9) : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconPill({required VoidCallback onTap, required IconData icon}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2531),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, size: 24),
        ),
      );
}

// ---- _HeroInfoPanel: the content overlay on the full-screen backdrop ----

class _HeroInfoPanel extends StatelessWidget {
  final String? logoUrl;
  final String title;
  final double? imdbRating;
  final String? contentRating;
  final String? metaDuration;
  final List<_SeasonStub> seasons;
  final String? year;
  final List<String> genres;
  final String mediaType;
  final WatchHistoryItem? historyItem;
  final VoidCallback onPlay;
  final VoidCallback onDownload;
  final VoidCallback onTrailer;
  final String? languageLabel;
  final String? status;
  final String? nextAirDate;
  final int? nextEpisodeSeason;
  final int? nextEpisodeNumber;
  final String? lastAirDate;
  final int? lastEpisodeSeason;
  final int? lastEpisodeNumber;
  final int? totalSeasons;
  final int? totalEpisodes;
  final bool? inProduction;
  final bool isDesktop;

  const _HeroInfoPanel({
    required this.logoUrl,
    required this.title,
    required this.imdbRating,
    required this.contentRating,
    required this.metaDuration,
    required this.seasons,
    required this.year,
    required this.genres,
    required this.mediaType,
    required this.historyItem,
    required this.onPlay,
    required this.onDownload,
    required this.onTrailer,
    this.languageLabel,
    this.status,
    this.nextAirDate,
    this.nextEpisodeSeason,
    this.nextEpisodeNumber,
    this.lastAirDate,
    this.lastEpisodeSeason,
    this.lastEpisodeNumber,
    this.totalSeasons,
    this.totalEpisodes,
    this.inProduction,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo or title text â€” responsive height
        LayoutBuilder(
          builder: (ctx, c) {
            final halfScreen = MediaQuery.of(context).size.width * 0.5;
            final logoH = c.maxWidth < 400 ? 80.0 : 120.0;
            return logoUrl != null
                ? ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: halfScreen,
                      maxWidth: halfScreen,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: logoUrl!,
                      height: logoH,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      fadeInDuration: const Duration(milliseconds: 400),
                      placeholder: (context, url) => SizedBox(height: logoH),
                      errorWidget: (context, url, error) => _titleText(),
                    ),
                  )
                : _titleText();
          },
        ),

        const SizedBox(height: 16),

        // Meta row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (imdbRating != null) ...[
                _ratingBadge(imdbRating!),
                const SizedBox(width: 8),
              ],
              if (contentRating != null) ...[
                _metaBadge(contentRating!),
                const SizedBox(width: 8),
              ],
              if (languageLabel != null) ...[
                _metaBadge(languageLabel!),
                const SizedBox(width: 8),
              ],
              _metaBadge(
                mediaType == 'movie'
                    ? (metaDuration ?? 'N/A')
                    : '${totalSeasons ?? seasons.length} ${(totalSeasons ?? seasons.length) == 1 ? "Season" : "Seasons"}',
              ),
              if (mediaType == 'tv' && totalEpisodes != null) ...[
                const SizedBox(width: 8),
                _metaBadge('$totalEpisodes Episodes'),
              ],
              if (year != null) ...[
                const SizedBox(width: 8),
                _metaBadge(year!),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Genres
        if (genres.isNotEmpty)
          Text(
            genres.take(4).join(' • '),
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white60,
              fontWeight: FontWeight.w500,
            ),
          ),

        if (mediaType == 'tv' && (status != null || nextAirDate != null || lastAirDate != null)) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status != null) _statusBadge(status!),
              if (lastAirDate != null)
                _epBadge(
                  prefix: 'Latest',
                  date: lastAirDate!,
                  season: lastEpisodeSeason,
                  episode: lastEpisodeNumber,
                ),
              if (nextAirDate != null)
                _epBadge(
                  prefix: 'Next',
                  date: nextAirDate!,
                  season: nextEpisodeSeason,
                  episode: nextEpisodeNumber,
                ),
            ],
          ),
        ],

        const SizedBox(height: 16),

        // Watch progress bar
        if (historyItem != null && historyItem!.duration > 0) ...[
          SizedBox(
            width: isDesktop ? 220 : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (historyItem!.position / historyItem!.duration)
                        .clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    color: const Color(0xFFFFB561),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${(historyItem!.position / 60000).toInt()}m watched',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Watch Now
            if (isDesktop)
              SizedBox(
                width: 220,
                child: _PlayButton3D(
                  onPressed: onPlay,
                  mediaType: mediaType,
                  historyItem: historyItem,
                ),
              )
            else
              Expanded(
                child: _PlayButton3D(
                  onPressed: onPlay,
                  mediaType: mediaType,
                  historyItem: historyItem,
                ),
              ),

            const SizedBox(width: 10),

            // Trailer
            _SecondaryButton3D(
              onPressed: onTrailer,
              label: 'Trailer',
              icon: Icons.play_circle_outline_rounded,
            ),

            const SizedBox(width: 10),

            // Download
            _IconButton3D(
              onPressed: onDownload,
              icon: Icons.download_for_offline_rounded,
            ),
          ],
        ),
      ],
    );
  }

  Widget _titleText() => LayoutBuilder(
    builder: (ctx, c) {
      final fs = c.maxWidth < 340
          ? 24.0
          : c.maxWidth < 420
          ? 28.0
          : 34.0;
      return Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fs,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
          color: Colors.white,
          shadows: const [Shadow(blurRadius: 12, color: Colors.black54)],
        ),
      );
    },
  );

  Widget _ratingBadge(double rating) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFFFB561).withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFFFB561).withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB561)),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFFB561),
          ),
        ),
      ],
    ),
  );

  Widget _metaBadge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.white70,
      ),
    ),
  );

  Widget _statusBadge(String status) {
    Color color;
    IconData icon;

    final s = status.toLowerCase();
    //if s.contains('returning') then change that to 'ongoing'
    if (s.contains('returning')) {
      status = 'Ongoing';
    }
    //if s.contains('in production') then change that to 'ongoing'
    if (s.contains('in production')) {
      status = 'Ongoing';
    }
    if (s.contains('ongoing') ||
        s.contains('returning') ||
        s.contains('in production')) {
      color = const Color(0xFF4CAF50); // Green for ongoing
      icon = Icons.play_circle_filled_rounded;
    } else if (s.contains('ended')) {
      color = Colors.white60; // Grey for ended
      icon = Icons.stop_circle_rounded;
    } else if (s.contains('canceled')) {
      color = Colors.redAccent;
      icon = Icons.cancel_rounded;
    } else {
      color = Colors.blueAccent;
      icon = Icons.info_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _epBadge({required String prefix, required String date, int? season, int? episode}) {
    String label = '$prefix Episode';
    if (season != null && episode != null) {
      label = '$prefix: S$season.E$episode';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB561).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFB561).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.event_repeat_rounded,
            size: 14,
            color: Color(0xFFFFB561),
          ),
          const SizedBox(width: 6),
          Text(
            '$label - ${_formatAirDate(date)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFFFFB561),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAirDate(String rawDate) {
    try {
      final DateTime dt = DateTime.parse(rawDate);
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return rawDate;
    }
  }
}

// ---------- Small UI components ----------

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) =>
      const Center(child: AppLoader(size: 250));
}

class _NoNetworkState extends StatelessWidget {
  final bool isNotFound;
  const _NoNetworkState({this.isNotFound = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0C0C0F),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // icon â€œbadgeâ€
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2C2F3A), Color(0xFF151822)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.7),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Icon(
                  isNotFound
                      ? Icons.search_off_rounded
                      : Icons.wifi_off_rounded,
                  size: 34,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                isNotFound ? 'Content Unavailable' : 'No Internet Connection',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isNotFound
                    ? 'We couldn\'t retrieve the details for this item. It might be temporarily removed or restricted.'
                    : 'Check your connection and try again to continue watching.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F2531),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(isNotFound ? 'Go Back' : 'Retry'),
              ),
              if (!isNotFound) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyDownloadsPage(),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  icon: const Icon(Icons.download_for_offline_rounded),
                  label: const Text('Go to Downloads'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<http.Response?> _safeGet(
  Uri uri, {
  int retries = 2,
  Duration timeout = const Duration(seconds: 15),
  Map<String, String>? headers,
}) async {
  int attempt = 0;

  while (attempt <= retries) {
    try {
      final res = await http.get(uri, headers: headers).timeout(timeout);

      // SUCCESS
      if (res.statusCode == 200) return res;

      // Retry only for server-side problems or rate limits
      if (res.statusCode >= 500 || res.statusCode == 429) {
        attempt++;
        if (attempt <= retries) {
          await Future.delayed(Duration(milliseconds: 1000 * attempt));
          continue;
        }
      }

      // Return the response even if it's 404 etc., so caller can handle it
      return res;
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      final isNet =
          e is SocketException ||
          e is TimeoutException ||
          errStr.contains('socketexception') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('network is unreachable') ||
          errStr.contains('clientexception') ||
          errStr.contains('connection closed') ||
          errStr.contains('connection reset') ||
          errStr.contains('handshake');

      if (isNet) {
        attempt++;
        if (attempt <= retries) {
          // Longer delay for mobile networks to recover
          await Future.delayed(Duration(milliseconds: 1500 * attempt));
          continue;
        }
      }
      break; // Non-network error or exhausted retries
    }
  }

  return null;
}

class _Fail extends StatelessWidget {
  final String message;
  const _Fail({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.info_outline_rounded, size: 42),
          SizedBox(height: 12),
          Text(
            'Unable to load this title.\nPlease try again.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final String? posterUrl;
  final String title;
  const _PosterCard({required this.posterUrl, required this.title});
  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.38;
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: h,
          width: h * 0.70,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F2B),
            borderRadius: BorderRadius.circular(22),
          ),
          child: posterUrl == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      posterUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (c, w, p) =>
                          p == null ? w : const _Loader(),
                      errorBuilder: (c, e, s) =>
                          const Center(child: Icon(Icons.broken_image)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String? year;
  final String? runtimeOrEp;
  final String? genre;
  const _MetaRow({this.year, this.runtimeOrEp, this.genre});
  @override
  Widget build(BuildContext context) {
    Widget dot() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(' | ', style: TextStyle(color: Colors.white60)),
    );
    final items = <Widget>[];
    if (year != null) items.add(_metaIcon(Icons.date_range, year!));
    if (runtimeOrEp != null) {
      if (items.isNotEmpty) items.add(dot());
      items.add(_metaIcon(Icons.schedule_rounded, runtimeOrEp!));
    }
    if (genre != null) {
      if (items.isNotEmpty) items.add(dot());
      items.add(_metaIcon(Icons.category_outlined, genre!));
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: items);
  }

  Widget _metaIcon(IconData i, String t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(i, size: 18, color: Colors.white70),
      const SizedBox(width: 6),
      Text(t, style: const TextStyle(color: Colors.white70)),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
  );
}

class _ExpandableText extends StatefulWidget {
  final String text;
  const _ExpandableText(this.text);
  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final span = TextSpan(
      text: widget.text,
      style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 16),
    );
    return LayoutBuilder(
      builder: (context, c) {
        final tp = TextPainter(
          text: span,
          maxLines: _expanded ? null : 4,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: c.maxWidth);
        final overflow = tp.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              span,
              maxLines: _expanded ? null : 4,
              overflow: TextOverflow.fade,
            ),
            if (overflow)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Less' : 'More'),
              ),
          ],
        );
      },
    );
  }
}

class _PeopleRow extends StatelessWidget {
  final String title;
  final List<_Person> people;
  final String imgW185;
  const _PeopleRow({
    required this.title,
    required this.people,
    required this.imgW185,
  });
  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 16),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 16),
            itemBuilder: (_, i) {
              final p = people[i];
              final img = p.profilePath != null
                  ? (p.profilePath!.startsWith('http')
                      ? p.profilePath!
                      : '$imgW185${p.profilePath}')
                  : null;
              return SizedBox(
                width: 120,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFF2A2F3B),
                      backgroundImage: img != null ? NetworkImage(img) : null,
                      child: img == null ? const Icon(Icons.person) : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.role ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemCount: people.length,
          ),
        ),
      ],
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final String? thumbUrl;
  final int number;
  final int? runtime;
  final String title;
  final String overview;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  const _EpisodeCard({
    required this.thumbUrl,
    required this.number,
    required this.runtime,
    required this.title,
    required this.overview,
    required this.onPlay,
    required this.onDownload,
  });

  static String _fmtMinutes(int? m) {
    if (m == null || m <= 0) return '';
    final hours = m ~/ 60;
    final mins = m % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPlay,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Thumbnail with E# badge + runtime overlay ----
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background image
                    thumbUrl != null
                        ? CachedNetworkImage(
                            imageUrl: thumbUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                Container(color: const Color(0xFF1A1F2B)),
                            errorWidget: (_, _, _) => Container(
                              color: const Color(0xFF1A1F2B),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.movie_outlined,
                                color: Colors.white24,
                                size: 36,
                              ),
                            ),
                          )
                        : Container(
                            color: const Color(0xFF1A1F2B),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.movie_outlined,
                              color: Colors.white24,
                              size: 36,
                            ),
                          ),

                    // Bottom gradient
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.55),
                            ],
                            stops: const [0.4, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // E# badge â€” top left
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'E$number',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),

                    // Runtime â€” bottom right
                    if (_fmtMinutes(runtime).isNotEmpty)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Text(
                          _fmtMinutes(runtime),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black),
                            ],
                          ),
                        ),
                      ),

                    // Download button â€” top right
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: onDownload,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.download_for_offline_rounded,
                            color: Colors.white.withValues(alpha: 0.9),
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ---- Title ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
            ),

            const SizedBox(height: 6),

            // ---- Description ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                overview.isNotEmpty ? overview : 'Tap to watch this episode.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.65),
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

Widget _ratingChip(double? v) {
  final t = v == null ? '-' : v.toStringAsFixed(1);

  return Container(
    height: 50,
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          children: [
            // main pill
            Container(
              height: 33,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFE7B8), // highlight
                    Color(0xFFFFC56A),
                    Color(0xFFEB8D2E),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    offset: const Offset(0, 3),
                    blurRadius: 6,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.15),
                    offset: const Offset(0, -1),
                    blurRadius: 3,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.star_rate_rounded,
                    color: Color(0xFF7C4A00),
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    t,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: Color(0xFF3B2410),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ---------- Models ----------

class _DetailBundle {
  final _Details details;
  final _Credits credits;
  _DetailBundle({required this.details, required this.credits});
}

class _Details {
  final int id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final double? voteAverage;
  final List<String> genres;
  final int? runtime;
  final List<_SeasonStub> seasons;
  final String? firstAirDate;
  final String? releaseDate;
  final List<_Video> videos;
  final String? imdbId;
  final String? trailerUrl;
  final String? contentRating;
  final String? logoPath; // TMDB title logo (English PNG)
  final String? originalLanguage; // e.g. 'en', 'es', 'ko'
  final String? status; // e.g. 'Returning Series', 'Ended', 'Canceled'
  final String? nextAirDate; // e.g. '2024-05-12'
  final int? nextEpisodeSeason;
  final int? nextEpisodeNumber;
  final String? lastAirDate;
  final int? lastEpisodeSeason;
  final int? lastEpisodeNumber;
  final int? totalSeasons;
  final int? totalEpisodes;
  final bool? inProduction;

  _Details({
    required this.id,
    required this.title,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.voteAverage,
    required this.genres,
    this.runtime,
    required this.seasons,
    this.firstAirDate,
    this.releaseDate,
    required this.videos,
    this.imdbId,
    this.trailerUrl,
    this.contentRating,
    this.logoPath,
    this.originalLanguage,
    this.status,
    this.nextAirDate,
    this.nextEpisodeSeason,
    this.nextEpisodeNumber,
    this.lastAirDate,
    this.lastEpisodeSeason,
    this.lastEpisodeNumber,
    this.totalSeasons,
    this.totalEpisodes,
    this.inProduction,
  });

  _Details copyWith({
    int? id,
    String? title,
    String? posterPath,
    String? backdropPath,
    String? overview,
    double? voteAverage,
    List<String>? genres,
    int? runtime,
    List<_SeasonStub>? seasons,
    String? firstAirDate,
    String? releaseDate,
    List<_Video>? videos,
    String? imdbId,
    String? trailerUrl,
    String? contentRating,
    String? logoPath,
    String? originalLanguage,
    String? status,
    String? nextAirDate,
    int? nextEpisodeSeason,
    int? nextEpisodeNumber,
    String? lastAirDate,
    int? lastEpisodeSeason,
    int? lastEpisodeNumber,
    int? totalSeasons,
    int? totalEpisodes,
    bool? inProduction,
  }) {
    return _Details(
      id: id ?? this.id,
      title: title ?? this.title,
      posterPath: posterPath ?? this.posterPath,
      backdropPath: backdropPath ?? this.backdropPath,
      overview: overview ?? this.overview,
      voteAverage: voteAverage ?? this.voteAverage,
      genres: genres ?? this.genres,
      runtime: runtime ?? this.runtime,
      seasons: seasons ?? this.seasons,
      firstAirDate: firstAirDate ?? this.firstAirDate,
      releaseDate: releaseDate ?? this.releaseDate,
      videos: videos ?? this.videos,
      imdbId: imdbId ?? this.imdbId,
      trailerUrl: trailerUrl ?? this.trailerUrl,
      contentRating: contentRating ?? this.contentRating,
      logoPath: logoPath ?? this.logoPath,
      originalLanguage: originalLanguage ?? this.originalLanguage,
      status: status ?? this.status,
      nextAirDate: nextAirDate ?? this.nextAirDate,
      nextEpisodeSeason: nextEpisodeSeason ?? this.nextEpisodeSeason,
      nextEpisodeNumber: nextEpisodeNumber ?? this.nextEpisodeNumber,
      lastAirDate: lastAirDate ?? this.lastAirDate,
      lastEpisodeSeason: lastEpisodeSeason ?? this.lastEpisodeSeason,
      lastEpisodeNumber: lastEpisodeNumber ?? this.lastEpisodeNumber,
      totalSeasons: totalSeasons ?? this.totalSeasons,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      inProduction: inProduction ?? this.inProduction,
    );
  }

  String? get firstGenre => genres.isEmpty ? null : genres.first;
  String? get year {
    final d = (releaseDate ?? firstAirDate);
    if (d == null || d.length < 4) return null;
    return d.substring(0, 4);
  }

  String? get languageLabel {
    if (originalLanguage == null) return null;
    final map = {
      'en': 'English',
      'hi': 'Hindi',
      'ml': 'Malayalam',
      'ta': 'Tamil',
      'te': 'Telugu',
      'kn': 'Kannada',
      'es': 'Spanish',
      'fr': 'French',
      'ko': 'Korean',
      'ja': 'Japanese',
      'zh': 'Chinese',
      'it': 'Italian',
      'de': 'German',
      'ru': 'Russian',
      'pt': 'Portuguese',
      'tr': 'Turkish',
      'bn': 'Bengali',
      'pa': 'Punjabi',
      'id': 'Indonesian',
    };
    final name = map[originalLanguage!] ?? originalLanguage!.toUpperCase();
    return name;
  }

  String? get metaDuration {
    if (runtime != null && runtime! > 0) {
      final h = runtime! ~/ 60;
      final m = runtime! % 60;
      return h > 0 ? '${h}h ${m}m' : '$m Minutes';
    }
    return null;
  }

  String get displayTitle {
    // Regex to match anything in square brackets like [Hindi], [CAM], [Dual Audio] etc.
    // Also trims surrounding whitespace.
    return title.replaceAll(RegExp(r'\s*\[.*?\]'), '').trim();
  }

  String? get youtubeTrailerKey {
    final yt = videos.firstWhere(
      (v) =>
          v.site?.toLowerCase() == 'youtube' &&
          v.type?.toLowerCase() == 'trailer',
      orElse: () => _Video.empty,
    );
    return yt.key;
  }

  factory _Details.fromJson(Map<String, dynamic> j, String mediaType) {
    final genres =
        (j['genres'] as List<dynamic>?)
            ?.map((e) => (e as Map<String, dynamic>)['name'] as String)
            .toList() ??
        <String>[];
    final videosJson = ((j['videos'] as Map?)?['results'] as List?) ?? const [];
    final videos = videosJson
        .cast<Map>()
        .map((e) => _Video.fromJson(e.cast<String, dynamic>()))
        .toList();

    String? imdb;
    try {
      if (j['external_ids'] is Map) {
        imdb = (j['external_ids'] as Map)['imdb_id'] as String?;
      }
    } catch (_) {
      imdb = null;
    }

    String? parsedLogo;
    try {
      final logos = j['images']?['logos'] as List?;
      if (logos != null && logos.isNotEmpty) {
        final enLogo = logos.firstWhere((img) => img['iso_639_1'] == 'en', orElse: () => logos.first);
        parsedLogo = enLogo['file_path'];
        if (parsedLogo != null) {
          parsedLogo = 'https://image.tmdb.org/t/p/w500$parsedLogo';
        }
      }
    } catch (_) {}

    return _Details(
      id: (j['id'] ?? 0) as int,
      title: (j['title'] ?? j['name'] ?? 'Untitled') as String,
      posterPath: j['poster_path'] as String?,
      backdropPath: j['backdrop_path'] as String?,
      overview: j['overview'] as String?,
      voteAverage: (j['vote_average'] is num)
          ? (j['vote_average'] + 0.0)
          : null,
      genres: genres,
      runtime: mediaType == 'movie' ? (j['runtime'] as int?) : null,
      seasons: mediaType == 'tv'
          ? ((j['seasons'] as List<dynamic>? ?? const [])
                .map(
                  (e) =>
                      _SeasonStub.fromJson((e as Map).cast<String, dynamic>()),
                )
                .toList())
          : <_SeasonStub>[],
      firstAirDate: j['first_air_date'] as String?,
      releaseDate: j['release_date'] as String?,
      videos: videos,
      imdbId: imdb,
      logoPath: parsedLogo,
      contentRating: _parseRating(j, mediaType),
      originalLanguage: j['original_language'] as String?,
      status: j['status'] as String?,
      nextAirDate: j['next_episode_to_air']?['air_date'] as String?,
      nextEpisodeSeason: j['next_episode_to_air']?['season_number'] as int?,
      nextEpisodeNumber: j['next_episode_to_air']?['episode_number'] as int?,
    );
  }

  static String? _parseRating(Map<String, dynamic> j, String mediaType) {
    try {
      if (mediaType == 'movie') {
        final rd = j['release_dates']?['results'] as List?;
        if (rd != null) {
          // Preference for India (IN) then US
          final inRating = rd.firstWhere(
            (r) => r['iso_3166_1'] == 'IN',
            orElse: () => null,
          );
          if (inRating != null &&
              (inRating['release_dates'] as List).isNotEmpty) {
            return inRating['release_dates'][0]['certification'];
          }
          final usRating = rd.firstWhere(
            (r) => r['iso_3166_1'] == 'US',
            orElse: () => null,
          );
          if (usRating != null &&
              (usRating['release_dates'] as List).isNotEmpty) {
            return usRating['release_dates'][0]['certification'];
          }
        }
      } else {
        final cr = j['content_ratings']?['results'] as List?;
        if (cr != null) {
          final inRating = cr.firstWhere(
            (r) => r['iso_3166_1'] == 'IN',
            orElse: () => null,
          );
          if (inRating != null) return inRating['rating'];
          final usRating = cr.firstWhere(
            (r) => r['iso_3166_1'] == 'US',
            orElse: () => null,
          );
          if (usRating != null) return usRating['rating'];
        }
      }
    } catch (_) {}
    return null;
  }
}

class _SeasonStub {
  final int seasonNumber;
  final String? name;
  final int? episodeCount;
  _SeasonStub({required this.seasonNumber, this.name, this.episodeCount});
  factory _SeasonStub.fromJson(Map<String, dynamic> j) => _SeasonStub(
    seasonNumber: (j['season_number'] ?? 0) as int,
    name: j['name'] as String?,
    episodeCount: (j['episode_count'] ?? j['maxEp']) as int?,
  );
}

class _Video {
  final String? key;
  final String? site;
  final String? type;
  _Video({this.key, this.site, this.type});
  static _Video empty = _Video();
  factory _Video.fromJson(Map<String, dynamic> j) => _Video(
    key: j['key'] as String?,
    site: j['site'] as String?,
    type: j['type'] as String?,
  );
}

class _Credits {
  final List<_Person> cast;
  final List<_Person> directors;
  final List<_Person> writers;
  _Credits({
    required this.cast,
    required this.directors,
    required this.writers,
  });

  factory _Credits.fromJson(Map<String, dynamic> j) {
    final cast = ((j['cast'] as List?) ?? const [])
        .cast<Map>()
        .map((e) => _Person.fromCast(e.cast<String, dynamic>()))
        .toList();
    final crewAll = ((j['crew'] as List?) ?? const [])
        .cast<Map>()
        .map((e) => _Person.fromCrew(e.cast<String, dynamic>()))
        .toList();
    final directors = crewAll.where((p) => p.role == 'Director').toList();
    final writers = crewAll
        .where(
          (p) =>
              p.role == 'Writer' || p.role == 'Screenplay' || p.role == 'Story',
        )
        .toList();
    return _Credits(cast: cast, directors: directors, writers: writers);
  }
}

class _Person {
  final int id;
  final String name;
  final String? profilePath;
  final String? role;
  _Person({required this.id, required this.name, this.profilePath, this.role});

  factory _Person.fromCast(Map<String, dynamic> j) => _Person(
    id: (j['id'] ?? 0) as int,
    name: (j['name'] ?? 'Unknown') as String,
    profilePath: j['profile_path'] as String?,
    role: j['character'] as String?,
  );

  factory _Person.fromCrew(Map<String, dynamic> j) => _Person(
    id: (j['id'] ?? 0) as int,
    name: (j['name'] ?? 'Unknown') as String,
    profilePath: j['profile_path'] as String?,
    role: j['job'] as String?,
  );
}

class _TvSeason {
  final int seasonNumber;
  final List<_Episode> episodes;
  _TvSeason({required this.seasonNumber, required this.episodes});
  factory _TvSeason.fromJson(Map<String, dynamic> j) => _TvSeason(
    seasonNumber: (j['season_number'] ?? 0) as int,
    episodes: ((j['episodes'] as List?) ?? const [])
        .cast<Map>()
        .map((e) => _Episode.fromJson(e.cast<String, dynamic>()))
        .toList(),
  );
}

class _Episode {
  final int episodeNumber;
  final String? name;
  final int? runtime;
  final String? overview;
  final String? stillPath;
  _Episode({
    required this.episodeNumber,
    this.name,
    this.runtime,
    this.overview,
    this.stillPath,
  });
  factory _Episode.fromJson(Map<String, dynamic> j) => _Episode(
    episodeNumber: (j['episode_number'] ?? 0) as int,
    name: j['name'] as String?,
    runtime: j['runtime'] as int?,
    overview: j['overview'] as String?,
    stillPath: j['still_path'] as String?,
  );
}

class _BackdropHalf extends StatelessWidget {
  final String? url;
  final double height;
  const _BackdropHalf({required this.url, required this.height});

  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.shrink();

    final bg = Theme.of(context).scaffoldBackgroundColor;

    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ShaderMask(
              shaderCallback: (Rect rect) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xFFFFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: [0.0, 0.70, 1.0],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstIn,
              child: CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [bg, bg.withValues(alpha: 0.0)],
                    stops: const [0.0, 0.35],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Placeholder for WidgetStateColor used above; keep it consistent with your app.
class WidgetStateColor {
  static const transparent = Colors.transparent;
}

class AppLoader extends StatelessWidget {
  final double size;
  const AppLoader({this.size = 80, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Lottie.asset(
          'assets/animations/loader.json', // your loader path
          repeat: true,
        ),
      ),
    );
  }
}

class _PlayButton3D extends StatelessWidget {
  final VoidCallback onPressed;
  final String mediaType;
  final WatchHistoryItem? historyItem;

  const _PlayButton3D({
    required this.onPressed,
    required this.mediaType,
    this.historyItem,
  });

  @override
  Widget build(BuildContext context) {
    const baseColor = Color(0xFFFFB561);
    const darkBase = Color(0xFFE28A2B);

    final isTV = mediaType == 'tv' || mediaType == 'series';
    final isContinue = historyItem != null;

    final mainText = isContinue ? 'Continue Watch' : 'Watch Now';
    String? subText;

    if (isTV) {
      if (isContinue && historyItem!.season != null) {
        subText = 'S${historyItem!.season}.E${historyItem!.episode}';
      } else {
        subText = 'S1.E1';
      }
    }

    return GestureDetector(
      onTap: onPressed,
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: Stack(
          children: [
            // Bottom shadow/depth
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: darkBase.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            // Main button
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFD59E), baseColor, Color(0xFFF7A23B)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      offset: const Offset(0, 3),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Color(0xFF3B2410),
                          size: 22,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          mainText.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: Color(0xFF3B2410),
                          ),
                        ),
                        if (subText != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.black12,
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              subText,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF3B2410),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButton3D extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;

  const _IconButton3D({required this.onPressed, required this.icon});

  @override
  Widget build(BuildContext context) {
    const baseColor = Color(0xFF1F2531);
    const darkBase = Color(0xFF11151D);

    return GestureDetector(
      onTap: onPressed,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          children: [
            // bottom shadow "plate"
            Positioned(
              left: 0,
              right: 0,
              top: 3,
              child: Container(
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
            // main circular button
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF343B49), baseColor, darkBase],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    offset: const Offset(0, 4),
                    blurRadius: 8,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.08),
                    offset: const Offset(0, -1),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: Center(child: Icon(icon, size: 20, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton3D extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;

  const _SecondaryButton3D({
    required this.onPressed,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 50, maxWidth: 100),
        child: SizedBox(
          height: 46,
          child: Stack(
            children: [
              // Bottom shadow/depth
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[400]!.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              // Main button
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white,
                        Colors.grey[100]!,
                        Colors.grey[300]!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        offset: const Offset(0, 3),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: Colors.black, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            label.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                              color: Colors.black,
                            ),
                          ),
                        ],
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
